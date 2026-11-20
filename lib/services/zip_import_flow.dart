import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../models/lesson_import_info.dart';
import '../models/media.dart';
import '../models/song.dart';
import '../models/unassigned_media.dart';
import '../screens/zip_import_dialog.dart';
import '../utils/helpers.dart';
import 'app_state.dart';
import 'file_service.dart';
import 'folder_tools.dart';
import 'github_media.dart';
import 'media_upload.dart';
import 'storage.dart';
import 'zip_bytes.dart';

/// תהליך ייבוא ZIP מלא: בחירת קובץ → טבלה (שיעור / שיר / לא משויך + כל שדות העריכה) → העלאה.
///
/// קובץ שסומן בטבלה כ״שיעור״ או ״שיר״ נשמר ישירות כשיעור / כשיר עם כל הפרטים
/// שהוזנו (ולא כקובץ לא משויך). רק קובץ שסומן ״לא משויך״ נשמר ברשימת הלא משויכים.
///
/// אין מגבלת גודל ל-ZIP: בטלפון/מחשב הוא נקרא מהדיסק בלי לטעון לזיכרון,
/// ובדפדפן הקבצים מחולצים ומועלים אחד-אחד.
/// [defaultTarget] – הסוג ההתחלתי בטבלה (מטפסי עריכה: ״לא משויך״, כדי לבחור אחר כך).
/// מחזיר כמה קבצים יובאו בפועל (0 אם בוטל או נכשל).
Future<int> importZipFlow(BuildContext context,
    {ZipImportTarget defaultTarget = ZipImportTarget.lesson}) async {
  final useLocal = app.localEnabled && !kIsWeb;
  final useGithub = app.githubReady;
  if (!useLocal && !useGithub) {
    snack(context,
        'הגדר תיקייה מקומית או התחבר למאגר GitHub בהגדרות כדי לייבא ארכיון');
    return 0;
  }

  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: archiveExts,
      // בדפדפן אין נתיב – חייבים את התוכן. בשאר הפלטפורמות קוראים מהדיסק.
      withData: kIsWeb,
    );
  } catch (error) {
    if (context.mounted) snack(context, 'בחירת קובץ ה-ZIP נכשלה: $error');
    return 0;
  }
  final zip = picked?.files.firstOrNull;
  if (zip == null) return 0;
  if (!context.mounted) return 0;

  final kind = archiveKindOf(zip.name);
  if (kind == null) {
    snack(context,
        'סוג הקובץ אינו נתמך. אפשר לייבא רק ZIP, TAR או TAR.GZ (RAR ו-7Z יש להמיר ל-ZIP).');
    return 0;
  }
  final zipPath = safePickedPath(zip);
  var zipBytes = zip.bytes;
  if (zipPath == null && zipBytes == null) {
    snack(context, 'לא ניתן לקרוא את תוכן הארכיון');
    return 0;
  }

  try {
    // ZIP במכשיר נקרא ישירות מהדיסק (בלי זיכרון). דפדפן ו-TAR/TAR.GZ נקראים מהזיכרון.
    final bytesMode = zipPath == null || kind != ArchiveKind.zip;
    if (bytesMode && zipBytes == null) {
      zipBytes = Uint8List.fromList(await readLocalRange(zipPath!, 0, zip.size));
    }
    final entries = bytesMode
        ? listImportableEntriesFromBytes(zipBytes!, importExts, kind)
        : await listImportableZipEntries(zipPath, importExts);
    if (!context.mounted) return 0;
    if (entries.isEmpty) {
      snack(context, 'לא נמצאו בארכיון קובצי שמע נתמכים (MP3, AAC, WAV, FLAC, OGG)');
      return 0;
    }

    final selections = await showDialog<List<ZipImportSelection>>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ZipImportDialog(entries: entries, defaultTarget: defaultTarget),
    );
    if (selections == null || selections.isEmpty || !context.mounted) return 0;

    final sizeOf = {for (final entry in entries) entry.path: entry.size};
    final selected = selections.map((item) => item.path).toSet();
    final zipName = zip.name
        .replaceAll(RegExp(r'\.zip$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final zipFolder =
        'inbox/${zipName.isEmpty ? 'archive' : zipName}_${DateTime.now().millisecondsSinceEpoch}';
    await app.addCustomParashot(selections
        .where((item) =>
            item.target != ZipImportTarget.song && item.parashaKind == 'event')
        .map((item) => item.parasha));

    LessonImportInfo infoOf(ZipImportSelection selection) => LessonImportInfo(
          title: selection.title,
          number: selection.number,
          parasha: selection.parasha,
          parashaKind: selection.parashaKind,
        );

    final failed = <String>[];

    // נתיב הקובץ בתיקייה המקומית, לכל קובץ שחולץ אליה
    final localPaths = <String, String>{};
    // תוצאת ההעלאה ל-GitHub, לכל קובץ שהועלה
    final uploaded = <String, UnassignedMedia>{};
    // קבצים ״לא משויכים״ שנשמרו בפועל
    final unassignedSaved = <String>{};

    ZipBytesReader? reader;
    if (bytesMode) reader = ZipBytesReader(zipBytes!, kind);

    if (useLocal) {
      await runWithProgress<int>(
        context,
        'מייבא קבצים מתוך הארכיון',
        (report) async {
          if (!bytesMode) {
            return extractSelectedZipEntries(app.localFolder, zipPath, selected,
                sub: zipFolder, onProgress: report);
          }
          var done = 0;
          for (final path in selected) {
            final bytes = reader!.read(path);
            if (bytes == null) continue;
            await writeBytesToFolder(app.localFolder, '$zipFolder/$path', bytes);
            report(++done, selected.length);
          }
          return done;
        },
      );
      for (final selection in selections) {
        final path = '${app.localFolder}/$zipFolder/${selection.path}';
        if (!localFileExists(path)) {
          failed.add('${selection.path.split('/').last} (החילוץ נכשל)');
          continue;
        }
        localPaths[selection.path] = path;
        if (selection.target == ZipImportTarget.unassigned) {
          unassignedSaved.add(selection.path);
        }
      }
      // רק ״לא משויך״ נשמר כהצעת שיעור; שיעור/שיר נוצרים ישירות בהמשך
      app.setImportedLessonInfo({
        for (final selection in selections)
          if (selection.target == ZipImportTarget.unassigned &&
              !(selection.duplicate && selection.duplicateAction == ZipDuplicateAction.replace) &&
              localPaths.containsKey(selection.path))
            '$zipFolder/${selection.path}': infoOf(selection),
      });
    }

    if (useGithub) {
      String? tempRoot;
      // בייבוא לתיקייה מקומית מעלים מהקבצים שנכתבו; אחרת ישירות מהזיכרון
      final fromMemory = reader != null && !useLocal;
      try {
        if (!bytesMode && !useLocal) {
          // GitHub בלבד במכשיר: מחלצים לתיקייה זמנית ומעלים משם בזרימה
          tempRoot = await makeTempFolder();
          if (!context.mounted) return localPaths.length;
          await runWithProgress<int>(
            context,
            'מכין קבצים להעלאה',
            (report) => extractSelectedZipEntries(tempRoot!, zipPath, selected,
                sub: 'z', onProgress: report),
          );
        }

        for (final selection in selections) {
          if (!context.mounted) break;
          final name = selection.path.split('/').last;
          final size = sizeOf[selection.path] ?? 0;
          try {
            final PickedMedia media;
            if (fromMemory) {
              final bytes = reader.read(selection.path);
              if (bytes == null) {
                throw Exception('לא ניתן לפתוח את $name מתוך ה-ZIP');
              }
              media =
                  PickedMedia(path: null, name: name, size: bytes.length, bytes: bytes);
            } else {
              final base =
                  useLocal ? '${app.localFolder}/$zipFolder' : '$tempRoot/z';
              media = PickedMedia(
                  path: '$base/${selection.path}', name: name, size: size);
            }
            final unassigned = selection.target == ZipImportTarget.unassigned;
            final asset = UnassignedMedia(
                id: app.newId(),
                lessonInfo: unassigned ? infoOf(selection) : null);
            await runWithProgress(
              context,
              'מעלה את $name',
              (report) => GitHubMedia.upload(media, asset,
                  folder: switch (selection.target) {
                    ZipImportTarget.lesson => 'lessons',
                    ZipImportTarget.song => 'songs',
                    ZipImportTarget.unassigned => 'inbox',
                  },
                  onProgress: report),
            );
            if (unassigned &&
                !(selection.duplicate &&
                    selection.duplicateAction == ZipDuplicateAction.replace)) {
              app.unassignedMedia.add(asset);
              unassignedSaved.add(selection.path);
            } else {
              uploaded[selection.path] = asset;
              if (unassigned) unassignedSaved.add(selection.path);
            }
          } catch (error) {
            failed.add('$name ($error)');
          }
        }
      } finally {
        if (tempRoot != null) await deleteFolder(tempRoot);
      }
    }

    // ---- החלפת מדיה קיימת לפי שם קובץ בלבד ----
    final replacedPaths = <String>{};
    var filesReplaced = 0;
    for (final selection in selections) {
      if (!selection.duplicate ||
          selection.duplicateAction != ZipDuplicateAction.replace) continue;
      final old = _findExistingMedia(selection.path.split('/').last);
      final local = localPaths[selection.path];
      final remote = uploaded[selection.path];
      if (old == null || (local == null && remote == null)) continue;
      final oldPath = old.filePath;
      final oldAsset = old.assetApi;
      _attachImportedMedia(old,
          localPath: local,
          remote: remote,
          name: selection.path.split('/').last,
          size: sizeOf[selection.path] ?? 0);
      final stillReferenced = <MediaFields>[
        ...app.lessons,
        ...app.songs,
        ...app.unassignedMedia,
      ].any((item) => !identical(item, old) &&
          ((oldPath != null && item.filePath == oldPath) ||
              (oldAsset != null && item.assetApi == oldAsset)));
      if (!stillReferenced && oldPath != null && oldPath != local) {
        unawaited(deleteMedia(oldPath));
      }
      if (!stillReferenced && oldAsset != null && oldAsset != remote?.assetApi && app.githubReady) {
        unawaited(GitHubMedia.deleteAsset(oldAsset).catchError((_) {}));
      }
      replacedPaths.add(selection.path);
      filesReplaced++;
    }

    // ---- יצירת השיעורים והשירים עם כל הפרטים מהטבלה ----
    var lessonsCreated = 0;
    var songsCreated = 0;
    final newSongs = <(Song, String?)>[];
    var sequence = 0;
    for (final selection in selections) {
      final local = localPaths[selection.path];
      final remote = uploaded[selection.path];
      final name = selection.path.split('/').last;
      final size = sizeOf[selection.path] ?? 0;

      // הוחלפה המדיה בפריט הקיים; אין ליצור רשומה נוספת.
      if (replacedPaths.contains(selection.path)) continue;
      // ״לא משויך״: כבר נשמר למעלה (מקומית ו/או ב-GitHub)
      if (selection.target == ZipImportTarget.unassigned) continue;
      // הקובץ לא נשמר באף מקום (ההעלאה נכשלה ואין תיקייה מקומית)
      if (local == null && remote == null) continue;

      final id = '${app.newId()}_${sequence++}';
      final date = selection.date ?? DateTime.now();
      if (selection.target == ZipImportTarget.lesson) {
        final lesson = Lesson(
            id: id,
            title: selection.title,
            notes: selection.notes,
            date: date)
          ..number = selection.number
          ..parasha = selection.parasha
          ..parashaKind = selection.parashaKind
          ..dateKind = selection.dateKind;
        _attachImportedMedia(lesson,
            localPath: local, remote: remote, name: name, size: size);
        app.lessons.add(lesson);
        lessonsCreated++;
      } else {
        final song = Song(
          id: id,
          title: selection.title,
          singerId: selection.singerId ?? '',
          lyrics: selection.lyrics,
          notes: selection.notes,
          year: selection.year,
          eventDate: date,
          location: selection.location,
        );
        _attachImportedMedia(song,
            localPath: local, remote: remote, name: name, size: size);
        app.songs.add(song);
        songsCreated++;
        newSongs.add((song, local));
      }
    }
    app.save();

    // זיהוי משך לשירים שנשמרו במכשיר (לא חוסם: כשל – פשוט נשאר ריק)
    final probeable = newSongs.where((item) => item.$2 != null).toList();
    if (probeable.isNotEmpty && context.mounted) {
      await runWithProgress<void>(context, 'מזהה משך שירים', (report) async {
        var done = 0;
        for (final (song, path) in probeable) {
          try {
            final duration = await probeDuration(PickedMedia(
                path: path, name: song.fileName ?? 'audio', size: song.fileSize ?? 0));
            if (duration != null) song.duration = formatDuration(duration);
          } catch (_) {}
          report(++done, probeable.length);
        }
      });
      app.save();
    }

    final unassignedCount = unassignedSaved.difference(replacedPaths).length;
    final total = lessonsCreated + songsCreated + unassignedCount + filesReplaced;
    if (context.mounted) {
      final summary = [
        if (lessonsCreated > 0) '$lessonsCreated שיעורים',
        if (songsCreated > 0) '$songsCreated שירים',
        if (unassignedCount > 0) '$unassignedCount קבצים לא משויכים',
        if (filesReplaced > 0) '$filesReplaced קבצים הוחלפו',
      ].join(', ');
      if (failed.isEmpty) {
        snack(context, 'יובאו $summary.');
      } else {
        snack(context,
            'יובאו $summary, ${failed.length} נכשלו:\n${failed.take(3).join('\n')}');
      }
    }
    return total;
  } catch (error) {
    if (context.mounted) snack(context, 'ייבוא ה-ZIP נכשל: $error');
    return 0;
  }
}

MediaFields? _findExistingMedia(String fileName) {
  final expected = fileName.trim().toLowerCase();
  for (final media in <MediaFields>[
    ...app.lessons,
    ...app.songs,
    ...app.unassignedMedia,
  ]) {
    if (media.fileName?.trim().toLowerCase() == expected) return media;
  }
  return null;
}

/// מצמיד לשיעור / שיר את הקובץ שיובא: נתיב מקומי ו/או כתובות GitHub
void _attachImportedMedia(MediaFields target,
    {String? localPath,
    UnassignedMedia? remote,
    required String name,
    required int size}) {
  target
    ..filePath = localPath
    ..fileName = name
    ..fileSize = remote?.fileSize ?? size
    ..remoteUrl = remote?.remoteUrl
    ..assetApi = remote?.assetApi
    ..clipStartMs = null
    ..clipEndMs = null;
}
