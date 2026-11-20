import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/media.dart';
import 'app_state.dart';
import 'file_service.dart';
import 'storage.dart';

/// אחסון קבצי שמע גדולים ב-GitHub Releases.
///
/// ה-Contents API של GitHub מוגבל ל-100MB לקובץ (ובפועל מנפח את המאגר),
/// לעומת קבצים מצורפים ל-Release שמוגבלים ל-2GB לקובץ ואינם נספרים בגודל המאגר.
String _contentsBody(({String message, String branch, Uint8List bytes}) a) =>
    jsonEncode({
      'message': a.message,
      'branch': a.branch,
      'content': base64Encode(a.bytes)
    });

class GitHubMedia {
  static const releaseTag = 'music-manager-media';
  static const maxBytes = 2 * 1024 * 1024 * 1024 - 1;

  static int? _releaseId;
  static String? _releaseFor;

  static String get _repo => '${app.githubOwner}/${app.githubRepo}';

  static Future<int> _ensureRelease() async {
    if (_releaseId != null && _releaseFor == _repo) return _releaseId!;
    final base = 'https://api.github.com/repos/$_repo/releases';
    final get = await http.get(Uri.parse('$base/tags/$releaseTag'),
        headers: app.githubHeaders);
    if (get.statusCode == 200) {
      _releaseFor = _repo;
      return _releaseId = jsonDecode(get.body)['id'] as int;
    }
    if (get.statusCode != 404)
      throw Exception('GitHub releases ${get.statusCode}: ${get.body}');

    Future<http.Response> create() => http.post(
          Uri.parse(base),
          headers: {...app.githubHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'tag_name': releaseTag,
            'target_commitish': app.githubBranch,
            'name': 'Music Manager – קבצי מדיה',
            'body':
                'קבצי השירים והשיעורים של האפליקציה. אין למחוק את ה-Release הזה.',
            'draft': false,
            'prerelease': false,
          }),
        );

    var res = await create();
    if (res.statusCode == 422) {
      // מאגר ריק – יוצרים קודם את מבנה התיקיות ומנסים שוב
      await app.ensureRepositoryStructure();
      res = await create();
    }
    if (res.statusCode != 201)
      throw Exception('יצירת Release נכשלה ${res.statusCode}: ${res.body}');
    _releaseFor = _repo;
    return _releaseId = jsonDecode(res.body)['id'] as int;
  }

  /// מעלה קובץ ומעדכן את [target]. מחזיר שגיאה קריאה אם נכשל.
  static Future<void> upload(
    PickedMedia media,
    MediaFields target, {
    required String folder,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (!app.githubReady) throw Exception('יש להגדיר חיבור ל-GitHub בהגדרות');
    if (media.size > maxBytes) throw Exception('GitHub מאפשר עד 2GB לקובץ');

    final safe = media.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final assetName =
        '${folder}_${DateTime.now().millisecondsSinceEpoch}_$safe';

    // Small files use the Contents API: it works in browsers where uploads.github.com
    // can fail its CORS preflight. Large media continues to use Release assets.
    // קבצים קטנים – Contents API (עובד בדפדפן בלי בעיות CORS).
    // קבצים גדולים (גם בדפדפן וגם מעל 100MB) – Release assets, עד 2GB.
    final contentsLimit = kIsWeb ? 25 * 1024 * 1024 : 8 * 1024 * 1024;
    if (media.size <= contentsLimit) {
      onProgress?.call(0, media.size);
      final bytes =
          media.bytes ?? await readLocalRange(media.path!, 0, media.size);
      // קידוד base64 ובניית JSON ב-Isolate נפרד – אחרת המסך קופא בקבצים גדולים
      final body = await compute(_contentsBody, (
        message: 'Upload media $assetName',
        branch: app.githubBranch,
        bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      ));
      final uri = Uri.parse(
          'https://api.github.com/repos/$_repo/contents/media/$assetName');
      final res = await http
          .put(uri,
              headers: {
                ...app.githubHeaders,
                'Content-Type': 'application/json'
              },
              body: body)
          .timeout(const Duration(minutes: 10),
              onTimeout: () =>
                  throw Exception('פג זמן ההעלאה – בדוק את החיבור לאינטרנט'));
      onProgress?.call(media.size, media.size);
      final tooLarge = res.statusCode == 422 &&
          res.body.toLowerCase().contains('too large');
      if (!tooLarge) {
        if (res.statusCode != 201 && res.statusCode != 200) {
          throw Exception('העלאת הקובץ נכשלה (${res.statusCode}): ${res.body}');
        }
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final content = j['content'] as Map<String, dynamic>? ?? const {};
        target
          ..remoteUrl = content['download_url']?.toString()
          ..assetApi = content['url']?.toString()
          ..fileName = media.name
          ..fileSize = media.size;
        return;
      }
      // GitHub דחה את הקובץ כגדול מדי ל-Contents API – ממשיכים להעלאה כ-Release asset
      onProgress?.call(0, media.size);
    }

    final id = await _ensureRelease();
    final uri =
        Uri.parse('https://uploads.github.com/repos/$_repo/releases/$id/assets')
            .replace(queryParameters: {'name': assetName});

    final res = await uploadStream(
      uri: uri,
      headers: {
        ...app.githubHeaders,
        'Content-Type': 'application/octet-stream'
      },
      path: media.path,
      bytes: media.path == null ? media.bytes : null,
      length: media.size,
      onProgress: onProgress,
    );
    if (res.status != 201) {
      if (res.status == 404) _releaseId = null;
      final detail = res.body.trim().isEmpty
          ? 'אין תשובת שרת'
          : res.body
              .substring(0, res.body.length > 300 ? 300 : res.body.length);
      throw Exception(
          'העלאת הקובץ נכשלה (${res.status}). נסה שוב; בקבצים גדולים יש להשאיר את האפליקציה פתוחה עד לסיום. $detail');
    }
    final j = jsonDecode(res.body);

    final oldAsset = target.assetApi;
    target
      ..remoteUrl = j['browser_download_url']
      ..assetApi = j['url']
      ..fileName = media.name
      ..fileSize = media.size;
    if (oldAsset != null && oldAsset != target.assetApi) {
      deleteAsset(oldAsset).catchError((_) {});
    }
  }

  /// מוחק קובץ שהועלה ל-GitHub. יש שני סוגים, ולכל אחד API אחר:
  /// - קובץ שהועלה דרך Contents API (קבצים קטנים): הכתובת מכילה `/contents/`
  ///   והמחיקה דורשת `sha` של הקובץ ו-`branch` בגוף הבקשה. בלי זה GitHub מחזיר 422.
  /// - Release asset (קבצים גדולים): DELETE פשוט שמחזיר 204.
  /// קובץ שכבר לא קיים (404) נחשב כמחיקה שהצליחה.
  static Future<void> deleteAsset(String apiUrl) async {
    if (apiUrl.contains('/contents/')) {
      await _deleteContentsFile(apiUrl);
      return;
    }
    final res =
        await http.delete(Uri.parse(apiUrl), headers: app.githubHeaders);
    if (res.statusCode != 204 && res.statusCode != 404) {
      throw Exception('מחיקה נכשלה ${res.statusCode}: ${_errorText(res.body)}');
    }
  }

  static Future<void> _deleteContentsFile(String apiUrl) async {
    final parsed = Uri.parse(apiUrl);
    // כתובת נקייה בלי ?ref=... (הענף נשלח בנפרד)
    final clean =
        Uri(scheme: parsed.scheme, host: parsed.host, path: parsed.path);
    final info = await http.get(
        clean.replace(queryParameters: {'ref': app.githubBranch}),
        headers: app.githubHeaders);
    if (info.statusCode == 404) return;
    if (info.statusCode != 200) {
      throw Exception(
          'מחיקה נכשלה: קריאת פרטי הקובץ ${info.statusCode}: ${_errorText(info.body)}');
    }
    final sha = (jsonDecode(info.body) as Map)['sha']?.toString();
    if (sha == null || sha.isEmpty) {
      throw Exception('מחיקה נכשלה: GitHub לא החזיר מזהה לקובץ');
    }
    final name = parsed.pathSegments.isEmpty ? '' : parsed.pathSegments.last;
    final res = await http.delete(
      clean,
      headers: {...app.githubHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': 'Delete media $name',
        'sha': sha,
        'branch': app.githubBranch,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 404) {
      throw Exception('מחיקה נכשלה ${res.statusCode}: ${_errorText(res.body)}');
    }
  }

  /// הודעת השגיאה של GitHub (שדה message), קצרה וקריאה
  static String _errorText(String body) {
    try {
      final message = (jsonDecode(body) as Map)['message']?.toString();
      if (message != null && message.isNotEmpty) return message;
    } catch (_) {}
    return body.length > 160 ? '${body.substring(0, 160)}…' : body;
  }
}
