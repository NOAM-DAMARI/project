import 'package:flutter/foundation.dart';
import '../models/media.dart';
import 'app_state.dart';
import 'storage.dart';

/// מאתר איפה הקובץ נמצא: במכשיר, במטמון, או בענן.
class MediaResolver {
  static String? cacheKey(MediaFields m) {
    final src = m.assetApi ?? m.remoteUrl;
    if (src == null) return null;
    final tail = src.split('/').where((e) => e.isNotEmpty).toList();
    final name = m.fileName ?? (tail.isEmpty ? 'media' : tail.last);
    return '${_fnv(src)}_$name';
  }

  /// גיבוב יציב (FNV-1a) – String.hashCode אינו מובטח בין הרצות
  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  /// נתיב מקומי זמין עכשיו בלי להוריד (קובץ מקורי או עותק במטמון)
  static String? availableLocally(MediaFields m) {
    if (localFileExists(m.filePath)) return m.filePath;
    final key = cacheKey(m);
    return key == null ? null : cachedPath(key);
  }

  static bool isOffline(MediaFields m) => availableLocally(m) != null;

  /// כותרות להזרמה ישירה (מאגר פרטי ב-raw.githubusercontent)
  static Map<String, String>? streamHeaders(String url) =>
      url.contains('raw.githubusercontent.com') && app.githubToken.isNotEmpty
          ? {'Authorization': 'Bearer ${app.githubToken}'}
          : null;

  /// מוריד למטמון (אם צריך) ומחזיר נתיב מקומי. בדפדפן מחזיר null.
  static Future<String?> ensureLocal(MediaFields m,
      {void Function(int received, int? total)? onProgress}) async {
    final local = availableLocally(m);
    if (local != null) return local;
    if (kIsWeb) return null;
    final key = cacheKey(m);
    if (key == null) return null;

    Object? lastError;
    if (m.assetApi != null) {
      try {
        return await downloadToCache(
          url: m.assetApi!,
          key: key,
          headers: {
            'Accept': 'application/octet-stream',
            if (app.githubToken.isNotEmpty)
              'Authorization': 'Bearer ${app.githubToken}',
          },
          onProgress: onProgress,
        );
      } catch (e) {
        lastError = e;
      }
    }
    if (m.remoteUrl != null) {
      return downloadToCache(
        url: m.remoteUrl!,
        key: key,
        headers: streamHeaders(m.remoteUrl!) ?? const {},
        onProgress: onProgress,
      );
    }
    if (lastError != null) throw lastError;
    return null;
  }

  static Future<void> removeOffline(MediaFields m) async {
    final key = cacheKey(m);
    if (key != null) await removeCached(key);
  }
}
