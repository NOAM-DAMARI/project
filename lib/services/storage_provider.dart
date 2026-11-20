import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_sync.dart';

class StorageSnapshot {
  final String rawData;
  final DateTime updatedAt;

  const StorageSnapshot({required this.rawData, required this.updatedAt});

  factory StorageSnapshot.fromRaw(String rawData) {
    final value = jsonDecode(rawData);
    final timestamp = value is Map
        ? DateTime.tryParse(value['_updatedAt']?.toString() ?? '')
        : null;
    return StorageSnapshot(
      rawData: rawData,
      updatedAt:
          timestamp ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

abstract interface class StorageProvider {
  String get name;
  Future<StorageSnapshot?> read();
  Future<void> write(StorageSnapshot snapshot);
}

class LocalJsonStorageProvider implements StorageProvider {
  final String folder;
  const LocalJsonStorageProvider(this.folder);

  @override
  String get name => 'אחסון מקומי';

  @override
  Future<StorageSnapshot?> read() async {
    final raw = await readLocalJson(folder);
    if (raw == null || raw.trim().isEmpty) return null;
    return StorageSnapshot.fromRaw(raw);
  }

  @override
  Future<void> write(StorageSnapshot snapshot) =>
      writeLocalJson(folder, snapshot.rawData);
}

class GitHubJsonStorageProvider implements StorageProvider {
  final String owner;
  final String repository;
  final String branch;
  final String token;

  const GitHubJsonStorageProvider(
      {required this.owner,
      required this.repository,
      required this.branch,
      required this.token});

  Uri get _uri => Uri.https('api.github.com',
      '/repos/$owner/$repository/contents/data/music_manager.json');
  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $token',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  @override
  String get name => 'GitHub';

  @override
  Future<StorageSnapshot?> read() async {
    final response = await http
        .get(_uri.replace(queryParameters: {'ref': branch}), headers: _headers);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200)
      throw Exception('GitHub GET ${response.statusCode}: ${response.body}');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final encoded = (body['content'] as String).replaceAll('\n', '');
    return StorageSnapshot.fromRaw(utf8.decode(base64Decode(encoded)));
  }

  @override
  Future<void> write(StorageSnapshot snapshot) async {
    String? sha;
    final current = await http
        .get(_uri.replace(queryParameters: {'ref': branch}), headers: _headers);
    if (current.statusCode == 200) {
      sha =
          (jsonDecode(current.body) as Map<String, dynamic>)['sha']?.toString();
    } else if (current.statusCode != 404) {
      throw Exception('GitHub GET ${current.statusCode}: ${current.body}');
    }
    final response = await http.put(
      _uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': 'עדכון נתוני Music Manager',
        'content': base64Encode(utf8.encode(snapshot.rawData)),
        'branch': branch,
        if (sha != null) 'sha': sha,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('GitHub PUT ${response.statusCode}: ${response.body}');
    }
  }
}
