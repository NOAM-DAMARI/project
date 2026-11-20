// גרסת דפדפן (Web): אין מערכת קבצים, לכן רוב הפעולות ריקות.
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> initStorage() async {}

Future<String?> defaultMediaFolder() async => null;

Future<String?> persistPickedFile(String srcPath, String fileName) async =>
    null;

Future<String?> persistPickedBytes(String fileName, List<int> bytes) async =>
    null;

Future<void> deletePersistedFile(String? path) async {}

Future<void> writeBytesToPath(String path, List<int> bytes) async {}

bool localFileExists(String? path) => false;

int? localFileSize(String? path) => null;

Future<List<int>> readLocalRange(String path, int start, int end) async =>
    const [];

String? cachedPath(String key) => null;

int cacheSizeBytes() => 0;

Future<void> clearCache() async {}

Future<void> removeCached(String key) async {}

Future<String?> downloadToCache({
  required String url,
  required String key,
  Map<String, String> headers = const {},
  void Function(int received, int? total)? onProgress,
}) async =>
    null;

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
  if (bytes == null || bytes.length != length) {
    throw StateError(
        'בדפדפן תוכן הקובץ לא נטען במלואו. יש לבחור את הקובץ מחדש.');
  }
  final h = Map<String, String>.of(headers)
    ..remove('Content-Length')
    ..putIfAbsent('Accept', () => 'application/vnd.github+json');
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final res = await http
          .post(uri, headers: h, body: bytes)
          .timeout(const Duration(minutes: 30));
      onProgress?.call(length, length);
      return UploadResponse(res.statusCode, utf8.decode(res.bodyBytes));
    } catch (error) {
      lastError = error;
      if (attempt < 2)
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
    }
  }
  throw http.ClientException(
      'העלאת הקובץ נקטעה אחרי 3 ניסיונות: $lastError', uri);
}
