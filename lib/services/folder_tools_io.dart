import 'dart:io';

import 'package:archive/archive_io.dart';

import 'folder_tools.dart';

String _sep(String p) => p.replaceAll('\\', '/');

String _relative(String folder, String path) {
  final f = _sep(folder).replaceAll(RegExp(r'/+$'), '');
  final p = _sep(path);
  return p.startsWith('$f/') ? p.substring(f.length + 1) : p;
}

/// כל קבצי המדיה בתיקייה (רקורסיבי), בלי תיקיות מערכת/נתונים
Future<List<FreeFile>> listMediaFiles(String folder, List<String> exts) async {
  final dir = Directory(folder);
  if (folder.isEmpty || !dir.existsSync()) return const [];
  final set = exts.map((e) => e.toLowerCase()).toSet();
  final out = <FreeFile>[];
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = _relative(folder, e.path);
    if (rel.startsWith('data/') || rel.split('/').any((s) => s.startsWith('.')))
      continue;
    final name = rel.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || !set.contains(name.substring(dot + 1).toLowerCase()))
      continue;
    out.add(FreeFile(
        path: e.path, name: name, relative: rel, size: await e.length()));
  }
  out.sort((a, b) => a.relative.compareTo(b.relative));
  return out;
}

String _safe(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

Future<File> _unique(Directory dir, String name) async {
  var target = File('${dir.path}/${_safe(name)}');
  if (!target.existsSync()) return target;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 2;; i++) {
    target = File('${dir.path}/${_safe('$base ($i)$ext')}');
    if (!target.existsSync()) return target;
  }
}

/// העתקת קבצים לתיקייה (תת-תיקייה inbox כברירת מחדל). מחזיר את הנתיבים החדשים.
Future<List<String>> copyFilesToFolder(String folder, List<String> sources,
    {String sub = 'inbox'}) async {
  final dir = Directory('$folder/$sub');
  if (!dir.existsSync()) await dir.create(recursive: true);
  final out = <String>[];
  for (final s in sources) {
    final name = _sep(s).split('/').last;
    final target = await _unique(dir, name);
    await File(s).copy(target.path);
    out.add(target.path);
  }
  return out;
}

/// חילוץ ZIP גדול ישירות מהדיסק (בלי לטעון את כולו לזיכרון) ופריסת הקבצים בתיקייה.
/// שומר על מבנה התיקיות שבתוך ה-ZIP וחוסם נתיבים מסוכנים (../).
Future<List<ZipEntry>> listImportableZipEntries(
    String zipPath, List<String> allowedExtensions) async {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final allowed = allowedExtensions.map((e) => e.toLowerCase()).toSet();
    return [
      for (final f in archive.files)
        if (f.isFile &&
            _safeZipPath(f.name) != null &&
            _allowedFile(f.name, allowed))
          ZipEntry(path: _safeZipPath(f.name)!, size: f.size),
    ];
  } finally {
    await input.close();
  }
}

bool _allowedFile(String path, Set<String> allowed) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 && allowed.contains(name.substring(dot + 1).toLowerCase());
}

String? _safeZipPath(String path) {
  final value = _sep(path);
  if (value.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(value))
    return null;
  final parts =
      value.split('/').where((part) => part.isNotEmpty && part != '.').toList();
  if (parts.isEmpty ||
      parts.any((part) => part == '..') ||
      parts.first == '__MACOSX') return null;
  return parts.join('/');
}

Future<int> extractSelectedZipEntries(
    String folder, String zipPath, Set<String> selected,
    {String sub = 'inbox',
    void Function(int done, int total)? onProgress}) async {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final root = Directory('$folder/$sub');
    await root.create(recursive: true);
    final rootPath = _sep(root.absolute.path).replaceAll(RegExp(r'/+$'), '');
    var done = 0;
    for (final f in archive.files) {
      final rel = _safeZipPath(f.name);
      if (!f.isFile || rel == null || !selected.contains(rel)) continue;
      var out = File('$rootPath/$rel');
      if (!_sep(out.absolute.path).startsWith('$rootPath/')) continue;
      await out.parent.create(recursive: true);
      if (out.existsSync())
        out = await _unique(out.parent, out.uri.pathSegments.last);
      final os = OutputFileStream(out.path);
      try {
        f.writeContent(os);
      } finally {
        await os.close();
      }
      done++;
      onProgress?.call(done, selected.length);
    }
    return done;
  } finally {
    await input.close();
  }
}

Future<int> extractZipToFolder(String folder, String zipPath,
    {String sub = 'inbox',
    void Function(int done, int total)? onProgress}) async {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final root = Directory('$folder/$sub');
    if (!root.existsSync()) await root.create(recursive: true);
    final rootPath = _sep(root.absolute.path);
    final files = archive.files.where((f) => f.isFile).toList();
    var done = 0;
    for (final f in files) {
      final rel = _sep(f.name)
          .split('/')
          .where((s) => s.isNotEmpty && s != '.' && s != '..')
          .join('/');
      if (rel.isEmpty || rel.startsWith('__MACOSX/')) continue;
      final out = File('$rootPath/$rel');
      if (!_sep(out.absolute.path).startsWith(rootPath)) continue;
      await out.parent.create(recursive: true);
      final os = OutputFileStream(out.path);
      try {
        f.writeContent(os);
      } finally {
        await os.close();
      }
      done++;
      onProgress?.call(done, files.length);
    }
    return done;
  } finally {
    await input.close();
  }
}

/// תיקייה זמנית לחילוץ קבצים לפני העלאה (כשאין תיקייה מקומית מוגדרת)
Future<String> makeTempFolder() async =>
    (await Directory.systemTemp.createTemp('lesson_zip_')).path;

Future<void> deleteFolder(String path) async {
  try {
    final dir = Directory(path);
    if (dir.existsSync()) await dir.delete(recursive: true);
  } catch (_) {}
}

/// כותב קובץ בודד (מארכיון שנפתח בזיכרון) לתיקייה, עם הגנה מנתיבים מסוכנים
Future<String> writeBytesToFolder(
    String folder, String relative, List<int> bytes) async {
  final rel = _safeZipPath(relative);
  if (rel == null) throw Exception('נתיב קובץ לא תקין: $relative');
  final root = Directory(folder);
  await root.create(recursive: true);
  final rootPath = _sep(root.absolute.path).replaceAll(RegExp(r'/+$'), '');
  var out = File('$rootPath/$rel');
  if (!_sep(out.absolute.path).startsWith('$rootPath/')) {
    throw Exception('נתיב קובץ לא תקין: $relative');
  }
  await out.parent.create(recursive: true);
  if (out.existsSync()) out = await _unique(out.parent, out.uri.pathSegments.last);
  await out.writeAsBytes(bytes, flush: true);
  return out.path;
}
