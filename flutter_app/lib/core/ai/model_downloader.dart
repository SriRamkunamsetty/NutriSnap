import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class ModelDownloadException implements Exception {
  ModelDownloadException(this.message, {this.retryable = true});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();
}

/// Cooperative cancellation for [ModelDownloader].
class DownloadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

typedef DownloadProgress = void Function(int received, int total);

/// Resumable, integrity-checked file download for the multi-gigabyte model.
///
/// Why not the plugin's downloader? On Android, WorkManager stops any
/// background task after ~9 minutes, and HuggingFace URLs can't be paused and
/// resumed by that downloader, so a 2.6 GB download restarted from zero
/// forever. This downloader:
///
///  * writes to `<file>.part` and **resumes from the bytes already on disk**
///    with HTTP Range requests, across retries, network drops and app restarts;
///  * retries transient failures with backoff, but only gives up after several
///    attempts in a row that made **no** progress;
///  * verifies the exact size (and optional SHA-256) before the file is
///    renamed into place, so a truncated or corrupt model is never loaded.
class ModelDownloader {
  ModelDownloader({
    required this.url,
    required this.destination,
    required this.expectedBytes,
    this.expectedSha256,
    this.authToken,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String url;
  final File destination;

  /// Exact size the finished file must have. Guards against truncation.
  final int? expectedBytes;

  /// Lower-case hex SHA-256 of the finished file, if known.
  final String? expectedSha256;
  final String? authToken;
  final HttpClient _client;

  File get partFile => File('${destination.path}.part');

  static const _maxStalledAttempts = 6;
  static const _stallTimeout = Duration(seconds: 30);
  static const _maxRedirects = 6;

  /// Bytes already downloaded in a previous session (0 if none).
  Future<int> partialBytes() async =>
      await partFile.exists() ? await partFile.length() : 0;

  /// Downloads (or resumes) until complete. [onVerifying] fires before the
  /// SHA-256 pass, which takes a few seconds on a phone.
  Future<void> download({
    required DownloadProgress onProgress,
    required DownloadCancelToken cancel,
    VoidCallback? onVerifying,
  }) async {
    await destination.parent.create(recursive: true);

    if (await destination.exists() && await _isValidSize(destination)) {
      return; // already complete
    }

    var stalled = 0;
    while (true) {
      _throwIfCancelled(cancel);
      final before = await partialBytes();
      try {
        final done = await _attempt(onProgress, cancel);
        if (done) break;
      } on ModelDownloadCancelled {
        rethrow;
      } on ModelDownloadException catch (e) {
        if (!e.retryable) rethrow;
        debugPrint('[ModelDownloader] attempt failed: ${e.message}');
      } on SocketException catch (e) {
        debugPrint('[ModelDownloader] network error: $e');
      } on HttpException catch (e) {
        debugPrint('[ModelDownloader] http error: $e');
      } on TimeoutException {
        debugPrint('[ModelDownloader] stalled connection');
      } on HandshakeException catch (e) {
        debugPrint('[ModelDownloader] TLS error: $e');
      } on FileSystemException catch (e) {
        if (_isOutOfSpace(e)) {
          throw ModelDownloadException(
            'Not enough free storage. Free up about 3 GB and try again.',
            retryable: false,
          );
        }
        rethrow;
      }

      final after = await partialBytes();
      stalled = after > before ? 0 : stalled + 1;
      if (stalled >= _maxStalledAttempts) {
        throw ModelDownloadException(
          'The download keeps failing. Check your connection and try again; '
          'it will continue from where it stopped.',
        );
      }
      // Back off (capped) before the next attempt.
      final wait = Duration(seconds: (1 << stalled.clamp(0, 4)).clamp(1, 15));
      await _sleep(wait, cancel);
    }

    // Size check before anything is trusted.
    final part = partFile;
    final size = await part.length();
    if (expectedBytes != null && size != expectedBytes) {
      await part.delete();
      throw ModelDownloadException(
        'The downloaded file was incomplete. Please download again.',
      );
    }

    if (expectedSha256 != null) {
      onVerifying?.call();
      final actual = await Isolate.run(() => _sha256Of(part.path));
      if (actual != expectedSha256!.toLowerCase()) {
        await part.delete();
        throw ModelDownloadException(
          'The downloaded file failed its integrity check. Please download again.',
        );
      }
    }

    if (await destination.exists()) await destination.delete();
    await part.rename(destination.path);
  }

  /// One connection. Returns true when the whole file is on disk.
  Future<bool> _attempt(DownloadProgress onProgress, DownloadCancelToken cancel) async {
    final part = partFile;
    var received = await partialBytes();

    if (expectedBytes != null && received > expectedBytes!) {
      await part.delete(); // corrupt leftover
      received = 0;
    }
    if (expectedBytes != null && received == expectedBytes) return true;

    final response = await _open(received);
    try {
      final status = response.statusCode;

      if (status == 416) {
        // Range not satisfiable: our partial is inconsistent. Start over.
        await response.drain<void>();
        if (await part.exists()) await part.delete();
        return false;
      }
      if (status == 401 || status == 403) {
        throw ModelDownloadException(
          'The model server refused the download (access denied).',
          retryable: false,
        );
      }
      if (status == 404) {
        throw ModelDownloadException(
          'The model file was not found on the server.',
          retryable: false,
        );
      }
      if (status != 200 && status != 206) {
        throw ModelDownloadException('Server error ($status).');
      }

      // A 200 means the server ignored Range: restart from the beginning.
      if (status == 200 && received > 0) {
        received = 0;
        await part.writeAsBytes(const [], flush: true);
      }

      final total = _totalSize(response, received);
      final raf = await part.open(mode: FileMode.append);
      try {
        var sinceFlush = 0;
        await for (final chunk in response.timeout(_stallTimeout)) {
          _throwIfCancelled(cancel);
          await raf.writeFrom(chunk);
          received += chunk.length;
          sinceFlush += chunk.length;
          if (sinceFlush >= 8 * 1024 * 1024) {
            await raf.flush(); // make resume points durable
            sinceFlush = 0;
          }
          onProgress(received, total ?? expectedBytes ?? 0);
        }
        await raf.flush();
      } finally {
        await raf.close();
      }

      final finalTotal = total ?? expectedBytes;
      return finalTotal != null && received >= finalTotal;
    } finally {
      // Leaving the `await for` early (cancel/error) cancels the subscription,
      // which closes the underlying connection; nothing more to release.
    }
  }

  /// GET with a Range header, following redirects manually so the header is
  /// preserved and the auth token is only sent to the original host.
  Future<HttpClientResponse> _open(int from) async {
    var uri = Uri.parse(url);
    final originalHost = uri.host;

    for (var i = 0; i <= _maxRedirects; i++) {
      final request = await _client.getUrl(uri).timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'NutriSnap/1.0');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (from > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      if (authToken != null && authToken!.isNotEmpty && uri.host == originalHost) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
      }
      final response = await request.close().timeout(const Duration(seconds: 30));

      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw ModelDownloadException('Bad redirect from server.');
        }
        uri = uri.resolve(location);
        continue;
      }
      return response;
    }
    throw ModelDownloadException('Too many redirects.');
  }

  int? _totalSize(HttpClientResponse r, int received) {
    final range = r.headers.value(HttpHeaders.contentRangeHeader);
    if (range != null) {
      final total = int.tryParse(range.split('/').last);
      if (total != null) return total;
    }
    final len = r.contentLength;
    if (len >= 0) return r.statusCode == 206 ? received + len : len;
    return null;
  }

  Future<bool> _isValidSize(File f) async =>
      expectedBytes == null || await f.length() == expectedBytes;

  bool _isOutOfSpace(FileSystemException e) {
    final code = e.osError?.errorCode;
    return code == 28 /* ENOSPC */ || code == 112 /* ERROR_DISK_FULL */;
  }

  void _throwIfCancelled(DownloadCancelToken c) {
    if (c.isCancelled) throw const ModelDownloadCancelled();
  }

  Future<void> _sleep(Duration d, DownloadCancelToken c) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      _throwIfCancelled(c);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  void close() => _client.close(force: true);

  /// Streams the file through SHA-256 without loading it into memory.
  static Future<String> _sha256Of(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  /// Deletes the finished file and any partial download.
  Future<void> deleteAll() async {
    for (final f in [destination, partFile]) {
      if (await f.exists()) await f.delete();
    }
  }
}
