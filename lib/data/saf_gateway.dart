import 'dart:convert';

import 'package:flutter/services.dart';

class SafDocument {
  const SafDocument({
    required this.uri,
    required this.name,
    required this.size,
    required this.mtimeMs,
    required this.exists,
  });

  final String uri;
  final String name;
  final int size;
  final int mtimeMs;
  final bool exists;

  factory SafDocument.fromMap(Map<Object?, Object?> map) => SafDocument(
        uri: (map['uri'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        size: (map['size'] as num?)?.toInt() ?? -1,
        mtimeMs: (map['mtime'] as num?)?.toInt() ?? -1,
        exists: (map['exists'] as bool?) ?? false,
      );
}

class SafChild {
  const SafChild({
    required this.uri,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.mtimeMs,
  });

  final String uri;
  final String name;
  final bool isDirectory;
  final int size;
  final int mtimeMs;

  factory SafChild.fromMap(Map<Object?, Object?> map) => SafChild(
        uri: (map['uri'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        isDirectory: (map['isDirectory'] as bool?) ?? false,
        size: (map['size'] as num?)?.toInt() ?? -1,
        mtimeMs: (map['mtime'] as num?)?.toInt() ?? -1,
      );
}

enum SafErrorKind { permission, io, unavailable, busy, missing, unknown }

class SafException implements Exception {
  const SafException(this.kind, this.message);

  final SafErrorKind kind;
  final String message;

  @override
  String toString() => 'SafException(${kind.name}): $message';
}

abstract class SafGateway {
  Future<SafDocument?> pickFile();
  Future<SafDocument?> pickDirectory();
  Future<SafDocument?> createFile({required String suggestedName, String mimeType});
  Future<Uint8List> readBytes(String uri);
  Future<SafDocument> writeBytes(String uri, Uint8List bytes);
  Future<SafDocument> stat(String uri);
  Future<List<SafChild>> listChildren(String uri);
  Future<bool> hasPersistedPermission(String uri);
  Future<void> releasePermission(String uri);
}

class AndroidSafGateway implements SafGateway {
  static const MethodChannel _channel = MethodChannel('mangacat/saf');

  Future<Object?> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException catch (error) {
      throw SafException(_kindFor(error.code), error.message ?? error.code);
    } on MissingPluginException {
      throw const SafException(
        SafErrorKind.unavailable,
        'Storage access is unavailable on this platform.',
      );
    }
  }

  static SafErrorKind _kindFor(String code) => switch (code) {
        'permission' => SafErrorKind.permission,
        'io' => SafErrorKind.io,
        'busy' => SafErrorKind.busy,
        'notFound' => SafErrorKind.missing,
        'unavailable' => SafErrorKind.unavailable,
        _ => SafErrorKind.unknown,
      };

  @override
  Future<SafDocument?> pickFile() async {
    final result = await _invoke('pickFile');
    if (result == null) return null;
    return SafDocument.fromMap(result as Map<Object?, Object?>);
  }

  @override
  Future<SafDocument?> pickDirectory() async {
    final result = await _invoke('pickDirectory');
    if (result == null) return null;
    return SafDocument.fromMap(result as Map<Object?, Object?>);
  }

  @override
  Future<SafDocument?> createFile({
    required String suggestedName,
    String mimeType = 'text/csv',
  }) async {
    final result = await _invoke('createFile', <String, Object?>{
      'suggestedName': suggestedName,
      'mimeType': mimeType,
    });
    if (result == null) return null;
    return SafDocument.fromMap(result as Map<Object?, Object?>);
  }

  @override
  Future<Uint8List> readBytes(String uri) async {
    final result = await _invoke('readBytes', <String, Object?>{'uri': uri});
    if (result == null) throw const SafException(SafErrorKind.io, 'Could not read file.');
    final map = result as Map<Object?, Object?>;
    final encoded = map['bytes'] as String?;
    if (encoded == null) throw const SafException(SafErrorKind.io, 'Could not read file.');
    return base64Decode(encoded);
  }

  @override
  Future<SafDocument> writeBytes(String uri, Uint8List bytes) async {
    final result = await _invoke('writeBytes', <String, Object?>{
      'uri': uri,
      'bytes': base64Encode(bytes),
    });
    if (result == null) throw const SafException(SafErrorKind.io, 'Could not write file.');
    return SafDocument.fromMap(result as Map<Object?, Object?>);
  }

  @override
  Future<SafDocument> stat(String uri) async {
    final result = await _invoke('stat', <String, Object?>{'uri': uri});
    if (result == null) {
      return SafDocument(uri: uri, name: '', size: -1, mtimeMs: -1, exists: false);
    }
    return SafDocument.fromMap(result as Map<Object?, Object?>);
  }

  @override
  Future<List<SafChild>> listChildren(String uri) async {
    final result = await _invoke('listChildren', <String, Object?>{'uri': uri});
    if (result is! List) return const <SafChild>[];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(SafChild.fromMap)
        .toList(growable: false);
  }

  @override
  Future<bool> hasPersistedPermission(String uri) async {
    final result = await _invoke('checkPersisted', <String, Object?>{'uri': uri});
    if (result is! Map) return false;
    return (result['persisted'] as bool?) ?? false;
  }

  @override
  Future<void> releasePermission(String uri) async {
    await _invoke('releasePermission', <String, Object?>{'uri': uri});
  }
}
