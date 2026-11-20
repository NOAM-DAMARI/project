import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/media.dart';
import '../utils/helpers.dart';
import 'app_state.dart';
import 'download_bytes.dart';
import 'file_service.dart';
import 'media_resolver.dart';
import 'storage.dart';

const _mimeByExt = {
  'mp3': 'audio/mpeg',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'flac': 'audio/flac',
  'ogg': 'audio/ogg',
};

String _cleanName(String name) => name
    .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String? _extOf(String? source) {
  if (source == null) return null;
  final clean = source.split('?').first;
  final dot = clean.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = clean.substring(dot + 1).toLowerCase();
  return audioExts.contains(ext) ? ext : null;
}

/// שם הקובץ להורדה: **השם המקורי** כפי ששמור באפליקציה (למשל "שיעור 12.mp3"),
/// ולא השם הטכני שבמאגר (media_songs_1794..._______.mp3).
/// אם אין שם מקורי – שם השיעור/השיר, עם הסיומת המתאימה.
String originalDownloadName(MediaFields m, {String fallbackTitle = ''}) {
  final ext = _extOf(m.fileName) ??
      _extOf(m.filePath) ??
      _extOf(m.remoteUrl) ??
      _extOf(m.assetApi) ??
      'mp3';
  var name = _cleanName(m.fileName ?? '');
  if (name.isEmpty) name = _cleanName(fallbackTitle);
  if (name.isEmpty) name = 'media';
  return _extOf(name) == null ? '$name.$ext' : name;
}

String mimeForFileName(String name) =>
    _mimeByExt[_extOf(name) ?? 'mp3'] ?? 'application/octet-stream';

Future<Uint8List> _httpGetBytes(String url, Map<String, String> headers) async {
  final res = await http
      .get(Uri.parse(url), headers: headers)
      .timeout(const Duration(minutes: 10));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('שגיאת שרת ${res.statusCode}');
  }
  final type = res.headers['content-type'] ?? '';
  if (type.contains('json')) {
    // Contents API יכול להחזיר JSON עם התוכן ב-base64 במקום הקובץ עצמו
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is Map && data['content'] is String) {
      return base64Decode((data['content'] as String).replaceAll('\n', ''));
    }
    throw Exception('GitHub החזיר תשובה לא צפויה');
  }
  return res.bodyBytes;
}

/// תוכן הקובץ: מהמכשיר / מהמטמון אם קיים, אחרת מ-GitHub.
Future<Uint8List> fetchMediaBytes(MediaFields m) async {
  final local = MediaResolver.availableLocally(m);
  if (local != null) {
    final size = localFileSize(local);
    if (size != null && size > 0) {
      return Uint8List.fromList(await readLocalRange(local, 0, size));
    }
  }
  Object? lastError;
  if (m.assetApi != null && app.githubReady) {
    try {
      final isContents = m.assetApi!.contains('/contents/');
      return await _httpGetBytes(m.assetApi!, {
        ...app.githubHeaders,
        'Accept': isContents
            ? 'application/vnd.github.raw+json'
            : 'application/octet-stream',
      });
    } catch (error) {
      lastError = error;
    }
  }
  if (m.remoteUrl != null) {
    final auth = MediaResolver.streamHeaders(m.remoteUrl!);
    for (final headers in [if (auth != null) auth, const <String, String>{}]) {
      try {
        return await _httpGetBytes(m.remoteUrl!, headers);
      } catch (error) {
        lastError = error;
      }
    }
  }
  throw lastError ?? Exception('הקובץ אינו זמין להורדה');
}

/// הורדה / שמירה של קובץ בשם המקורי.
/// - דפדפן: מוריד ישירות לתיקיית ההורדות בשם המקורי.
/// - מכשיר: חלון "שמירה בשם" עם השם המקורי.
Future<bool> downloadWithOriginalName(BuildContext context, MediaFields m,
    {String fallbackTitle = ''}) async {
  final name = originalDownloadName(m, fallbackTitle: fallbackTitle);
  final mime = mimeForFileName(name);
  if (!m.hasMedia) {
    snack(context, 'אין קובץ להורדה');
    return false;
  }
  snack(context, 'מכין את "$name" להורדה...');
  Uint8List bytes;
  try {
    bytes = await fetchMediaBytes(m);
  } catch (error) {
    if (kIsWeb && m.remoteUrl != null) {
      // גיבוי אחרון: קישור ישיר. הדפדפן עלול להתעלם משם הקובץ בקישור חיצוני.
      await openDownloadUrl(m.remoteUrl!, name);
      if (context.mounted) {
        snack(context,
            'ההורדה הישירה התחילה, אך הדפדפן עשוי לשמור בשם הטכני. ($error)');
      }
      return true;
    }
    if (context.mounted) snack(context, 'ההורדה נכשלה: $error');
    return false;
  }
  try {
    if (kIsWeb) {
      await downloadBytes(bytes, name, mime);
      if (context.mounted) snack(context, 'ההורדה החלה: $name');
      return true;
    }
    final path =
        await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
    if (path == null) {
      if (context.mounted) snack(context, 'לא נבחר מיקום לשמירה');
      return false;
    }
    // במחשב file_picker מחזיר רק את הנתיב – הכתיבה בפועל כאן
    const desktop = {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    };
    if (desktop.contains(defaultTargetPlatform)) {
      await writeBytesToPath(path, bytes);
    }
    if (context.mounted) snack(context, 'נשמר: $name');
    return true;
  } catch (error) {
    if (context.mounted) snack(context, 'שמירת הקובץ נכשלה: $error');
    return false;
  }
}
