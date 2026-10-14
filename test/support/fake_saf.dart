import 'dart:convert';
import 'dart:typed_data';

import 'package:mangacat/data/saf_gateway.dart';

class FakeSaf implements SafGateway {
  final Map<String, List<int>> files = <String, List<int>>{};
  final Map<String, int> mtimes = <String, int>{};
  final Map<String, List<SafChild>> children = <String, List<SafChild>>{};
  int _clock = 1000;

  SafDocument? pickFileResult;
  SafDocument? pickDirectoryResult;
  SafDocument? createFileResult;

  void put(String uri, String contents) {
    files[uri] = utf8.encode(contents);
    mtimes[uri] = _clock++;
  }

  String _name(String uri) => uri.split('/').last;

  @override
  Future<SafDocument?> pickFile() async => pickFileResult;

  @override
  Future<SafDocument?> pickDirectory() async => pickDirectoryResult;

  @override
  Future<SafDocument?> createFile({
    required String suggestedName,
    String mimeType = 'text/csv',
  }) async {
    if (createFileResult != null) return createFileResult;
    final uri = 'content://fake/$suggestedName';
    files[uri] = <int>[];
    mtimes[uri] = _clock++;
    return SafDocument(
      uri: uri,
      name: suggestedName,
      size: 0,
      mtimeMs: mtimes[uri]!,
      exists: true,
    );
  }

  @override
  Future<Uint8List> readBytes(String uri) async {
    final data = files[uri];
    if (data == null) throw SafException(SafErrorKind.missing, 'Missing $uri');
    return Uint8List.fromList(data);
  }

  @override
  Future<SafDocument> writeBytes(String uri, Uint8List bytes) async {
    files[uri] = bytes.toList();
    mtimes[uri] = _clock++;
    return stat(uri);
  }

  @override
  Future<SafDocument> stat(String uri) async {
    final data = files[uri];
    if (data == null) {
      return SafDocument(uri: uri, name: _name(uri), size: -1, mtimeMs: -1, exists: false);
    }
    return SafDocument(
      uri: uri,
      name: _name(uri),
      size: data.length,
      mtimeMs: mtimes[uri]!,
      exists: true,
    );
  }

  @override
  Future<List<SafChild>> listChildren(String uri) async =>
      children[uri] ?? const <SafChild>[];

  @override
  Future<bool> hasPersistedPermission(String uri) async => true;

  @override
  Future<void> releasePermission(String uri) async {}
}
