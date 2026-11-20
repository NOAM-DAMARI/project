import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/lesson_import_info.dart';
import 'storage.dart';

/// סוגי קבצי שמע מותרים להעלאה (כל השאר נחסם)
const audioExts = ['mp3', 'aac', 'wav', 'flac', 'ogg'];

/// ארכיונים מותרים לייבוא: ZIP, TAR, TAR.GZ (גם TGZ)
const archiveExts = ['zip', 'tar', 'gz', 'tgz'];

/// קבצים שמותר לייבא מתוך ארכיון / להעלות כקובץ בודד
const importExts = audioExts;

/// האם שם הקובץ מסתיים באחת הסיומות המותרות
bool hasAllowedExt(String name, List<String> exts) {
  final dot = name.lastIndexOf('.');
  return dot > 0 && exts.contains(name.substring(dot + 1).toLowerCase());
}

class PickedMedia {
  /// עותק קבוע במכשיר (null בדפדפן)
  final String? path;
  final String name;
  final int size;

  /// תוכן הקובץ – בדפדפן או כשביקשו במפורש.
  final Uint8List? bytes;
  final String? remoteUrl;
  final String? assetApi;
  final String? unassignedId;
  final String? importedMetadataKey;
  final LessonImportInfo? suggestedLesson;

  PickedMedia({
    required this.path,
    required this.name,
    required this.size,
    this.bytes,
    this.remoteUrl,
    this.assetApi,
    this.unassignedId,
    this.importedMetadataKey,
    this.suggestedLesson,
  });
}

/// בחירת קובץ. בטלפון הקובץ מועתק לאחסון האפליקציה בלי לטעון אותו לזיכרון,
/// כך שאפשר לבחור גם קבצים של מאות MB.
Future<PickedMedia?> pickMedia(FileType type,
    {List<String>? exts, bool needBytes = false}) async {
  final result = await FilePicker.platform.pickFiles(
    type: type,
    // file_picker זורק שגיאה אם מעבירים סיומות לסוג שאינו custom
    allowedExtensions: type == FileType.custom ? exts : null,
    withData: kIsWeb || needBytes,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;

  if (kIsWeb) {
    if (file.bytes == null || file.bytes!.isEmpty) return null;
    return PickedMedia(
        path: null,
        name: file.name,
        size: file.bytes!.length,
        bytes: file.bytes);
  }

  String? path;
  if (file.path != null) {
    path = await persistPickedFile(file.path!, file.name);
  } else if (file.bytes != null) {
    path = await persistPickedBytes(file.name, file.bytes!);
  }
  if (path == null) return null;
  return PickedMedia(
      path: path, name: file.name, size: file.size, bytes: file.bytes);
}

Future<PickedMedia?> pickAudio() => pickMedia(FileType.custom, exts: audioExts);

Future<void> deleteMedia(String? path) => deletePersistedFile(path);

/// נתיב הקובץ שנבחר. בדפדפן קריאה ל-`path` זורקת חריגה, ולכן שם מחזירים null
/// והקוד משתמש ב-`bytes` במקום.
String? safePickedPath(PlatformFile file) {
  if (kIsWeb) return null;
  try {
    return file.path;
  } catch (_) {
    return null;
  }
}
