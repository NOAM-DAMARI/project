import '../services/file_service.dart';
import '../services/media_upload.dart';
import '../models/song.dart';
import '../services/app_state.dart';
import '../utils/helpers.dart';
import '../widgets/hebrew_date_picker.dart';
import 'package:flutter/material.dart';
import 'singer_form.dart';

class SongForm extends StatefulWidget {
  final Song? song;
  final String? initialSingerId;
  const SongForm({super.key, this.song, this.initialSingerId});
  @override
  State<SongForm> createState() => _SongFormState();
}

class _SongFormState extends State<SongForm> {
  late final title = TextEditingController(text: widget.song?.title);
  late final year = TextEditingController(text: widget.song?.year?.toString());
  late final dur = TextEditingController(text: widget.song?.duration);
  late final notes = TextEditingController(text: widget.song?.notes);
  late final lyrics = TextEditingController(text: widget.song?.lyrics);
  late final location = TextEditingController(text: widget.song?.location);
  late DateTime eventDate = widget.song?.eventDate ?? DateTime.now();
  String? singerId;
  PickedMedia? picked;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    singerId = widget.song?.singerId ?? widget.initialSingerId;
    if (singerId != null && app.singer(singerId!) == null) singerId = null;
  }

  @override
  void dispose() {
    for (final c in [title, year, dur, notes, lyrics, location]) {
      c.dispose();
    }
    super.dispose();
  }

  /// מזהה הזמר רק אם הוא באמת קיים ברשימה (אחרת Dropdown זורק שגיאת assertion)
  String? _validSingerId() {
    final id = singerId;
    if (id == null) return null;
    return app.singers.any((s) => s.id == id) ? id : null;
  }

  /// פריטי הרשימה ללא כפילויות מזהה
  List<DropdownMenuItem<String>> _singerItems() {
    final seen = <String>{};
    return [
      for (final s in app.singers)
        if (seen.add(s.id)) DropdownMenuItem(value: s.id, child: Text(s.name)),
    ];
  }

  Future<void> pickFile() async {
    final f = await pickAudio();
    if (f == null) return;
    setState(() => picked = f);
    final d = await probeDuration(f);
    if (d != null && mounted) setState(() => dur.text = formatDuration(d));
  }

  Future<void> pickFreeFile() async {
    final file = await pickFreeMedia(context);
    if (file == null || !mounted) return;
    setState(() => picked = file);
    final duration = await probeDuration(file);
    if (duration != null && mounted)
      setState(() => dur.text = formatDuration(duration));
  }

  Future<void> submit() async {
    if (title.text.trim().isEmpty || singerId == null) {
      snack(context, 'יש להזין שם שיר ולבחור זמר');
      return;
    }
    setState(() => saving = true);

    final isNew = widget.song == null;
    final s =
        widget.song ?? Song(id: app.newId(), title: '', singerId: singerId!);
    s
      ..title = title.text.trim()
      ..singerId = singerId!
      ..year = int.tryParse(year.text)
      ..duration = dur.text.trim()
      ..notes = notes.text
      ..eventDate = eventDate
      ..location = location.text.trim()
      ..stamps = (s.lyrics == lyrics.text ? s.stamps : <int>[])
      ..lyrics = lyrics.text;

    if (picked != null) {
      final ok = await attachMedia(context, s, picked!, folder: 'songs');
      if (!ok) {
        if (mounted) setState(() => saving = false);
        return;
      }
    }
    if (isNew) app.songs.add(s);
    app.save();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final c = Theme.of(context).colorScheme;
          final currentName = picked?.name ?? widget.song?.fileName;
          final currentSize = picked?.size ?? widget.song?.fileSize;
          return Scaffold(
            appBar: AppBar(
                title: Text(widget.song == null ? 'שיר חדש' : 'עריכת שיר'),
                actions: [
                  if (widget.song != null)
                    IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          if (await confirm(context, 'למחוק את השיר?')) {
                            app.deleteSong(widget.song!);
                            if (context.mounted) {
                              Navigator.pop(context);
                              Navigator.pop(context);
                            }
                          }
                        }),
                ]),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(
                      labelText: 'שם השיר',
                      prefixIcon: Icon(Icons.music_note_rounded))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('singer-${singerId ?? ''}-${app.singers.length}'),
                    initialValue: _validSingerId(),
                    decoration: const InputDecoration(
                        labelText: 'זמר', prefixIcon: Icon(Icons.mic_rounded)),
                    items: _singerItems(),
                    onChanged: (v) => setState(() => singerId = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'זמר חדש',
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  onPressed: () async {
                    final before = app.singers.length;
                    await go(context, const SingerForm());
                    if (app.singers.length > before)
                      setState(() => singerId = app.singers.last.id);
                  },
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: year,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'שנה'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: dur,
                        decoration: const InputDecoration(
                            labelText: 'משך', hintText: 'מזוהה אוטומטית'))),
              ]),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(Icons.event_rounded, color: c.primary),
                  title: Text(fmtDate(eventDate)),
                  subtitle: Text(hebrewDate(eventDate)),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: () async {
                    final d = await pickAnyDate(context, eventDate);
                    if (d != null) setState(() => eventDate = d);
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: location,
                  decoration: const InputDecoration(
                      labelText: 'מקום האירוע',
                      prefixIcon: Icon(Icons.place_outlined))),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(
                      currentName == null
                          ? Icons.upload_file_rounded
                          : Icons.audio_file_rounded,
                      color: c.primary),
                  title: Text(currentName ?? 'העלאת קובץ שמע'),
                  subtitle: Text(currentName == null
                      ? 'MP3, M4A, WAV ועוד · עד 2GB'
                      : [
                          fmtBytes(currentSize),
                          if (picked != null) 'יועלה בשמירה'
                        ].where((e) => e.isNotEmpty).join(' · ')),
                  trailing: TextButton(
                      onPressed: saving ? null : pickFile,
                      child: Text(currentName == null ? 'בחירה' : 'החלפה')),
                  onTap: saving ? null : pickFile,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: saving ? null : pickFreeFile,
                icon: const Icon(Icons.folder_special_rounded),
                label: const Text('בחר קובץ לא משויך מהמאגר'),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: lyrics,
                  maxLines: 10,
                  minLines: 5,
                  decoration: const InputDecoration(
                      labelText: 'מילים', alignLabelWithHint: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'הערות', alignLabelWithHint: true)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: saving ? null : submit,
                child: Text(saving ? 'שומר...' : 'שמירה'),
              ),
            ]),
          );
        },
      );
}
