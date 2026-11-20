import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'folder_tools.dart';

String? safeZipPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(normalized))
    return null;
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  if (parts.isEmpty ||
      parts.any((part) => part == '..') ||
      parts.first == '__MACOSX') return null;
  return parts.join('/');
}

bool _allowed(String path, Set<String> extensions) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 && extensions.contains(name.substring(dot + 1).toLowerCase());
}

List<ZipEntry> listImportableZipEntriesFromBytes(
    Uint8List bytes, List<String> allowedExtensions) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final allowed =
      allowedExtensions.map((extension) => extension.toLowerCase()).toSet();
  final entries = <ZipEntry>[];
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final path = safeZipPath(file.name);
    if (path != null && _allowed(path, allowed))
      entries.add(ZipEntry(path: path, size: file.size));
  }
  return entries;
}

Map<String, Uint8List> extractSelectedZipEntriesFromBytes(
    Uint8List bytes, Set<String> selected) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final result = <String, Uint8List>{};
  for (final file in archive.files) {
    final path = safeZipPath(file.name);
    if (!file.isFile || path == null || !selected.contains(path)) continue;
    result[path] = file.content;
  }
  return result;
}

/// סוגי ארכיון נתמכים
enum ArchiveKind { zip, tar, tarGz }

/// מזהה את סוג הארכיון לפי שם הקובץ (null = לא נתמך)
ArchiveKind? archiveKindOf(String fileName) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.zip')) return ArchiveKind.zip;
  if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) return ArchiveKind.tarGz;
  if (name.endsWith('.tar')) return ArchiveKind.tar;
  return null;
}

Archive decodeArchiveBytes(Uint8List bytes, ArchiveKind kind) {
  switch (kind) {
    case ArchiveKind.zip:
      return ZipDecoder().decodeBytes(bytes);
    case ArchiveKind.tar:
      return TarDecoder().decodeBytes(bytes);
    case ArchiveKind.tarGz:
      return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  }
}

/// רשימת הקבצים הניתנים לייבוא מתוך ארכיון בזיכרון (ZIP / TAR / TAR.GZ)
List<ZipEntry> listImportableEntriesFromBytes(
    Uint8List bytes, List<String> allowedExtensions, ArchiveKind kind) {
  final archive = decodeArchiveBytes(bytes, kind);
  final allowed =
      allowedExtensions.map((extension) => extension.toLowerCase()).toSet();
  final entries = <ZipEntry>[];
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final path = safeZipPath(file.name);
    if (path != null && _allowed(path, allowed)) {
      entries.add(ZipEntry(path: path, size: file.size));
    }
  }
  return entries;
}

/// קורא ארכיון מהזיכרון: פותח אותו פעם אחת ומחלץ קובץ בודד בכל פעם,
/// כך שלא צריך להחזיק את כל הקבצים שחולצו בזיכרון בו-זמנית.
class ZipBytesReader {
  final Archive _archive;
  final Map<String, ArchiveFile> _byPath = {};

  ZipBytesReader(Uint8List bytes, [ArchiveKind kind = ArchiveKind.zip])
      : _archive = decodeArchiveBytes(bytes, kind) {
    for (final file in _archive.files) {
      final path = safeZipPath(file.name);
      if (file.isFile && path != null) _byPath[path] = file;
    }
  }

  Uint8List? read(String path) {
    final file = _byPath[path];
    if (file == null) return null;
    return file.content;
  }
}
