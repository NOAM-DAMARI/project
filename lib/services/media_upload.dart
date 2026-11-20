import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import '../models/media.dart';
import '../utils/helpers.dart';
import '../utils/mp3.dart';
import 'app_state.dart';
import 'file_service.dart';
import 'github_media.dart';
import 'storage.dart';
import 'local_sync.dart';
import '../screens/zip_import_dialog.dart' show ZipImportTarget;
import 'zip_import_flow.dart';

/// בחירת קובץ מהמאגר (קבצים לא משויכים), עם אפשרות להעלות ZIP חדש/מעודכן
/// (נפתחת טבלת שיעורים) ואז לחזור לבחירה מהרשימה המעודכנת.
Future<PickedMedia?> pickFreeMedia(BuildContext context) async {
  while (true) {
    final result = await _pickFreeMediaOnce(context);
    if (result is PickedMedia) return result;
    if (result != _zipRequest || !context.mounted) return null;
    await importZipFlow(context, defaultTarget: ZipImportTarget.unassigned);
    if (!context.mounted) return null;
  }
}

const _zipRequest = 'zip-request';

Future<Object?> _pickFreeMediaOnce(BuildContext context) async {
  final localFiles = await app.freeMediaFiles(extensions: audioExts);
  if (!context.mounted) return null;
  final localNames = localFiles.map((file) => file.name.toLowerCase()).toSet();
  final remoteFiles = app.unassignedMedia.where((file) {
    final name = file.fileName;
    if (name == null || localNames.contains(name.toLowerCase())) return false;
    final dot = name.lastIndexOf('.');
    return dot > 0 && audioExts.contains(name.substring(dot + 1).toLowerCase());
  }).toList();
  final choices = <({PickedMedia media, String detail})>[
    for (final file in localFiles)
      (
        media: PickedMedia(
          path: file.path,
          name: file.name,
          size: file.size,
          importedMetadataKey: file.relative,
          suggestedLesson: app.importedInfoFor(file.relative),
        ),
        detail: file.relative,
      ),
    for (final file in remoteFiles)
      (
        media: PickedMedia(
          path: file.filePath,
          name: file.fileName!,
          size: file.fileSize ?? 0,
          remoteUrl: file.remoteUrl,
          assetApi: file.assetApi,
          unassignedId: file.id,
          suggestedLesson: file.lessonInfo,
        ),
        detail: 'מאגר GitHub',
      ),
  ];
  final search = TextEditingController();
  final chosen = await showDialog<Object>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, updateDialog) {
        final query = search.text.trim().toLowerCase();
        final visible = choices.where((choice) =>
            choice.media.name.toLowerCase().contains(query) ||
            choice.detail.toLowerCase().contains(query));
        return AlertDialog(
          title: Text('קבצים לא משויכים (${choices.length})'),
          content: SizedBox(
            width: 520,
            height: 440,
            child: Column(children: [
              TextField(
                controller: search,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'חיפוש קובץ',
                    prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (_) => updateDialog(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: choices.isEmpty
                    ? const Center(
                        child: Text(
                            'אין קבצים לא משויכים.\nהעלה ZIP חדש כדי להוסיף שיעורים.',
                            textAlign: TextAlign.center))
                    : ListView(children: [
                  for (final choice in visible)
                    ListTile(
                      leading: Icon(choice.media.unassignedId == null
                          ? Icons.audio_file_rounded
                          : Icons.cloud_done_rounded),
                      title: Text(choice.media.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${fmtBytes(choice.media.size)} · ${choice.detail}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(dialogContext, choice.media),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton.icon(
                onPressed: () => Navigator.pop(dialogContext, _zipRequest),
                icon: const Icon(Icons.folder_zip_rounded),
                label: const Text('העלאת ZIP חדש / מעודכן')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ביטול'))
          ],
        );
      },
    ),
  );
  search.dispose();
  return chosen;
}

/// מצרף קובץ שנבחר לשיר/שיעור: שומר במכשיר, ואם GitHub מחובר – מעלה עם חלון התקדמות.
/// מחזיר true אם הקובץ נשמר (גם אם רק במכשיר).
Future<bool> attachMedia(
    BuildContext context, MediaFields target, PickedMedia picked,
    {required String folder}) async {
  final oldLocal = target.filePath;
  final oldAsset = target.assetApi;

  if (picked.unassignedId != null) {
    final imported = app.unassignedById(picked.unassignedId!);
    if (imported == null) {
      if (context.mounted) snack(context, 'הקובץ כבר אינו זמין במאגר');
      return false;
    }
    if (oldLocal != null && oldLocal != imported.filePath)
      deleteMedia(oldLocal).catchError((_) {});
    if (oldAsset != null && oldAsset != imported.assetApi && app.githubReady) {
      GitHubMedia.deleteAsset(oldAsset).catchError((_) {});
    }
    target
      ..filePath = imported.filePath
      ..fileName = imported.fileName
      ..fileSize = imported.fileSize
      ..remoteUrl = imported.remoteUrl
      ..assetApi = imported.assetApi;
    app.consumeUnassignedMedia(imported.id);
    return true;
  }

  target
    ..filePath = picked.path
    ..fileName = picked.name
    ..fileSize = picked.size
    ..remoteUrl = picked.remoteUrl
    ..assetApi = picked.assetApi ?? oldAsset;

  if (oldLocal != null && oldLocal != picked.path)
    deleteMedia(oldLocal).catchError((_) {});

  if (app.localEnabled && picked.path != null) {
    try {
      await copyMediaToLocal(
          app.localFolder, picked.path!, picked.name, folder);
    } catch (e) {
      debugPrint('local media copy failed: $e');
    }
  }

  if (!app.githubReady) {
    target.assetApi = null;
    if (kIsWeb) {
      if (context.mounted)
        snack(context, 'כדי לשמור קובץ בדפדפן יש להתחבר למאגר GitHub בהגדרות');
      return false;
    }
    app.consumeImportedLessonInfo(picked.importedMetadataKey);
    return true;
  }

  try {
    await runWithProgress(context, 'מעלה את "${picked.name}"', (report) {
      return GitHubMedia.upload(picked, target,
          folder: folder, onProgress: report);
    });
    app.consumeImportedLessonInfo(picked.importedMetadataKey);
    return true;
  } catch (e) {
    target.assetApi = null;
    if (context.mounted) {
      snack(context,
          'ההעלאה ל-GitHub נכשלה – הקובץ נשמר במכשיר. אפשר לנסות שוב ממסך הקבצים.\n$e');
    }
    final savedLocally = picked.path != null;
    if (savedLocally) app.consumeImportedLessonInfo(picked.importedMetadataKey);
    return savedLocally;
  }
}

/// העלאה מאוחרת של קובץ שנשמר רק במכשיר
Future<bool> uploadExisting(BuildContext context, MediaFields target,
    {required String folder}) async {
  final path = target.filePath;
  final size = localFileSize(path);
  if (path == null || size == null) {
    snack(context, 'הקובץ לא נמצא במכשיר');
    return false;
  }
  try {
    await runWithProgress(context, 'מעלה את "${target.fileName ?? 'הקובץ'}"',
        (report) {
      return GitHubMedia.upload(
          PickedMedia(path: path, name: target.fileName ?? 'audio', size: size),
          target,
          folder: folder,
          onProgress: report);
    });
    return true;
  } catch (e) {
    if (context.mounted) snack(context, 'ההעלאה נכשלה: $e');
    return false;
  }
}

/// זיהוי משך הקובץ (כל פורמט שהנגן תומך בו; גיבוי – חישוב מכותרת MP3)
Future<Duration?> probeDuration(PickedMedia m) async {
  if (m.path != null) {
    final probe = AudioPlayer();
    try {
      final d =
          await probe.setFilePath(m.path!).timeout(const Duration(seconds: 8));
      if (d != null && d > Duration.zero) return d;
    } catch (_) {
    } finally {
      probe.dispose();
    }
    final head =
        await readLocalRange(m.path!, 0, m.size < 65536 ? m.size : 65536);
    return estimateMp3Duration(head, m.size);
  }
  if (m.bytes != null)
    return estimateMp3Duration(m.bytes!.take(65536).toList(), m.size);
  return null;
}

String formatDuration(Duration d) => d.inHours > 0
    ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}'
    : '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
