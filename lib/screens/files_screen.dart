import '../models/lesson.dart';
import '../models/media.dart';
import '../models/song.dart';
import '../models/unassigned_media.dart';
import '../services/file_service.dart';
import '../services/github_media.dart';
import '../services/media_resolver.dart';
import '../services/media_upload.dart';
import '../services/app_state.dart';
import '../services/storage.dart';
import '../services/player_service.dart';
import '../services/media_download.dart';
import '../services/export_service.dart';
import '../utils/helpers.dart';
import '../widgets/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/folder_tools.dart';
import '../services/zip_import_flow.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final Map<MediaFields, double?> downloading = {};
  int uploadTotal = 0;
  int uploadDone = 0;
  int uploadFailed = 0;
  bool uploading = false;
  String _fileQuery = '';
  late Future<List<FreeFile>> _freeFilesFuture;

  @override
  void initState() {
    super.initState();
    _freeFilesFuture = app.freeMediaFiles(extensions: importExts);
  }

  Future<bool> _requireStorage() async {
    if (app.localEnabled || app.githubReady) return true;
    snack(context,
        'הגדר תיקייה מקומית או התחבר למאגר GitHub בהגדרות כדי להעלות קבצים');
    return false;
  }

  Future<void> _uploadFiles() async {
    if (!await _requireStorage()) return;
    final useLocal = app.localEnabled && !kIsWeb;
    final useGithub = app.githubReady;
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: audioExts,
        allowMultiple: true,
        // בדפדפן אין נתיב קובץ – קוראים את התוכן (bytes)
        withData: kIsWeb,
      );
    } catch (error) {
      if (mounted) snack(context, 'בחירת הקבצים נכשלה: $error');
      return;
    }
    if (picked == null || picked.files.isEmpty) return;
    setState(() {
      uploadTotal = picked!.files.length;
      uploadDone = 0;
      uploadFailed = 0;
      uploading = true;
    });
    // חסימה: רק קבצי שמע מזוהים (MP3, AAC, WAV, FLAC, OGG)
    final rejected = picked.files
        .where((file) => !hasAllowedExt(file.name, audioExts))
        .map((file) => file.name)
        .toList();
    if (rejected.isNotEmpty) {
      setState(() => uploading = false);
      snack(context,
          'סוג קובץ לא נתמך: ${rejected.take(3).join(', ')}. מותר רק MP3, AAC, WAV, FLAC, OGG (או ארכיון ZIP / TAR.GZ בכפתור הייבוא).');
      return;
    }
    try {
      var copiedCount = 0;
      var uploadedCount = 0;
      if (useLocal) {
        final paths = picked.files
            .map(safePickedPath)
            .whereType<String>()
            .toList();
        if (paths.length != picked.files.length) {
          throw Exception('לא ניתן לקרוא את הקבצים שנבחרו');
        }
        copiedCount = (await copyFilesToFolder(app.localFolder, paths)).length;
        if (!useGithub && mounted) setState(() => uploadDone = copiedCount);
      }
      if (useGithub) {
        for (final file in picked.files) {
          final path = safePickedPath(file);
          if (path == null && file.bytes == null) {
            throw Exception('לא ניתן לקרוא את ${file.name}');
          }
          final asset = UnassignedMedia(id: app.newId());
          final media = PickedMedia(
              path: path,
              name: file.name,
              size: file.bytes?.length ?? file.size,
              bytes: file.bytes);
          if (!mounted) return;
          await runWithProgress(
              context,
              'מעלה את ${file.name}',
              (report) => GitHubMedia.upload(media, asset,
                  folder: 'inbox', onProgress: report));
          app.unassignedMedia.add(asset);
          uploadedCount++;
          if (mounted) setState(() => uploadDone = uploadedCount);
        }
        app.save();
      }
      if (mounted) {
        setState(() {
          _freeFilesFuture = app.freeMediaFiles(extensions: importExts);
        });
        final count = useLocal ? copiedCount : uploadedCount;
        snack(context,
            'הועלו $count קבצים. הם מופיעים ב״לא משויך״ עד לבחירתם בשיעור או בשיר.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => uploadFailed = uploadTotal - uploadDone);
        snack(context, 'העלאת הקבצים נכשלה: $error');
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _uploadZip() async {
    if (!await _requireStorage() || !mounted) return;
    final count = await importZipFlow(context);
    if (count > 0 && mounted) {
      setState(() {
        _freeFilesFuture = app.freeMediaFiles(extensions: importExts);
      });
    }
  }

  bool _matchesQuery(Iterable<String?> values) {
    final query = _fileQuery.trim().toLowerCase();
    return query.isEmpty ||
        values.whereType<String>().any((value) => value.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final songs = <Song>[];
          final lessons =
              app.lessons.where((lesson) => lesson.hasMedia).toList();
          final attached = [...songs, ...lessons];
          final visibleSongs = songs
              .where((song) => _matchesQuery([song.title, song.fileName]))
              .toList();
          final visibleLessons = lessons
              .where((lesson) => _matchesQuery([lesson.title, lesson.fileName]))
              .toList();
          final canImport = app.localEnabled || app.githubReady;
          return FutureBuilder<List<FreeFile>>(
            future: _freeFilesFuture,
            builder: (context, snapshot) {
              final localFiles = snapshot.data ?? const <FreeFile>[];
              final localNames =
                  localFiles.map((file) => file.name.toLowerCase()).toSet();
              final remoteFiles = app.unassignedMedia
                  .where((file) =>
                      file.fileName != null &&
                      !localNames.contains(file.fileName!.toLowerCase()))
                  .toList();
              final visibleLocalFiles = localFiles
                  .where((file) => _matchesQuery([file.name, file.relative]))
                  .toList();
              final visibleRemoteFiles = remoteFiles
                  .where((file) =>
                      _matchesQuery([
                        file.fileName,
                        file.lessonInfo?.title,
                        file.lessonInfo?.number?.toString(),
                        file.lessonInfo?.parasha,
                      ]))
                  .toList();
              final visibleAttached = [...visibleSongs, ...visibleLessons];
              final unassignedCount =
                  visibleLocalFiles.length + visibleRemoteFiles.length;
              final count = visibleAttached.length + unassignedCount;
              final allCount = attached.length + localFiles.length + remoteFiles.length;
              final size =
                  visibleAttached.fold<int>(0, (sum, media) => sum + (media.fileSize ?? 0)) +
                      visibleLocalFiles.fold<int>(0, (sum, file) => sum + file.size) +
                      visibleRemoteFiles.fold<int>(
                          0, (sum, file) => sum + (file.fileSize ?? 0));
              return Scaffold(
                appBar: AppBar(
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('קבצים'),
                        if (uploadTotal > 0)
                          Text(
                            '${uploadDone} עלו · ${uploadTotal - uploadDone - uploadFailed} ממתין · ${uploadFailed} שגיאות · מתוך $uploadTotal',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ), actions: [
                  IconButton(
                    tooltip: 'PDF – מספר, שם הקובץ ותאריך עברי',
                    onPressed: lessons.isEmpty && songs.isEmpty
                        ? null
                        : () => printNumberNameDate(
                            context,
                            [
                              for (final l in [...lessons]..sort((a, b) =>
                                  (a.number ?? 99999)
                                      .compareTo(b.number ?? 99999)))
                                (
                                  number: l.number?.toString() ?? '-',
                                  name: l.fileName ?? l.title,
                                  hebrewDate: hebrewDate(l.date),
                                ),
                              for (final s in songs)
                                (
                                  number: '-',
                                  name: s.fileName ?? s.title,
                                  hebrewDate: hebrewDate(s.eventDate ?? s.added),
                                ),
                            ],
                            title: 'רשימת קבצים',
                            nameHeader: 'שם הקובץ'),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                  ),
                  IconButton(
                    tooltip: 'העלאת קבצים',
                    onPressed: _uploadFiles,
                    icon: const Icon(Icons.upload_file_rounded),
                  ),
                  IconButton(
                    tooltip: 'ייבוא ארכיון (ZIP / TAR.GZ)',
                    onPressed: _uploadZip,
                    icon: const Icon(Icons.folder_zip_rounded),
                  ),
                ]),
                body: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : allCount == 0
                        ? EmptyState(
                            icon: Icons.folder_open_rounded,
                            title: 'אין קבצים',
                            subtitle: canImport
                                ? 'העלה קובץ בודד או ZIP כדי להוסיף קבצים לא משויכים'
                                : 'כדי להעלות קבצים, בחר תיקייה מקומית או התחבר למאגר GitHub בהגדרות',
                            action: Wrap(spacing: 8, children: [
                              FilledButton.icon(
                                onPressed: _uploadFiles,
                                icon: const Icon(Icons.upload_file_rounded),
                                label: const Text('העלאת קבצים'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _uploadZip,
                                icon: const Icon(Icons.folder_zip_rounded),
                                label: const Text('ייבוא ארכיון'),
                              ),
                            ]),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            children: [
                              SearchField(
                                hint: 'חיפוש בקבצים',
                                onChanged: (value) =>
                                    setState(() => _fileQuery = value),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _fileQuery.trim().isEmpty
                                    ? '$allCount קבצים · ${fmtBytes(size)}'
                                    : '$count מתוך $allCount קבצים · ${fmtBytes(size)}',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              if (count == 0)
                                const SizedBox(
                                  height: 220,
                                  child: EmptyState(
                                    icon: Icons.search_off_rounded,
                                    title: 'לא נמצאו קבצים',
                                    subtitle: 'נסה לשנות את מילות החיפוש',
                                  ),
                                ),
                              if (unassignedCount > 0) ...[
                                const SectionTitle('לא משויך'),
                                if (visibleLocalFiles.isNotEmpty)
                                  Card(
                                    child: Column(children: [
                                      for (final file in visibleLocalFiles)
                                        _freeFileTile(file),
                                    ]),
                                  ),
                                if (visibleRemoteFiles.isNotEmpty)
                                  Card(
                                    child: Column(children: [
                                      for (final file in visibleRemoteFiles)
                                        _remoteFileTile(file),
                                    ]),
                                  ),
                              ],
                              if (visibleSongs.isNotEmpty) ...[
                                const SectionTitle('שירים'),
                                Card(
                                  child: Column(children: [
                                    for (final song in visibleSongs)
                                      _tile(song, song.title, 'songs'),
                                  ]),
                                ),
                              ],
                              if (visibleLessons.isNotEmpty) ...[
                                const SectionTitle('שיעורים'),
                                Card(
                                  child: Column(children: [
                                    for (final lesson in visibleLessons)
                                      _tile(lesson, lesson.title, 'lessons'),
                                  ]),
                                ),
                              ],
                            ],
                          ),
              );
            },
          );
        },
      );

  Widget _remoteFileTile(UnassignedMedia file) {
    final colors = Theme.of(context).colorScheme;
    final info = file.lessonInfo;
    return ListTile(
      leading: Icon(Icons.cloud_done_rounded, color: colors.primary),
      title: Text(file.fileName ?? 'קובץ ללא שם',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          [
            fmtBytes(file.fileSize),
            if (info?.title.isNotEmpty == true) info!.title,
            if (info?.number != null) 'שיעור ${info!.number}',
            if (info?.parasha.isNotEmpty == true)
              '${info!.parashaKind == 'event' ? 'אירוע' : 'פרשה'} ${info.parasha}',
          ].where((value) => value.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (file.fileName != null &&
            audioExts.contains(file.fileName!.split('.').last.toLowerCase()))
          IconButton(
            tooltip: 'הפעלה',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () => _playMedia(file, file.fileName!),
          ),
        IconButton(
          tooltip: 'הורדה בשם המקורי',
          icon: const Icon(Icons.download_rounded),
          onPressed: () => _saveCopy(file),
        ),
        IconButton(
          tooltip: 'מחיקת הקובץ',
          icon: Icon(Icons.delete_outline_rounded, color: colors.error),
          onPressed: () async {
            if (!await confirm(context, 'למחוק את הקובץ \"${file.fileName}\"?')) {
              return;
            }
            try {
              await app.deleteUnassignedMedia(file.id);
            } catch (error) {
              if (mounted) snack(context, 'מחיקת הקובץ נכשלה: $error');
            }
          },
        ),
      ]),
    );
  }

  Widget _freeFileTile(FreeFile file) {
    final color = Theme.of(context).colorScheme;
    final ext = file.name.split('.').last.toLowerCase();
    final info = app.importedInfoFor(file.relative);
    final icon = ext == 'pdf'
        ? Icons.picture_as_pdf_rounded
        : const {'txt', 'srt', 'vtt', 'lrc'}.contains(ext)
            ? Icons.description_outlined
            : Icons.audio_file_rounded;
    return ListTile(
      leading: Icon(icon, color: color.primary),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          [
            fmtBytes(file.size),
            file.relative,
            if (info?.title.isNotEmpty == true) info!.title,
            if (info?.number != null) 'שיעור ${info!.number}',
            if (info?.parasha.isNotEmpty == true)
              '${info!.parashaKind == 'event' ? 'אירוע' : 'פרשה'} ${info.parasha}',
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (audioExts.contains(ext))
          IconButton(
            tooltip: 'הפעלה',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () => _playMedia(
                UnassignedMedia(id: 'local')
                  ..filePath = file.path
                  ..fileName = file.name,
                file.name),
          ),
        IconButton(
          tooltip: 'מחיקת הקובץ',
          icon: Icon(Icons.delete_outline_rounded, color: color.error),
          onPressed: () async {
            if (!await confirm(context, 'למחוק את הקובץ \"${file.name}\"?')) {
              return;
            }
            await deleteMedia(file.path);
            if (mounted) {
              setState(() {
                _freeFilesFuture = app.freeMediaFiles(extensions: importExts);
              });
            }
          },
        ),
      ]),
    );
  }

  Widget _tile(MediaFields m, String title, String folder) {
    final c = Theme.of(context).colorScheme;
    final onDevice = localFileExists(m.filePath);
    final offline = MediaResolver.isOffline(m);
    final dl = downloading.containsKey(m);
    return ListTile(
      leading: Icon(Icons.audio_file_rounded, color: c.primary),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            [m.fileName ?? '', fmtBytes(m.fileSize)]
                .where((e) => e.isNotEmpty)
                .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [
          if (m.isInCloud) const Pill('בענן', icon: Icons.cloud_done_rounded),
          if (offline)
            Pill('במכשיר',
                icon: Icons.phone_android_rounded, color: c.tertiary),
          if (!m.isInCloud && !onDevice)
            Pill('חסר במכשיר הזה',
                icon: Icons.warning_amber_rounded, color: c.error),
        ]),
        if (dl)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: downloading[m])),
      ]),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'הפעלה',
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: () => _action('play', m, folder),
        ),
        IconButton(
          tooltip: kIsWeb ? 'הורדה בשם המקורי' : 'שמירה לשימוש ללא אינטרנט',
          icon: Icon(kIsWeb
              ? Icons.download_rounded
              : Icons.offline_pin_outlined),
          onPressed: () => _action(kIsWeb ? 'web' : 'download', m, folder),
        ),
        if (!kIsWeb)
          IconButton(
            tooltip: 'שמירת עותק בשם המקורי',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => _action('web', m, folder),
          ),
        IconButton(
          tooltip: 'החלפת קובץ',
          icon: const Icon(Icons.swap_horiz_rounded),
          onPressed: () => _action('replace', m, folder),
        ),
        IconButton(
          tooltip: 'מחיקת הקובץ',
          icon: Icon(Icons.delete_outline_rounded, color: c.error),
          onPressed: () => _action('delete', m, folder),
        ),
      ]),
    );
  }

  /// שמירת עותק בשם המקורי (אותו שם שמוצג ברשימה), לא השם הטכני שבמאגר
  Future<void> _saveCopy(MediaFields m) => downloadWithOriginalName(context, m,
      fallbackTitle: m is Song
          ? m.title
          : m is Lesson
              ? m.title
              : '');

  String onDeviceMsg(MediaFields m) => localFileExists(m.filePath)
      ? 'הקובץ כבר שמור במכשיר'
      : 'הקובץ אינו זמין להורדה';

  Future<void> _playMedia(MediaFields media, String name) async {
    try {
      await player.open(
          Track('preview_$name', TrackKind.lesson, name, '', media));
    } catch (error) {
      if (mounted) snack(context, 'ההשמעה נכשלה: $error');
    }
  }

  Future<void> _action(String v, MediaFields m, String folder) async {
    switch (v) {
      case 'play':
        final track = m is Song ? Track.song(m) : Track.lesson(m as Lesson);
        await player.open(track);
        return;
      case 'web':
        await _saveCopy(m);
        return;
      case 'download':
        if (!m.isInCloud) {
          snack(context,
              onDeviceMsg(m));
          return;
        }
        setState(() => downloading[m] = null);
        try {
          await MediaResolver.ensureLocal(m, onProgress: (g, t) {
            if (mounted && t != null) setState(() => downloading[m] = g / t);
          });
          app.save();
          if (mounted) snack(context, 'נשמר במכשיר להאזנה ללא אינטרנט');
        } catch (e) {
          if (mounted) snack(context, 'ההורדה נכשלה: $e');
        }
        if (mounted) setState(() => downloading.remove(m));
      case 'unoffline':
        await MediaResolver.removeOffline(m);
        app.save();
        setState(() {});
      case 'upload':
        if (await uploadExisting(context, m, folder: folder)) app.save();
      case 'replace':
        final f = await pickAudio();
        if (f == null || !mounted) return;
        await MediaResolver.removeOffline(m);
        if (await attachMedia(context, m, f, folder: folder)) {
          if (m is Lesson) app.prefs.remove('pos_${m.id}');
          if (m is Song) m.stamps = [];
          app.save();
        }
      case 'delete':
        if (!await confirm(context, 'למחוק את הקובץ? השיר/השיעור עצמו יישאר.'))
          return;
        await MediaResolver.removeOffline(m);
        await deleteMedia(m.filePath);
        if (m.assetApi != null && app.githubReady) {
          GitHubMedia.deleteAsset(m.assetApi!).catchError((_) {});
        }
        m.clearMedia();
        app.save();
    }
  }
}
