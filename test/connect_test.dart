import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lesson_player/services/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final body = utf8.encode(jsonEncode({
    'lessons': [
      {'id': 'l1', 'title': 'שיעור', 'remoteUrl': 'https://e/a.mp3'}
    ],
    'songs': [],
  }));

  Future<AppState> fresh(http.Client client) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState()..client = client;
    await s.load();
    return s;
  }

  test('connect reads data/music_manager.json from the chosen repo and branch', () async {
    late http.Request seen;
    final s = await fresh(MockClient((r) async {
      seen = r;
      return http.Response.bytes(body, 200);
    }));
    final lib = await s.connect(owner: 'me', repo: 'Lessons', branch: 'dev', token: 'abc');
    expect(seen.url.path, '/repos/me/Lessons/contents/data/music_manager.json');
    expect(seen.url.queryParameters['ref'], 'dev');
    expect(seen.headers['Authorization'], 'Bearer abc');
    expect(lib.lessons.single.title, 'שיעור');
    expect(s.connected, isTrue);
    expect(s.prefs.getString('githubRepo'), 'Lessons');
  });

  test('a public repo can be connected without a token', () async {
    late http.Request seen;
    final s = await fresh(MockClient((r) async {
      seen = r;
      return http.Response.bytes(body, 200);
    }));
    await s.connect(owner: 'me', repo: 'Lessons');
    expect(seen.headers.containsKey('Authorization'), isFalse);
    expect(seen.url.queryParameters['ref'], 'main');
  });

  test('a failed connect does not save the settings', () async {
    final s = await fresh(MockClient((r) async => http.Response('', 404)));
    await expectLater(
        s.connect(owner: 'me', repo: 'Missing', token: 't'), throwsException);
    expect(s.connected, isFalse);
    expect(s.prefs.getString('githubRepo'), isNull);
  });

  test('a bad token shows a clear message', () async {
    final s = await fresh(MockClient((r) async => http.Response('', 401)));
    await expectLater(
        s.connect(owner: 'me', repo: 'R', token: 'bad'),
        throwsA(predicate((e) => e.toString().contains('Token'))));
  });

  test('disconnect clears the list', () async {
    final s = await fresh(MockClient((r) async => http.Response.bytes(body, 200)));
    await s.connect(owner: 'me', repo: 'R');
    await s.disconnect();
    expect(s.connected, isFalse);
    expect(s.library.isEmpty, isTrue);
  });
}
