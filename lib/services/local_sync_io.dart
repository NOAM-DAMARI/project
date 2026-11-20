import 'dart:io';

Future<String?> readLocalJson(String folder) async {
  final file = File('$folder/data/music_manager.json');
  return file.existsSync() ? file.readAsString() : null;
}

Future<void> writeLocalJson(String folder, String value) async {
  final dir = Directory('$folder/data');
  if (!dir.existsSync()) await dir.create(recursive: true);
  final target = File('${dir.path}/music_manager.json');
  final temporary = File('${dir.path}/music_manager.json.tmp');
  await temporary.writeAsString(value, flush: true);
  if (target.existsSync()) await target.delete();
  await temporary.rename(target.path);
}

/// עותק של קובץ מדיה בתיקייה המקומית (media/<folder>/name). מחזיר את הנתיב החדש.
Future<String?> copyMediaToLocal(String folder, String sourcePath, String name, String sub) async {
  // קובץ שכבר נמצא בתוך התיקייה (למשל "קובץ חופשי") – לא משכפלים
  final norm = (String x) => x.replaceAll('\\', '/').toLowerCase();
  if (norm(sourcePath).startsWith('${norm(folder)}/')) return sourcePath;
  final dir = Directory('$folder/media/$sub');
  if (!dir.existsSync()) await dir.create(recursive: true);
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final target = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$safe');
  await File(sourcePath).copy(target.path);
  return target.path;
}

/// בדיקה שאפשר לכתוב לתיקייה (באנדרואיד חלק מהתיקיות חסומות לכתיבה)
Future<void> checkLocalFolderWritable(String folder) async {
  final probe = File('$folder/.music_manager_probe');
  await probe.writeAsString('ok', flush: true);
  await probe.delete();
}
