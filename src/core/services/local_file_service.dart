import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for LocalFileService
final localFileServiceProvider = Provider<LocalFileService>((ref) {
  return LocalFileService();
});

/// NutriSnap AI - On-Device Local File Service
/// Handles saving captured food images and profile pictures directly to the
/// local application directory instead of relying on external cloud storage.
class LocalFileService {
  static final LocalFileService _instance = LocalFileService._internal();
  factory LocalFileService() => _instance;
  LocalFileService._internal();

  Directory? _baseDir;
  Directory? _profilesDir;
  Directory? _scansDir;
  Directory? _bodyScansDir;
  bool _initialized = false;

  /// In-memory cache fallback for environments without direct disk access
  final Map<String, Uint8List> _memoryFileCache = {};

  /// Initialize local storage directory hierarchy
  Future<void> initialize({String? customBasePath}) async {
    if (_initialized && customBasePath == null) return;

    try {
      if (kIsWeb) {
        _initialized = true;
        debugPrint('[LocalFileService] Initialized in Web mode (Base64/Memory)');
        return;
      }

      if (customBasePath != null) {
        _baseDir = Directory(customBasePath);
      } else {
        // Use standard local application directory
        final appDir = Directory('${Directory.systemTemp.path}/nutrisnap_local_storage');
        _baseDir = appDir;
      }

      if (!await _baseDir!.exists()) {
        await _baseDir!.create(recursive: true);
      }

      _profilesDir = Directory('${_baseDir!.path}/profiles');
      _scansDir = Directory('${_baseDir!.path}/food_scans');
      _bodyScansDir = Directory('${_baseDir!.path}/body_scans');

      await Future.wait([
        if (!await _profilesDir!.exists()) _profilesDir!.create(recursive: true),
        if (!await _scansDir!.exists()) _scansDir!.create(recursive: true),
        if (!await _bodyScansDir!.exists()) _bodyScansDir!.create(recursive: true),
      ]);

      _initialized = true;
      debugPrint('[LocalFileService] Initialized with local path: ${_baseDir!.path}');
    } catch (e) {
      debugPrint('[LocalFileService] Error initializing directory: $e. Falling back to memory/dataUri.');
      _initialized = true;
    }
  }

  Future<void> _ensureInit() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// Save profile picture to local app directory
  /// Returns the local absolute file path or base64 data URI
  Future<String> saveProfilePicture(dynamic source, {String? userId}) async {
    await _ensureInit();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanUid = userId?.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_') ?? 'user';
    final fileName = 'profile_${cleanUid}_$timestamp.jpg';

    Uint8List bytes;
    if (source is File) {
      bytes = await source.readAsBytes();
    } else if (source is Uint8List) {
      bytes = source;
    } else if (source is String && source.startsWith('data:image')) {
      final base64Part = source.split(',').last;
      bytes = base64Decode(base64Part);
    } else {
      throw ArgumentError('Unsupported source type for profile picture: ${source.runtimeType}');
    }

    // Web or in-memory fallback
    if (kIsWeb || _profilesDir == null) {
      final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _memoryFileCache[fileName] = bytes;
      return dataUri;
    }

    try {
      final targetFile = File('${_profilesDir!.path}/$fileName');
      await targetFile.writeAsBytes(bytes, flush: true);
      debugPrint('[LocalFileService] Profile photo saved to local file: ${targetFile.path}');
      return targetFile.path;
    } catch (e) {
      debugPrint('[LocalFileService] Write to disk failed: $e, using data URI fallback');
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
  }

  /// Save captured food scan photo to local app directory
  /// Returns the local absolute file path or base64 data URI
  Future<String> saveFoodImage(dynamic source, {String? scanId}) async {
    await _ensureInit();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanId = scanId?.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_') ?? 'scan';
    final fileName = 'food_${cleanId}_$timestamp.jpg';

    Uint8List bytes;
    if (source is File) {
      bytes = await source.readAsBytes();
    } else if (source is Uint8List) {
      bytes = source;
    } else if (source is String && source.startsWith('data:image')) {
      final base64Part = source.split(',').last;
      bytes = base64Decode(base64Part);
    } else {
      throw ArgumentError('Unsupported source type for food image: ${source.runtimeType}');
    }

    if (kIsWeb || _scansDir == null) {
      final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _memoryFileCache[fileName] = bytes;
      return dataUri;
    }

    try {
      final targetFile = File('${_scansDir!.path}/$fileName');
      await targetFile.writeAsBytes(bytes, flush: true);
      debugPrint('[LocalFileService] Food image saved locally: ${targetFile.path}');
      return targetFile.path;
    } catch (e) {
      debugPrint('[LocalFileService] Write failed: $e, using data URI fallback');
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
  }

  /// Save body scan photo to local app directory
  Future<String> saveBodyScanImage(dynamic source) async {
    await _ensureInit();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'body_scan_$timestamp.jpg';

    Uint8List bytes;
    if (source is File) {
      bytes = await source.readAsBytes();
    } else if (source is Uint8List) {
      bytes = source;
    } else if (source is String && source.startsWith('data:image')) {
      final base64Part = source.split(',').last;
      bytes = base64Decode(base64Part);
    } else {
      throw ArgumentError('Unsupported source type for body scan image: ${source.runtimeType}');
    }

    if (kIsWeb || _bodyScansDir == null) {
      final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _memoryFileCache[fileName] = bytes;
      return dataUri;
    }

    try {
      final targetFile = File('${_bodyScansDir!.path}/$fileName');
      await targetFile.writeAsBytes(bytes, flush: true);
      return targetFile.path;
    } catch (e) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
  }

  /// Read local image file as bytes
  Future<Uint8List?> getImageBytes(String pathOrDataUri) async {
    if (pathOrDataUri.startsWith('data:image')) {
      try {
        final commaIndex = pathOrDataUri.indexOf(',');
        final b64 = commaIndex != -1 ? pathOrDataUri.substring(commaIndex + 1) : pathOrDataUri;
        return base64Decode(b64);
      } catch (_) {
        return null;
      }
    }

    if (_memoryFileCache.containsKey(pathOrDataUri)) {
      return _memoryFileCache[pathOrDataUri];
    }

    final file = File(pathOrDataUri);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// Delete local image file
  Future<bool> deleteImage(String pathOrUri) async {
    if (pathOrUri.startsWith('data:')) return true;
    try {
      final file = File(pathOrUri);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      debugPrint('[LocalFileService] Error deleting file $pathOrUri: $e');
    }
    return false;
  }

  /// Get total storage size used by local images in bytes
  Future<int> getTotalLocalStorageBytes() async {
    if (kIsWeb || _baseDir == null) {
      int total = 0;
      _memoryFileCache.forEach((_, v) => total += v.length);
      return total;
    }

    int totalBytes = 0;
    try {
      if (await _baseDir!.exists()) {
        await for (final entity in _baseDir!.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalBytes += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalFileService] Error calculating size: $e');
    }
    return totalBytes;
  }

  /// Remove orphaned images older than specified duration
  Future<int> purgeImagesOlderThan(Duration maxAge) async {
    if (kIsWeb || _baseDir == null) return 0;

    int purgedCount = 0;
    final cutoff = DateTime.now().subtract(maxAge);

    try {
      if (await _scansDir != null && await _scansDir!.exists()) {
        await for (final entity in _scansDir!.list()) {
          if (entity is File) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              purgedCount++;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalFileService] Error during image purge: $e');
    }
    return purgedCount;
  }
}
