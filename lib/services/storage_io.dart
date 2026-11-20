import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;
import 'package:path_provider/path_provider.dart';

String? _docs;

/// חייב להיקרא פעם אחת בעליית האפליקציה.
Future<void> initStorage() async {
  _docs = (await getApplicationDocumentsDirectory()).path;
}

Future<String?> defaultMediaFolder() async {
  if (_docs == null) return null;
  final directory = Directory('${_docs!}/lesson_manager_inbox');
  await directory.create(recursive: true);
  return directory.path;
}

String _safe(String name) => name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

Directory _dir(String sub) => Directory('$_docs/$sub');

/// מעתיק קובץ שנבחר לתיקיית האפליקציה בלי לטעון אותו לזיכרון (מתאים לקבצים גדולים).
Future<String?> persistPickedFile(String srcPath, String fileName) async {
  final dir = _dir('media');
  await dir.create(recursive: true);
  final path =
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_${_safe(fileName)}';
  await File(srcPath).copy(path);
  return path;
}

Future<String?> persistPickedBytes(String fileName, List<int> bytes) async {
  final dir = _dir('media');
  await dir.create(recursive: true);
  final path =
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_${_safe(fileName)}';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<void> deletePersistedFile(String? path) async {
  if (path == null) return;
  final file = File(path);
  if (await file.exists()) await file.delete();
}

/// כתיבת קובץ לנתיב שנבחר (שמירה בשם במחשב)
Future<void> writeBytesToPath(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

bool localFileExists(String? path) =>
    path != null && !path.startsWith('http') && File(path).existsSync();

int? localFileSize(String? path) =>
    localFileExists(path) ? File(path!).lengthSync() : null;

Future<List<int>> readLocalRange(String path, int start, int end) async {
  final b = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead(start, end)) {
    b.add(chunk);
  }
  return b.takeBytes();
}

// ---------- מטמון להאזנה ללא אינטרנט ----------

String? cachedPath(String key) {
  if (_docs == null) return null;
  final f = File('${_dir('media_cache').path}/${_safe(key)}');
  return f.existsSync() && f.lengthSync() > 0 ? f.path : null;
}

int cacheSizeBytes() {
  final d = _dir('media_cache');
  if (!d.existsSync()) return 0;
  return d.listSync().whereType<File>().fold(0, (s, f) => s + f.lengthSync());
}

Future<void> clearCache() async {
  final d = _dir('media_cache');
  if (await d.exists()) await d.delete(recursive: true);
}

Future<void> removeCached(String key) async {
  final p = cachedPath(key);
  if (p != null) await File(p).delete();
}

/// הורדה בזרימה לקובץ, עם מעקב התקדמות. הפניות (redirect) לשרת אחר
/// נשלחות ללא כותרת ההרשאה כדי לא לחשוף את ה-Token.
Future<String?> downloadToCache({
  required String url,
  required String key,
  Map<String, String> headers = const {},
  void Function(int received, int? total)? onProgress,
}) async {
  final existing = cachedPath(key);
  if (existing != null) return existing;
  final dir = _dir('media_cache');
  await dir.create(recursive: true);
  final target = File('${dir.path}/${_safe(key)}');
  final tmp = File('${target.path}.part');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(minutes: 2);
  try {
    var uri = Uri.parse(url);
    var hdrs = Map<String, String>.of(headers);
    for (var i = 0; i < 6; i++) {
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      hdrs.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      if (res.statusCode >= 300 && res.statusCode < 400) {
        final loc = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (loc == null) throw Exception('הפניה ללא כתובת');
        final next = uri.resolve(loc);
        if (next.host != uri.host) hdrs = {};
        uri = next;
        continue;
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw Exception('ההורדה נכשלה (${res.statusCode})');
      }
      final total = res.contentLength > 0 ? res.contentLength : null;
      final sink = tmp.openWrite();
      var got = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(got, total);
        }
      } finally {
        await sink.close();
      }
      await tmp.rename(target.path);
      return target.path;
    }
    throw Exception('יותר מדי הפניות');
  } catch (_) {
    if (await tmp.exists()) await tmp.delete();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

// ---------- העלאה בזרימה (קבצים גדולים, עד 2GB) ----------

class UploadResponse {
  final int status;
  final String body;
  UploadResponse(this.status, this.body);
}

Future<UploadResponse> uploadStream({
  required Uri uri,
  required Map<String, String> headers,
  String? path,
  List<int>? bytes,
  required int length,
  void Function(int sent, int total)? onProgress,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(minutes: 2);
  try {
    final req = await client.postUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    req.contentLength = length;
    var sent = 0;
    final Stream<List<int>> source =
        path != null ? File(path).openRead() : Stream.value(bytes ?? const []);
    await req.addStream(source.map((c) {
      sent += c.length;
      onProgress?.call(sent, length);
      return c;
    }));
    // בלי מגבלת זמן חיבור שנפל נשאר "תקוע ב-100%" לנצח
    final res = await req.close().timeout(const Duration(minutes: 15),
        onTimeout: () =>
            throw Exception('השרת לא אישר את סיום ההעלאה (פג זמן). נסה שוב.'));
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(minutes: 2));
    return UploadResponse(res.statusCode, body);
  } finally {
    client.close();
  }
}
