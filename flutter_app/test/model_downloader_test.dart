import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/ai/model_downloader.dart';

/// A tiny HTTP server that behaves like HuggingFace's CDN: 302 redirect, then
/// Range support. Can be told to drop the connection part-way through.
class FakeCdn {
  FakeCdn(this.data, {this.dropAfter, this.supportRange = true});

  final Uint8List data;

  /// Bytes to send on each *attempt* before killing the connection.
  final int? dropAfter;
  final bool supportRange;

  late HttpServer server;
  final requestedRanges = <String?>[];
  int connections = 0;

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}/resolve/model.bin');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/resolve/model.bin') {
        req.response.statusCode = 302;
        req.response.headers.set('location', '/cdn/model.bin');
        await req.response.close();
        return;
      }
      connections++;
      final range = req.headers.value('range');
      requestedRanges.add(range);

      var start = 0;
      var partial = false;
      if (range != null && supportRange) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        partial = true;
      }
      final body = data.sublist(start);
      final limit = dropAfter == null ? body.length : min(dropAfter!, body.length);

      // Speak raw HTTP so a "network drop" is a real socket destroy mid-body.
      final socket = await req.response.detachSocket(writeHeaders: false);
      final head = StringBuffer()
        ..write(partial ? 'HTTP/1.1 206 Partial Content\r\n' : 'HTTP/1.1 200 OK\r\n')
        ..write('content-length: ${body.length}\r\n')
        ..write('accept-ranges: bytes\r\n');
      if (partial) {
        head.write('content-range: bytes $start-${data.length - 1}/${data.length}\r\n');
      }
      head.write('connection: close\r\n\r\n');
      try {
        socket.add(head.toString().codeUnits);
        socket.add(body.sublist(0, limit));
        await socket.flush();
        if (limit < body.length) {
          socket.destroy(); // drop mid-body
        } else {
          await socket.close();
        }
      } on SocketException {
        // The client hung up (e.g. the user paused); nothing to do.
        socket.destroy();
      }
    });
  }

  Future<void> stop() => server.close(force: true);
}

Uint8List randomBytes(int n) {
  final r = Random(42);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  late Directory dir;
  late File dest;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dl_test_');
    dest = File('${dir.path}/models/model.bin');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ModelDownloader make(FakeCdn cdn, {int? bytes, String? sha}) => ModelDownloader(
        url: cdn.url.toString(),
        destination: dest,
        expectedBytes: bytes ?? cdn.data.length,
        expectedSha256: sha,
      );

  test('downloads through a redirect and verifies size + SHA-256', () async {
    final data = randomBytes(3 * 1024 * 1024);
    final cdn = FakeCdn(data);
    await cdn.start();
    addTearDown(cdn.stop);

    final progress = <int>[];
    await make(cdn, sha: sha256.convert(data).toString()).download(
      onProgress: (r, t) => progress.add(r),
      cancel: DownloadCancelToken(),
    );

    expect(await dest.readAsBytes(), data);
    expect(File('${dest.path}.part').existsSync(), isFalse);
    expect(progress.last, data.length);
  });

  test('REGRESSION: connection drops mid-download -> resumes, never restarts from zero', () async {
    final data = randomBytes(4 * 1024 * 1024);
    // Every attempt dies after 1 MiB, so it needs ~4 attempts.
    final cdn = FakeCdn(data, dropAfter: 1024 * 1024);
    await cdn.start();
    addTearDown(cdn.stop);

    var maxReceived = 0;
    var wentBackwards = false;
    await make(cdn).download(
      onProgress: (r, t) {
        if (r < maxReceived) wentBackwards = true; // progress must be monotonic
        maxReceived = max(maxReceived, r);
      },
      cancel: DownloadCancelToken(),
    );

    expect(await dest.readAsBytes(), data);
    expect(wentBackwards, isFalse, reason: 'progress must never reset');
    expect(cdn.connections, greaterThan(1));
    // Every retry after the first must ask for the remainder, not byte 0.
    final resumed = cdn.requestedRanges.skip(1);
    expect(resumed.every((r) => r != null && r != 'bytes=0-'), isTrue);
    expect(maxReceived, data.length); // and never exceeds 100%
  });

  test('resumes a partial file left by a previous app session', () async {
    final data = randomBytes(2 * 1024 * 1024);
    final cdn = FakeCdn(data);
    await cdn.start();
    addTearDown(cdn.stop);

    await dest.parent.create(recursive: true);
    await File('${dest.path}.part').writeAsBytes(data.sublist(0, 700000));

    final dl = make(cdn);
    expect(await dl.partialBytes(), 700000);
    await dl.download(onProgress: (_, __) {}, cancel: DownloadCancelToken());

    expect(await dest.readAsBytes(), data);
    expect(cdn.requestedRanges.first, 'bytes=700000-');
  });

  test('server that ignores Range restarts cleanly and still produces a correct file', () async {
    final data = randomBytes(1024 * 1024);
    final cdn = FakeCdn(data, supportRange: false);
    await cdn.start();
    addTearDown(cdn.stop);

    await dest.parent.create(recursive: true);
    await File('${dest.path}.part').writeAsBytes(data.sublist(0, 300000));

    await make(cdn).download(onProgress: (_, __) {}, cancel: DownloadCancelToken());
    expect(await dest.readAsBytes(), data);
  });

  test('a wrong-size file is rejected and deleted, never installed', () async {
    final data = randomBytes(500000);
    final cdn = FakeCdn(data);
    await cdn.start();
    addTearDown(cdn.stop);

    // Expecting a size the server can't satisfy -> corrupt/truncated result.
    final dl = make(cdn, bytes: data.length + 10);
    await expectLater(
      dl.download(onProgress: (_, __) {}, cancel: DownloadCancelToken()).timeout(const Duration(seconds: 60)),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(dest.existsSync(), isFalse);
  });

  test('a wrong SHA-256 is rejected and deleted', () async {
    final data = randomBytes(400000);
    final cdn = FakeCdn(data);
    await cdn.start();
    addTearDown(cdn.stop);

    await expectLater(
      make(cdn, sha: 'deadbeef').download(onProgress: (_, __) {}, cancel: DownloadCancelToken()),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(dest.existsSync(), isFalse);
    expect(File('${dest.path}.part').existsSync(), isFalse);
  });

  test('cancel keeps the partial bytes so the user can resume', () async {
    final data = randomBytes(8 * 1024 * 1024);
    final cdn = FakeCdn(data);
    await cdn.start();
    addTearDown(cdn.stop);

    final cancel = DownloadCancelToken();
    final dl = make(cdn);
    await expectLater(
      dl.download(
        onProgress: (r, _) {
          if (r > 1024 * 1024) cancel.cancel();
        },
        cancel: cancel,
      ),
      throwsA(isA<ModelDownloadCancelled>()),
    );
    expect(await dl.partialBytes(), greaterThan(0));
    expect(dest.existsSync(), isFalse);

    // ...and a fresh attempt finishes the job.
    await make(cdn).download(onProgress: (_, __) {}, cancel: DownloadCancelToken());
    expect(await dest.readAsBytes(), data);
  });

  test('404 fails fast without retrying', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var hits = 0;
    server.listen((r) async {
      hits++;
      r.response.statusCode = 404;
      await r.response.close();
    });
    final dl = ModelDownloader(
      url: 'http://127.0.0.1:${server.port}/x',
      destination: dest,
      expectedBytes: 10,
    );
    await expectLater(
      dl.download(onProgress: (_, __) {}, cancel: DownloadCancelToken()),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(hits, 1);
  });
}
