import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum ImageKind { scan, profile, body }

/// Private, on-device image storage inside the app's documents directory.
///
/// The database only ever stores paths *relative* to [root] (e.g.
/// `scans/3f2a....jpg`). Absolute container paths change on iOS between app
/// updates and restores, so they must never be persisted.
class ImageStore {
  ImageStore(this.root);

  final Directory root;
  static const _uuid = Uuid();

  static Future<ImageStore> open({Directory? root}) async {
    final dir = root ??
        Directory(p.join((await getApplicationDocumentsDirectory()).path, 'images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return ImageStore(dir);
  }

  String _folder(ImageKind kind) => switch (kind) {
        ImageKind.scan => 'scans',
        ImageKind.profile => 'profile',
        ImageKind.body => 'body',
      };

  /// Rejects anything that could escape [root] (used for restored backups too).
  bool isSafeRelative(String rel) {
    if (rel.isEmpty || p.isAbsolute(rel)) return false;
    final normalized = p.normalize(rel);
    return !normalized.startsWith('..') && !normalized.contains('${p.separator}..');
  }

  /// Writes [bytes] and returns the relative path.
  Future<String> saveBytes(Uint8List bytes, ImageKind kind,
      {String extension = 'jpg'}) async {
    final rel = p.join(_folder(kind), '${_uuid.v4()}.$extension');
    final file = File(p.join(root.path, rel));
    await file.parent.create(recursive: true);
    // Write to a temp name first so a crash never leaves a truncated image.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return rel;
  }

  /// Copies a picked/captured file into private storage.
  Future<String> saveFile(File source, ImageKind kind) async {
    final ext = p.extension(source.path).replaceFirst('.', '').toLowerCase();
    return saveBytes(await source.readAsBytes(), kind,
        extension: ext.isEmpty ? 'jpg' : ext);
  }

  /// Absolute path for a stored relative path, or null when unset/unsafe.
  String? absolutePath(String? rel) {
    if (rel == null || rel.isEmpty || !isSafeRelative(rel)) return null;
    return p.join(root.path, rel);
  }

  /// Converts an absolute path inside [root] back to a relative one.
  /// Returns null for paths outside the store (e.g. transient picker files).
  String? relativize(String? path) {
    if (path == null || path.isEmpty) return null;
    if (!p.isAbsolute(path)) return isSafeRelative(path) ? path : null;
    if (!p.isWithin(root.path, path)) return null;
    return p.relative(path, from: root.path);
  }

  Future<Uint8List?> read(String? rel) async {
    final abs = absolutePath(rel);
    if (abs == null) return null;
    final f = File(abs);
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> delete(String? rel) async {
    final abs = absolutePath(rel);
    if (abs == null) return;
    try {
      final f = File(abs);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Best effort: an undeletable orphan must not fail the caller.
    }
  }

  Future<int> sizeBytes() async {
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> deleteAll() async {
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }
}
