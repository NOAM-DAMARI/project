import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'library.dart';

/// מצב האפליקציה: הגדרות החיבור ל-GitHub והרשימה שנקראה מהמאגר.
class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  SharedPreferences get prefs => _p;

  String githubOwner = 'NOAM-DAMARI';
  String githubRepo = 'LessonSong';
  String githubBranch = 'main';
  String githubToken = '';

  bool connected = false;
  Library library = Library.empty;
  bool refreshing = false;
  String? error;

  /// מאפשר לבדיקות להחליף את הרשת
  http.Client client = http.Client();

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    githubOwner = _p.getString('githubOwner') ?? githubOwner;
    githubRepo = _p.getString('githubRepo') ?? githubRepo;
    githubBranch = _p.getString('githubBranch') ?? githubBranch;
    githubToken = _p.getString('githubToken') ?? '';
    connected = _p.getBool('connected') ?? false;
    final cached = _p.getString('library_cache');
    if (cached != null) {
      try {
        library = Library.parse(cached);
      } catch (_) {}
    }
    notifyListeners();
    if (connected) refresh();
  }

  Map<String, String> _headers(String token) => {
        // מחזיר את תוכן הקובץ כמו שהוא (עד 100MB), ולא base64
        'Accept': 'application/vnd.github.raw+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Library> _fetch(
      String owner, String repo, String branch, String token) async {
    final uri = Uri.https('api.github.com',
        '/repos/$owner/$repo/contents/data/music_manager.json', {'ref': branch});
    final http.Response res;
    try {
      res = await client.get(uri, headers: _headers(token));
    } catch (_) {
      throw Exception('אין חיבור לאינטרנט');
    }
    switch (res.statusCode) {
      case 200:
        return Library.parse(utf8Body(res));
      case 401:
        throw Exception('ה-Token לא תקין או שפג תוקפו');
      case 403:
      case 429:
        throw Exception(token.isEmpty
            ? 'GitHub חסם זמנית בקשות בלי Token. הוסף Token ונסה שוב'
            : 'אין הרשאה לקרוא את המאגר עם ה-Token הזה');
      case 404:
        throw Exception(
            'לא נמצא המאגר $owner/$repo (ענף $branch) או הקובץ data/music_manager.json.\nבמאגר פרטי צריך Token.');
      default:
        throw Exception('GitHub החזיר שגיאה ${res.statusCode}');
    }
  }

  static String utf8Body(http.Response r) =>
      const Utf8Decoder(allowMalformed: true).convert(r.bodyBytes);

  /// "חבר מאגר": בודק שהמאגר נקרא, ורק אז שומר את ההגדרות.
  Future<Library> connect(
      {required String owner,
      required String repo,
      String branch = 'main',
      String token = ''}) async {
    owner = owner.trim();
    repo = repo.trim();
    branch = branch.trim().isEmpty ? 'main' : branch.trim();
    token = token.trim();
    if (owner.isEmpty || repo.isEmpty) {
      throw Exception('צריך למלא בעלים ושם מאגר');
    }
    final lib = await _fetch(owner, repo, branch, token);
    githubOwner = owner;
    githubRepo = repo;
    githubBranch = branch;
    githubToken = token;
    connected = true;
    error = null;
    await _p.setString('githubOwner', owner);
    await _p.setString('githubRepo', repo);
    await _p.setString('githubBranch', branch);
    await _p.setString('githubToken', token);
    await _p.setBool('connected', true);
    await _setLibrary(lib);
    return lib;
  }

  /// קריאה מחדש של הרשימה מהמאגר
  Future<void> refresh() async {
    if (!connected || refreshing) return;
    refreshing = true;
    error = null;
    notifyListeners();
    try {
      await _setLibrary(
          await _fetch(githubOwner, githubRepo, githubBranch, githubToken));
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    connected = false;
    library = Library.empty;
    error = null;
    await _p.setBool('connected', false);
    await _p.remove('library_cache');
    notifyListeners();
  }

  Future<void> _setLibrary(Library lib) async {
    library = lib;
    await _p.setString('library_cache', lib.toCache());
    notifyListeners();
  }
}

final app = AppState();
