import 'playlists_screen.dart';
import '../models/song.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import '../widgets/player_controls.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'song_form.dart';
import '../services/export_service.dart';
import '../services/subtitle_formats.dart';
import '../widgets/live_subtitles.dart';

class SongPlayerPage extends StatefulWidget {
  final Song s;
  const SongPlayerPage(this.s, {super.key});
  @override
  State<SongPlayerPage> createState() => _SongPlayerState();
}

class _SongPlayerState extends State<SongPlayerPage> {
  Song get s => widget.s;
  double fontScale = 1;

  @override
  void initState() {
    super.initState();
    player.markFullScreen(s.id, true);
  }

  @override
  void dispose() {
    player.markFullScreen(s.id, false);
    super.dispose();
  }

  /// שיר עם קובץ כתוביות מתוזמן → כתוביות רצות. טקסט רגיל → מוצג כטקסט פשוט בלבד.
  bool get timed => songSegs(s).isNotEmpty;

  /// העלאת קובץ כתוביות מוכן (LRC / SRT / VTT). קובץ טקסט רגיל נשמר כמילים בלי זמנים.
  Future<void> _uploadSubtitles() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['lrc', 'srt', 'vtt', 'txt'], withData: true);
    final bytes = r?.files.firstOrNull?.bytes;
    if (bytes == null) return;
    final text = decodeTextBytes(bytes);
    final cues = looksTimed(text) ? parseSubtitles(text) : const <Cue>[];
    if (cues.isEmpty) {
      s.lyrics = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
      s.stamps = [];
      app.save();
      if (mounted) {
        setState(() {});
        snack(context, 'הקובץ אינו קובץ כתוביות מתוזמן – המילים יוצגו כטקסט פשוט');
      }
      return;
    }
    final lines = <String>[], stamps = <int>[];
    for (final c in cues) {
      for (final line in c.text.split('\n')) {
        if (line.trim().isEmpty) continue;
        lines.add(line);
        stamps.add(c.start);
      }
    }
    s.lyrics = lines.join('\n');
    s.stamps = stamps;
    app.save();
    if (mounted) {
      setState(() {});
      snack(context, 'נטען קובץ כתוביות: ${lines.length} שורות מתוזמנות');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sg = app.singer(s.singerId);
    final c = Theme.of(context).colorScheme;
    final accent = sg != null ? Color(sg.color) : c.primary;
    final segs = songSegs(s);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (sg != null) Text(sg.name, style: TextStyle(fontSize: 13, color: c.onSurfaceVariant)),
        ]),
        actions: [
          IconButton(
            tooltip: 'הקטנת כתוביות',
            icon: const Icon(Icons.remove_rounded),
            onPressed: fontScale <= .7
                ? null
                : () => setState(() => fontScale = (fontScale - .15).clamp(.7, 2.0)),
          ),
          IconButton(
            tooltip: 'הגדלת כתוביות',
            icon: const Icon(Icons.add_rounded),
            onPressed: fontScale >= 2.0
                ? null
                : () => setState(() => fontScale = (fontScale + .15).clamp(.7, 2.0)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'playlist') addToPlaylist(context, s);
              if (v == 'edit') {
                await go(context, SongForm(song: s));
                if (mounted) setState(() {});
              }
              if (v == 'subs') await _uploadSubtitles();
              if (v == 'export' && context.mounted) await exportSubtitlesMenu(context, segs, s.title);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'playlist', child: Text('הוספה לרשימת השמעה')),
              const PopupMenuItem(value: 'edit', child: Text('עריכת שיר')),
              const PopupMenuItem(value: 'subs', child: Text('העלאת קובץ כתוביות (LRC / SRT / VTT)')),
              if (segs.isNotEmpty) const PopupMenuItem(value: 'export', child: Text('ייצוא כתוביות')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: s.lyrics.trim().isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [accent, accent.withValues(alpha: .5)]),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(Icons.music_note_rounded, size: 72, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text('אין מילים לשיר הזה', style: TextStyle(color: c.onSurfaceVariant)),
                  ]),
                )
              : timed
                  // כתוביות מתוזמנות: מילים בלבד, במרכז, בלי שניות
                  ? LiveSubtitles(segs: segs, track: Track.song(s), showTimes: false, fontScale: fontScale, accent: accent)
                  // טקסט רגיל: מוצג כטקסט נקי במרכז
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      child: Text(
                        s.lyrics,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20 * fontScale, height: 1.6, fontWeight: FontWeight.w500),
                      ),
                    ),
        ),
        SafeArea(top: false, child: PlayerControls(Track.song(s))),
      ]),
    );
  }
}
