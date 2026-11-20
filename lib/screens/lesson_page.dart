import '../models/lesson.dart';
import '../models/media.dart';
import '../models/song.dart';
import '../services/app_state.dart';
import '../services/export_service.dart';
import '../services/audio_processing.dart';
import '../services/media_download.dart';
import '../services/player_service.dart';
import '../services/transcriber.dart';
import '../utils/helpers.dart';
import '../widgets/player_controls.dart';
import '../widgets/seg_list.dart';
import '../widgets/point_dialog.dart';
import '../services/points.dart';
import '../services/text_aligner.dart';
import 'lesson_form.dart';
import 'settings_screen.dart';
import 'transcripts_screen.dart';
import 'subtitle_editor_screen.dart';
import 'points_screen.dart';
import '../services/subtitle_formats.dart';
import '../widgets/live_subtitles.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

class LessonPage extends StatefulWidget {
  final Lesson l;
  final int initialTab;
  const LessonPage(this.l, {super.key, this.initialTab = 0});
  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  Lesson get l => widget.l;
  late final summary = TextEditingController(text: l.summary);
  bool busy = false;
  String status = '';

  Track get track => Track.lesson(l);

  @override
  void initState() {
    super.initState();
    player.markFullScreen(l.id, true);
  }

  @override
  void dispose() {
    player.markFullScreen(l.id, false);
    summary.dispose();
    super.dispose();
  }

  void changed() {
    app.save();
    setState(() {});
  }

  Future<void> _createClip() async {
    if (!l.hasMedia) {
      snack(context, 'יש לצרף הקלטה לשיעור לפני יצירת קטע');
      return;
    }
    final position = player.isCurrent(l.id) ? player.p.position.inSeconds : 0;
    final duration = player.isCurrent(l.id) ? player.p.duration?.inSeconds : null;
    final title = TextEditingController(text: 'קטע – ${l.title}');
    final start = TextEditingController(text: '$position');
    final end = TextEditingController(text: '${duration != null && duration > position ? duration : position + 60}');
    var asSong = false;
    var singerId = app.singers.isEmpty ? null : app.singers.first.id;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('יצירת קטע מתוך השיעור'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'שם הקטע')),
                Row(children: [
                  Expanded(child: TextField(controller: start, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'התחלה (שניות)'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: end, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'סיום (שניות)'))),
                ]),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('כשיעור')),
                    ButtonSegment(value: true, label: Text('כשיר')),
                  ],
                  selected: {asSong},
                  onSelectionChanged: (value) => setDialogState(() => asSong = value.first),
                ),
                if (asSong && app.singers.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: singerId,
                    decoration: const InputDecoration(labelText: 'זמר'),
                    items: [for (final singer in app.singers) DropdownMenuItem(value: singer.id, child: Text(singer.name))],
                    onChanged: (value) => setDialogState(() => singerId = value),
                  ),
                if (asSong && app.singers.isEmpty)
                  const Padding(padding: EdgeInsets.only(top: 8), child: Text('כדי לשמור כשיר, הוסף קודם זמר.')),
                const SizedBox(height: 8),
                Text('הקטע יישמר כפריט חדש וינגן את הטווח מתוך קובץ המקור.', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('ביטול')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, {
              'title': title.text.trim(),
              'start': int.tryParse(start.text.trim()),
              'end': int.tryParse(end.text.trim()),
              'song': asSong,
              'singerId': singerId,
            }), child: const Text('שמירת קטע')),
          ],
        ),
      ),
    );
    title.dispose();
    start.dispose();
    end.dispose();
    if (result == null || !mounted) return;
    final clipTitle = result['title'] as String? ?? '';
    final startSeconds = result['start'] as int?;
    final endSeconds = result['end'] as int?;
    final toSong = result['song'] == true;
    final clipSinger = result['singerId'] as String?;
    if (clipTitle.isEmpty || startSeconds == null || endSeconds == null || startSeconds < 0 || endSeconds <= startSeconds) {
      snack(context, 'יש למלא שם וטווח זמן תקין');
      return;
    }
    if (toSong && clipSinger == null) {
      snack(context, 'הוסף זמר כדי ליצור פריט שיר');
      return;
    }
    final startMs = startSeconds * 1000;
    final endMs = endSeconds * 1000;
    if (toSong) {
      final song = Song(id: app.newId(), title: clipTitle, singerId: clipSinger!, eventDate: l.date);
      song.stamps = [for (final seg in l.transcript.where((seg) => seg.ms >= startMs && seg.ms < endMs)) seg.ms - startMs];
      song.lyrics = l.transcript.where((seg) => seg.ms >= startMs && seg.ms < endMs).map((seg) => seg.text).join('\n');
      _attachClipMedia(song, startMs, endMs);
      app.songs.add(song);
    } else {
      final lesson = Lesson(id: app.newId(), title: clipTitle, date: l.date, notes: 'קטע מתוך: ${l.title}')
        ..parasha = l.parasha
        ..parashaKind = l.parashaKind
        ..number = null;
      lesson.transcript = [for (final seg in l.transcript.where((seg) => seg.ms >= startMs && seg.ms < endMs)) Seg(seg.ms - startMs, seg.text)];
      _attachClipMedia(lesson, startMs, endMs);
      app.lessons.add(lesson);
    }
    app.save();
    if (mounted) snack(context, 'הקטע נוסף לרשימה ומשתמש בטווח מתוך ההקלטה המקורית');
  }

  void _attachClipMedia(MediaFields target, int startMs, int endMs) {
    target
      ..filePath = l.filePath
      ..fileName = l.fileName
      ..fileSize = l.fileSize
      ..remoteUrl = l.remoteUrl
      ..assetApi = l.assetApi
      ..clipStartMs = startMs
      ..clipEndMs = endMs;
  }

  Future<void> _exportProcessedAudio() async {
    if (!l.hasMedia) {
      snack(context, 'יש לצרף הקלטה לשיעור לפני עיבוד');
      return;
    }
    final position = player.isCurrent(l.id) ? player.p.position.inSeconds : 0;
    final duration = player.isCurrent(l.id) ? player.p.duration?.inSeconds : null;
    final start = TextEditingController(text: '0');
    final end = TextEditingController(
        text: '${duration != null && duration > 0 ? duration : position + 60}');
    var reduceNoise = true;
    var strength = 18.0;
    final options = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('חיתוך והפחתת רעשי רקע'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('הקובץ המעובד יישמר כ-M4A; קובץ המקור לא ישתנה.'),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: start,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'התחלה (שניות)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: end,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'סיום (שניות)'),
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('הפחתת רעשי רקע'),
                  value: reduceNoise,
                  onChanged: (value) => setDialogState(() => reduceNoise = value),
                ),
                if (reduceNoise) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('עוצמת ההפחתה: ${strength.round()} dB'),
                  ),
                  Slider(
                    min: 0,
                    max: 30,
                    divisions: 30,
                    value: strength,
                    label: '${strength.round()} dB',
                    onChanged: (value) => setDialogState(() => strength = value),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ביטול'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded),
              onPressed: () => Navigator.pop(dialogContext, {
                'start': double.tryParse(start.text.trim()),
                'end': double.tryParse(end.text.trim()),
                'reduceNoise': reduceNoise,
                'strength': strength,
              }),
              label: const Text('עבד ושמור'),
            ),
          ],
        ),
      ),
    );
    start.dispose();
    end.dispose();
    if (options == null || !mounted) return;

    final startSeconds = options['start'] as double?;
    final endSeconds = options['end'] as double?;
    if (startSeconds == null || endSeconds == null ||
        startSeconds < 0 || endSeconds <= startSeconds) {
      snack(context, 'יש להזין טווח זמן תקין');
      return;
    }

    if (kIsWeb && l.fileSize != null && l.fileSize! > 80 * 1024 * 1024) {
      snack(context, 'בדפדפן אפשר לעבד קבצים עד 80 MB.');
      return;
    }

    setState(() {
      busy = true;
      status = 'מוריד ומעבד את ההקלטה...';
    });
    try {
      final sourceBytes = await fetchMediaBytes(l);
      final output = await AudioProcessingService.exportM4a(
        sourceBytes: sourceBytes,
        sourceName: originalDownloadName(l, fallbackTitle: l.title),
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        reduceNoise: options['reduceNoise'] as bool,
        noiseReductionDb: options['strength'] as double,
      );
      final safeTitle = l.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final name = '${safeTitle}_קטע_נקי.m4a';
      await shareBytes(output, name, 'audio/mp4');
      if (mounted) snack(context, 'הקובץ המעובד מוכן לשמירה או לשיתוף');
    } catch (error) {
      if (mounted) snack(context, 'עיבוד השמע נכשל: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> transcribe() async {
    if (!l.hasMedia) {
      snack(context, 'יש להעלות קודם הקלטה לשיעור');
      return;
    }
    if (!Transcriber.ready) {
      snack(context, 'יש להשלים את הגדרות התמלול');
      go(context, const SettingsScreen(standalone: true));
      return;
    }
    if (l.transcript.isNotEmpty &&
        !await confirm(context, 'להחליף את התמלול הקיים בתמלול חדש?',
            ok: 'החלפה')) return;
    setState(() {
      busy = true;
      status = 'מתחיל...';
    });
    try {
      final segs = await Transcriber.transcribe(l, onStatus: (s) {
        if (mounted) setState(() => status = s);
      });
      preserveMainTranscript(l);
      addTranscriptVersion(l, Transcriber.providerId, segs);
      l.transcript = [for (final x in segs) Seg(x.ms, x.text)];
      app.save();
      if (mounted)
        snack(context, 'התמלול הסתיים – לחיצה על שורה קופצת לרגע הזה בהקלטה');
    } catch (e) {
      if (mounted)
        snack(context,
            'התמלול נכשל: ${e.toString().replaceFirst('Exception: ', '')}');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> alignTextWithAI() async {
    if (l.transcript.isEmpty) {
      snack(context, 'יש ליצור תמלול לפני התאמת AI');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['txt'], withData: true);
    if (result == null ||
        result.files.isEmpty ||
        result.files.first.bytes == null) return;
    setState(() {
      busy = true;
      status = 'AI מתאים את הטקסט לזמנים...';
    });
    try {
      final text = decodeTextBytes(result.files.first.bytes!);
      final aligned = await Transcriber.alignTextWithAI(text, l.transcript);
      if (aligned.isEmpty) throw Exception('לא התקבלו שורות מה-AI');
      l.transcript = aligned;
      app.save();
      if (mounted) snack(context, 'הטקסט הותאם לזמנים באמצעות AI');
    } catch (e) {
      if (mounted)
        snack(context,
            'התאמת AI נכשלה: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importSubtitleFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'lrc'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      snack(context, 'לא ניתן לקרוא את קובץ הכתוביות');
      return;
    }
    if (l.transcript.isNotEmpty &&
        !await confirm(context, 'להחליף את הכתוביות הקיימות?', ok: 'החלפה'))
      return;
    setState(() {
      busy = true;
      status = 'טוען כתוביות...';
    });
    try {
      final cues = parseSubtitles(decodeTextBytes(bytes));
      final segments = [
        for (final cue in cues)
          if (cue.text.trim().isNotEmpty) Seg(cue.start, cue.text)
      ];
      if (segments.isEmpty) throw Exception('לא נמצאו כתוביות מתוזמנות בקובץ');
      preserveMainTranscript(l);
      addTranscriptVersion(l, 'subtitle-file', segments);
      l.transcript = segments;
      app.save();
      if (mounted)
        snack(context,
            'נטענו ${segments.length} שורות כתוביות מתוך ${file.name}');
    } catch (error) {
      if (mounted) snack(context, 'טעינת הכתוביות נכשלה: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> alignTextByTime() async {
    if (l.transcript.isEmpty) {
      snack(context, 'יש ליצור תמלול לפני סידור הטקסט – הזמנים נלקחים מהתמלול');
      return;
    }
    final text = await askTextForAlignment(context);
    if (text == null || !mounted) return;
    final aligned = TextAligner.align(
      text,
      l.transcript,
    );
    if (aligned.isEmpty) return;
    l.transcript = aligned;
    changed();
    snack(context,
        'הטקסט סודר לפי הזמנים בלי לשנות אף אות (${aligned.length} שורות)');
  }

  Future<void> editAsText() async {
    final ctl =
        TextEditingController(text: l.transcript.map((s) => s.text).join('\n'));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('עריכת התמלול'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctl,
            maxLines: 16,
            minLines: 8,
            decoration: const InputDecoration(
                hintText: 'שורה לכל קטע. אפשר גם להדביק תמלול מוכן.'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('שמירה')),
        ],
      ),
    );
    ctl.dispose();
    if (res == null) return;
    final rows = res
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // שומרים את הזמנים הקיימים לפי סדר השורות
    final old = l.transcript;
    l.transcript = [
      for (var i = 0; i < rows.length; i++)
        Seg(i < old.length ? old[i].ms : (old.isEmpty ? 0 : old.last.ms),
            rows[i]),
    ];
    changed();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final c = Theme.of(context).colorScheme;
          return DefaultTabController(
            initialIndex: widget.initialTab <= 0
                ? 0
                : (widget.initialTab + 1).clamp(1, 5).toInt(),
            length: 6,
            child: Scaffold(
              appBar: AppBar(
                title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(lessonMeta(l),
                          style: TextStyle(
                              fontSize: 12, color: c.onSurfaceVariant)),
                    ]),
                actions: [
                  IconButton(
                    tooltip: l.fav ? 'הסרה ממועדפים' : 'הוספה למועדפים',
                    icon: Icon(
                        l.fav ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: l.fav ? const Color(0xFFF2A541) : null),
                    onPressed: () {
                      l.fav = !l.fav;
                      app.save();
                    },
                  ),
                  IconButton(
                      icon: const Icon(Icons.ios_share_rounded),
                      tooltip: 'ייצוא ושיתוף',
                      onPressed: () => exportLessonMenu(context, l)),
                  IconButton(
                    tooltip: 'יצירת קטע חדש מתוך השיעור',
                    icon: const Icon(Icons.content_cut_rounded),
                    onPressed: _createClip,
                  ),
                  IconButton(
                    tooltip: 'חיתוך והפחתת רעשי רקע לקובץ',
                    icon: const Icon(Icons.graphic_eq_rounded),
                    onPressed: busy ? null : _exportProcessedAudio,
                  ),
                  IconButton(
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: () => go(context, LessonForm(lesson: l))),
                ],
                bottom: TabBar(
                  dividerColor: Colors.transparent,
                  isScrollable: true,
                  tabs: const [
                    Tab(icon: Icon(Icons.headphones_rounded), text: 'האזנה'),
                    Tab(text: 'סימניות'),
                    Tab(text: 'תמלול'),
                    Tab(text: 'סיכום'),
                    Tab(text: 'נקודות'),
                    Tab(text: 'כתוביות רצות'),
                  ],
                ),
              ),
              body: Column(children: [
                Expanded(
                  child: TabBarView(children: [
                    _ListeningTab(lesson: l, track: track),
                    SegList(l.marks, track, 'סימנייה בנקודה הנוכחית', changed,
                        emptyText: 'הוסף סימניות לרגעים חשובים'),
                    SegList(
                      l.transcript,
                      track,
                      'הוספת שורת תמלול',
                      changed,
                      emptyText:
                          busy ? '' : 'עדיין אין תמלול – לחץ "תמלול אוטומטי"',
                      header: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                        child: Column(children: [
                          Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 4,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 44)),
                                    icon: busy
                                        ? SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: c.onPrimary),
                                          )
                                        : const Icon(
                                            Icons.auto_awesome_rounded),
                                    label: Text(
                                        busy ? 'מתמלל...' : 'תמלול אוטומטי'),
                                    onPressed: busy ? null : transcribe,
                                  ),
                                ),
                                IconButton.filledTonal(
                                    tooltip: 'תמלולים מכמה מנועים והשוואה',
                                    icon: Badge(
                                      isLabelVisible: l.transcripts.length > 1,
                                      label: Text('${l.transcripts.length}'),
                                      child: const Icon(
                                          Icons.compare_arrows_rounded),
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () =>
                                            go(context, TranscriptsScreen(l))),
                                IconButton.filledTonal(
                                    tooltip: 'מצב עריכת כתוביות (מקלדת)',
                                    icon: const Icon(Icons.keyboard_rounded),
                                    onPressed: busy || l.transcript.isEmpty
                                        ? null
                                        : () async {
                                            await go(context,
                                                SubtitleEditorScreen(l));
                                            if (mounted) setState(() {});
                                          }),
                                IconButton.filledTonal(
                                    tooltip:
                                        'ייצוא כתוביות (TXT / SRT / VTT / LRC)',
                                    icon: const Icon(
                                        Icons.closed_caption_rounded),
                                    onPressed: l.transcript.isEmpty
                                        ? null
                                        : () => exportSubtitlesMenu(
                                            context, l.transcript, l.title)),
                                IconButton.filledTonal(
                                  tooltip:
                                      'העלאת קובץ כתוביות (SRT / VTT / LRC)',
                                  icon: const Icon(Icons.file_open_rounded),
                                  onPressed: busy ? null : importSubtitleFile,
                                ),
                                IconButton.filledTonal(
                                    tooltip: 'עריכה כטקסט',
                                    icon: const Icon(Icons.edit_note_rounded),
                                    onPressed: busy ? null : editAsText),
                                IconButton.filledTonal(
                                  tooltip: 'העלאת טקסט וסידור לפי זמנים',
                                  icon: const Icon(Icons.schedule_rounded),
                                  onPressed: busy ? null : alignTextByTime,
                                ),
                                IconButton.filledTonal(
                                  tooltip: 'התאמת טקסט לזמנים באמצעות AI',
                                  icon: const Icon(Icons.auto_awesome_rounded),
                                  onPressed: busy ? null : alignTextWithAI,
                                ),
                                IconButton.filledTonal(
                                  tooltip: 'העתקה',
                                  icon: const Icon(Icons.copy_rounded),
                                  onPressed: l.transcript.isEmpty
                                      ? null
                                      : () {
                                          Clipboard.setData(ClipboardData(
                                              text: l.transcript
                                                  .map((e) => e.text)
                                                  .join('\n')));
                                          snack(context, 'התמלול הועתק');
                                        },
                                ),
                              ]),
                          if (busy)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(children: [
                                const LinearProgressIndicator(),
                                const SizedBox(height: 6),
                                Text(status,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ]),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('מנוע: ${Transcriber.provider.label}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: c.onSurfaceVariant)),
                            ),
                        ]),
                      ),
                    ),
                    Column(children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextField(
                            controller: summary,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                                hintText: 'סיכום השיעור...'),
                            onChanged: (v) {
                              l.summary = v;
                              app.save(notify: false);
                            },
                          ),
                        ),
                      ),
                    ]),
                    _PointsTab(lesson: l),
                    l.transcript.isEmpty
                        ? Center(
                            child: Text('אין עדיין כתוביות – צור תמלול',
                                style: TextStyle(color: c.onSurfaceVariant)))
                        : LiveSubtitles(segs: l.transcript, track: track),
                  ]),
                ),
                const Divider(),
                SafeArea(top: false, child: PlayerControls(track)),
              ]),
            ),
          );
        },
      );
}

/// לשונית הנקודות בדף השיעור: חיפוש, רשימה, גרירה לשינוי סדר, לחיצה פותחת חלון נקודה.
class _PointsTab extends StatefulWidget {
  final Lesson lesson;
  const _PointsTab({required this.lesson});
  @override
  State<_PointsTab> createState() => _PointsTabState();
}

class _PointsTabState extends State<_PointsTab> {
  String q = '';
  Lesson get l => widget.lesson;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final query = q.trim().toLowerCase();
    final visible = [
      for (var i = 0; i < l.pointCount; i++)
        if (query.isEmpty ||
            l.pointTitle(i).toLowerCase().contains(query) ||
            l.pointNote(i).toLowerCase().contains(query))
          i
    ];
    Widget tile(int i) => ListTile(
          key: ValueKey(
              'pt_${i}_${l.pointStart(i)}_${l.pointTitle(i).hashCode}'),
          onTap: () => showPointDialog(context, l, i),
          leading: CircleAvatar(
            radius: 13,
            backgroundColor: c.primaryContainer,
            child: Text('${i + 1}',
                style: TextStyle(fontSize: 12, color: c.onPrimaryContainer)),
          ),
          title: Text(l.pointTitle(i),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (l.pointCat(i).isNotEmpty || l.pointSub(i).isNotEmpty)
              Text(
                  [l.pointCat(i), l.pointSub(i)]
                      .where((e) => e.isNotEmpty)
                      .join(' › '),
                  style: TextStyle(
                      color: c.tertiary, fontWeight: FontWeight.w600)),
            Text(
                '${fmt(Duration(milliseconds: l.pointStart(i)))} – ${fmt(Duration(milliseconds: l.pointEnd(i)))}',
                style: TextStyle(color: c.primary)),
            if (l.pointNote(i).isNotEmpty)
              Text(l.pointNote(i),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
          trailing: IconButton(
            tooltip: 'הפעל קטע',
            icon: const Icon(Icons.play_circle_outline_rounded),
            onPressed: () => player.playSegment(
                Track.lesson(l), l.pointStart(i), l.pointEnd(i)),
          ),
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'חיפוש בנקודות'),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          const SizedBox(width: 10),
          Text('${l.pointCount} נקודות',
              style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
          IconButton(
            tooltip: 'מיון, נושאים והדפסה',
            icon: const Icon(Icons.print_rounded),
            onPressed: l.pointCount == 0
                ? null
                : () => go(context, PointsScreen(only: l)),
          ),
        ]),
      ),
      Expanded(
        child: l.pointCount == 0
            ? Center(
                child: Text('אין עדיין נקודות',
                    style: TextStyle(color: c.onSurfaceVariant)))
            : query.isNotEmpty
                ? (visible.isEmpty
                    ? Center(
                        child: Text('לא נמצאו נקודות',
                            style: TextStyle(color: c.onSurfaceVariant)))
                    : ListView(
                        padding: const EdgeInsets.all(8),
                        children: [for (final i in visible) tile(i)]))
                : ReorderableListView(
                    padding: const EdgeInsets.all(8),
                    onReorder: (a, b) {
                      if (b > a) b--;
                      l.movePoint(a, b);
                      app.save();
                    },
                    children: [for (var i = 0; i < l.pointCount; i++) tile(i)],
                  ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 46)),
          icon: const Icon(Icons.add_rounded),
          label: Text(player.isCurrent(l.id)
              ? 'הוסף נקודה מהשנייה הנוכחית'
              : 'הוסף נקודה'),
          onPressed: () => showAddPointDialog(context, l),
        ),
      ),
    ]);
  }
}

class _ListeningTab extends StatelessWidget {
  final Lesson lesson;
  final Track track;

  const _ListeningTab({required this.lesson, required this.track});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final events = <({int ms, String title, String detail, IconData icon, int? pointIndex})>[
      for (var i = 0; i < lesson.pointCount; i++)
        (
          ms: lesson.pointStart(i),
          title: lesson.pointTitle(i),
          detail: lesson.pointNote(i),
          icon: Icons.push_pin_rounded,
          pointIndex: i,
        ),
      for (final mark in lesson.marks)
        (
          ms: mark.ms,
          title: mark.text,
          detail: 'סימנייה',
          icon: Icons.bookmark_rounded,
          pointIndex: null,
        ),
    ]..sort((a, b) => a.ms.compareTo(b.ms));

    return Column(children: [
      Expanded(
        flex: 3,
        child: lesson.transcript.isEmpty
            ? Center(
                child: Text('אין עדיין כתוביות לשיעור',
                    style: TextStyle(color: c.onSurfaceVariant)))
            : LiveSubtitles(segs: lesson.transcript, track: track),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 4),
        child: Row(children: [
          Expanded(
              child: Text('נקודות וסימניות לפי זמן',
                  style: Theme.of(context).textTheme.titleMedium)),
          Text('${events.length}', style: TextStyle(color: c.onSurfaceVariant)),
          IconButton(
            tooltip: 'הוסף נקודה',
            onPressed: () => showAddPointDialog(context, lesson),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ]),
      ),
      Expanded(
        flex: 2,
        child: events.isEmpty
            ? Center(
                child: Text('נקודות וסימניות שתוסיף יופיעו כאן',
                    style: TextStyle(color: c.onSurfaceVariant)))
            : ListView.builder(
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final item = events[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(item.icon, color: c.primary),
                    title: Text(item.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${fmt(Duration(milliseconds: item.ms))}${item.detail.isEmpty ? '' : ' · ${item.detail}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    onTap: () {
                      final pointIndex = item.pointIndex;
                      if (pointIndex != null) {
                        showPointDialog(context, lesson, pointIndex);
                      } else {
                        player.seekTo(track, item.ms);
                      }
                    },
                  );
                },
              ),
      ),
    ]);
  }
}
