import '../services/file_service.dart';
import '../services/media_upload.dart';
import '../services/zip_import_flow.dart';
import '../models/lesson.dart';
import '../services/app_state.dart';
import '../utils/helpers.dart';
import '../widgets/hebrew_date_picker.dart';
import '../widgets/parasha_picker.dart';
import 'zip_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LessonForm extends StatefulWidget {
  final Lesson? lesson;
  const LessonForm({super.key, this.lesson});
  @override
  State<LessonForm> createState() => _LessonFormState();
}

class _LessonFormState extends State<LessonForm> {
  late final title = TextEditingController(text: widget.lesson?.title);
  late final notes = TextEditingController(text: widget.lesson?.notes);
  late final number =
      TextEditingController(text: widget.lesson?.number?.toString() ?? '');
  late DateTime date = widget.lesson?.date ?? DateTime.now();
  late String dateKind = widget.lesson?.dateKind ?? 'g';
  late String parasha = widget.lesson?.parasha ?? '';
  late bool parashaIsEvent = widget.lesson?.parashaKind == 'event';
  PickedMedia? picked;
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    number.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (title.text.trim().isEmpty) {
      snack(context, 'יש להזין שם לשיעור');
      return;
    }
    final n =
        number.text.trim().isEmpty ? null : int.tryParse(number.text.trim());
    if (number.text.trim().isNotEmpty && (n == null || n < 1 || n > 9999)) {
      snack(context, 'מספר שיעור חייב להיות בין 1 ל-9999 (עד 4 ספרות)');
      return;
    }
    setState(() => saving = true);
    final isNew = widget.lesson == null;
    final l = widget.lesson ?? Lesson(id: app.newId(), title: '');
    l
      ..title = title.text.trim()
      ..notes = notes.text
      ..number = n
      ..parasha = parasha
      ..parashaKind = parashaIsEvent ? 'event' : 'weekly'
      ..dateKind = dateKind
      ..date = date;
    if (picked != null) {
      final ok = await attachMedia(context, l, picked!, folder: 'lessons');
      if (!ok) {
        if (mounted) setState(() => saving = false);
        return;
      }
      app.prefs.remove('pos_${l.id}');
    }
    if (isNew) app.lessons.add(l);
    app.save();
    if (mounted) Navigator.pop(context);
  }

  Future<void> pickFreeFile() async {
    final chosen = await pickFreeMedia(context);
    if (chosen == null || !mounted) return;
    final info = chosen.suggestedLesson ??
        app.importedInfoFor(chosen.importedMetadataKey);
    setState(() {
      picked = chosen;
      if (info != null) {
        if (widget.lesson == null || title.text.trim().isEmpty)
          title.text = info.title;
        if (widget.lesson == null || number.text.trim().isEmpty)
          number.text = info.number?.toString() ?? '';
        if (widget.lesson == null || parasha.isEmpty) {
          parasha = info.parasha;
          parashaIsEvent = info.parashaKind == 'event';
        }
      } else if (title.text.trim().isEmpty) {
        title.text = chosen.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final currentName = picked?.name ?? widget.lesson?.fileName;
    final currentSize = picked?.size ?? widget.lesson?.fileSize;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.lesson == null ? 'שיעור חדש' : 'עריכת שיעור'),
          actions: [
            if (widget.lesson != null)
              IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    if (await confirm(context, 'למחוק את השיעור?')) {
                      app.deleteLesson(widget.lesson!);
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
                labelText: 'שם השיעור',
                prefixIcon: Icon(Icons.school_rounded))),
        const SizedBox(height: 12),
        SizedBox(
          width: 180,
          child: TextField(
            controller: number,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4)
            ],
            decoration: const InputDecoration(
                labelText: 'מספר שיעור',
                hintText: 'עד 4 ספרות',
                prefixIcon: Icon(Icons.tag_rounded),
                counterText: ''),
          ),
        ),
        const SizedBox(height: 14),
        ParashaPicker(
          value: parasha,
          isEvent: parashaIsEvent,
          onChanged: (selection) => setState(() {
            parasha = selection.value;
            parashaIsEvent = selection.isEvent;
          }),
        ),
        const SizedBox(height: 12),
        // בחירת סוג התאריך – רק כאן, בטופס עריכת השיעור
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'g',
                label: Text('תאריך לועזי'),
                icon: Icon(Icons.calendar_month_rounded)),
            ButtonSegment(
                value: 'h',
                label: Text('תאריך עברי'),
                icon: Icon(Icons.auto_stories_rounded)),
          ],
          selected: {dateKind},
          onSelectionChanged: (v) => setState(() => dateKind = v.first),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.event_rounded, color: c.primary),
            title: Text(dateKind == 'h' ? hebrewDate(date) : fmtDate(date)),
            trailing: const Icon(Icons.edit_calendar_rounded),
            onTap: () async {
              final d = dateKind == 'h'
                  ? await showHebrewDatePicker(context, initial: date)
                  : await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2150));
              if (d != null) setState(() => date = d);
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
              leading: Icon(
                  currentName == null
                      ? Icons.upload_file_rounded
                      : Icons.audio_file_rounded,
                  color: c.primary),
              title: Text(currentName ?? 'העלאת הקלטה (שמע / וידאו)'),
              subtitle: Text(currentName == null
                  ? 'MP3, M4A, MP4 ועוד · עד 2GB'
                  : [fmtBytes(currentSize), if (picked != null) 'יצורף בשמירה']
                      .where((e) => e.isNotEmpty)
                      .join(' · ')),
              trailing: TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        final f = await pickAudio();
                        if (f != null) setState(() => picked = f);
                      },
                child: Text(currentName == null ? 'בחירה' : 'החלפה'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 42)),
                icon: const Icon(Icons.folder_special_rounded),
                label: const Text('בחר קובץ לא משויך מהמאגר'),
                onPressed: saving ? null : pickFreeFile,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 42)),
                icon: const Icon(Icons.folder_zip_rounded),
                label: const Text('העלאת ZIP חדש / מעודכן'),
                onPressed: saving
                    ? null
                    : () async {
                        // מתוך טופס שיעור: הקבצים נשמרים כ״לא משויך״ כדי לבחור אחד מהם לשיעור הזה
                        final count = await importZipFlow(context,
                            defaultTarget: ZipImportTarget.unassigned);
                        if (count > 0 && mounted) await pickFreeFile();
                      },
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'הערות', alignLabelWithHint: true)),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: saving ? null : submit,
            child: Text(saving ? 'שומר...' : 'שמירה')),
      ]),
    );
  }
}
