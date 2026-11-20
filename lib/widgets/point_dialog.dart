import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../screens/lesson_page.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../services/points.dart';
import '../utils/helpers.dart';

/// בחירת נושא ותת-נושא לנקודה
class PointCategoryFields extends StatelessWidget {
  final String cat, sub;
  final void Function(String cat, String sub) onChanged;
  const PointCategoryFields({super.key, required this.cat, required this.sub, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in pointCategories)
            ChoiceChip(
              label: Text(k),
              selected: cat == k,
              onSelected: (v) => onChanged(v ? k : '', sub),
            ),
        ]),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: sub,
          decoration: const InputDecoration(labelText: 'תת-נושא', hintText: 'למשל: שבת, תפילה, כשרות…', isDense: true),
          onChanged: (v) => onChanged(cat, v.trim()),
        ),
      ]);
}

String _clock(int ms) => fmt(Duration(milliseconds: ms < 0 ? 0 : ms));

/// חלון פרטי נקודה: צפייה, עריכה ישירה, הפעלת קטע, מחיקה ומעבר לשיעור.
/// לחיצה על נקודה בכל מקום באפליקציה פותחת את החלון הזה (ולא מעבירה ישר לשיעור).
Future<void> showPointDialog(BuildContext context, Lesson lesson, int index, {bool startEditing = false}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PointDialog(lesson: lesson, index: index, startEditing: startEditing),
  );
}

class _PointDialog extends StatefulWidget {
  final Lesson lesson;
  final int index;
  final bool startEditing;
  const _PointDialog({required this.lesson, required this.index, required this.startEditing});
  @override
  State<_PointDialog> createState() => _PointDialogState();
}

class _PointDialogState extends State<_PointDialog> {
  Lesson get l => widget.lesson;
  int get i => widget.index;
  late bool editing = widget.startEditing;
  late final title = TextEditingController(text: l.pointTitle(i));
  late final note = TextEditingController(text: l.pointNote(i));
  late final start = TextEditingController(text: _clock(l.pointStart(i)));
  late final end = TextEditingController(text: _clock(l.pointEnd(i)));
  late String cat = l.pointCat(i), sub = l.pointSub(i);
  String? error;

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    start.dispose();
    end.dispose();
    super.dispose();
  }

  bool _save() {
    final s = parseClock(start.text), e = parseClock(end.text);
    if (s == null || e == null || e <= s) {
      setState(() => error = 'זמנים לא תקינים: יש להזין 00:00, והסיום חייב להיות אחרי ההתחלה');
      return false;
    }
    l.updatePoint(i,
        title: title.text.trim().isEmpty ? 'נקודה' : title.text.trim(),
        note: note.text.trim(),
        startMs: s,
        endMs: e,
        cat: cat,
        sub: sub);
    app.save();
    setState(() {
      error = null;
      editing = false;
    });
    return true;
  }

  Future<void> _play() async {
    final s = editing ? (parseClock(start.text) ?? l.pointStart(i)) : l.pointStart(i);
    final e = editing ? (parseClock(end.text) ?? l.pointEnd(i)) : l.pointEnd(i);
    if (!l.hasMedia) {
      snack(context, 'לשיעור הזה אין הקלטה');
      return;
    }
    await player.playSegment(Track.lesson(l), s, e);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'למחוק את הנקודה "${l.pointTitle(i)}"?')) return;
    l.removePoint(i);
    app.save();
    if (mounted) Navigator.pop(context);
  }

  void _goToLesson() {
    final nav = Navigator.of(context);
    final ms = l.pointStart(i);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => LessonPage(l, initialTab: 4)));
    if (l.hasMedia) player.seekTo(Track.lesson(l), ms);
  }

  @override
  Widget build(BuildContext context) {
    if (i >= l.pointCount) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    final text = l.pointTranscript(i);
    final size = MediaQuery.of(context).size;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      title: Row(children: [
        Expanded(
          child: editing
              ? const Text('עריכת נקודה')
              : Text(l.pointTitle(i), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        IconButton(tooltip: 'סגור', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
      ]),
      content: SizedBox(
        width: size.width > 640 ? 560 : size.width,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(l.title, style: TextStyle(color: c.onSurfaceVariant, fontSize: 12)),
            if (!editing && (l.pointCat(i).isNotEmpty || l.pointSub(i).isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text([l.pointCat(i), l.pointSub(i)].where((e) => e.isNotEmpty).join(' › '),
                    style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 8),
            if (editing) ...[
              TextField(controller: title, decoration: const InputDecoration(labelText: 'כותרת')),
              const SizedBox(height: 10),
              TextField(
                  controller: note,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'פירוט', alignLabelWithHint: true)),
              const SizedBox(height: 10),
              PointCategoryFields(cat: cat, sub: sub, onChanged: (a, b) => setState(() {
                    cat = a;
                    sub = b;
                  })),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: start,
                        keyboardType: TextInputType.datetime,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: 'התחלה',
                          hintText: '00:00',
                          suffixIcon: IconButton(
                            tooltip: 'הזמן הנוכחי בנגן',
                            icon: const Icon(Icons.my_location_rounded, size: 18),
                            onPressed: () => start.text = _clock(player.p.position.inMilliseconds),
                          ),
                        ))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: end,
                        keyboardType: TextInputType.datetime,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: 'סיום',
                          hintText: '05:00',
                          suffixIcon: IconButton(
                            tooltip: 'הזמן הנוכחי בנגן',
                            icon: const Icon(Icons.my_location_rounded, size: 18),
                            onPressed: () => end.text = _clock(player.p.position.inMilliseconds),
                          ),
                        ))),
              ]),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: TextStyle(color: c.error)),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Text('טווח בשיעור: ${_clock(l.pointStart(i))} – ${_clock(l.pointEnd(i))}',
                    style: TextStyle(color: c.onPrimaryContainer, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              Text('פירוט', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(l.pointNote(i).isEmpty ? 'אין פירוט לנקודה' : l.pointNote(i)),
            ],
            const SizedBox(height: 14),
            Text('טקסט מהשיעור בטווח הזה', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(text.isEmpty ? 'אין תמלול בטווח הזה' : text,
                    style: TextStyle(color: text.isEmpty ? c.onSurfaceVariant : null, height: 1.5)),
              ),
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: player,
              builder: (_, __) => player.segmentEndMs != null && player.isCurrent(l.id)
                  ? Row(children: [
                      const Icon(Icons.graphic_eq_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('הקטע מתנגן – אפשר להמשיך לערוך')),
                      TextButton(
                          onPressed: () {
                            player.p.pause();
                            player.cancelSegment();
                          },
                          child: const Text('עצור')),
                    ])
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        Wrap(alignment: WrapAlignment.end, spacing: 4, runSpacing: 4, children: [
          FilledButton.tonalIcon(
              icon: const Icon(Icons.play_arrow_rounded), label: const Text('הפעל קטע'), onPressed: _play),
          if (editing) ...[
            FilledButton.icon(icon: const Icon(Icons.check_rounded), label: const Text('שמור'), onPressed: _save),
            TextButton(
                onPressed: () => setState(() {
                      editing = false;
                      error = null;
                      title.text = l.pointTitle(i);
                      note.text = l.pointNote(i);
                      start.text = _clock(l.pointStart(i));
                      end.text = _clock(l.pointEnd(i));
                    }),
                child: const Text('ביטול')),
          ] else
            OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('ערוך'),
                onPressed: () => setState(() => editing = true)),
          OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new_rounded), label: const Text('עבור לשיעור'), onPressed: _goToLesson),
          TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: c.error),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('מחק'),
              onPressed: _delete),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('סגור')),
        ]),
      ],
    );
  }
}

/// חלון הוספת נקודה במרכז המסך. ההתחלה נקבעת לפי השנייה הנוכחית בנגן,
/// "עצור" סוגר את הטווח בזמן אמת, ואפשר להמשיך לכתוב גם אחרי זה.
/// הנקודה נשמרת מיד עם פתיחת החלון, כך ששום דבר לא הולך לאיבוד.
Future<void> showAddPointDialog(BuildContext context, Lesson lesson) {
  final live = player.isCurrent(lesson.id);
  final startMs = live ? player.p.position.inMilliseconds : 0;
  final index = lesson.addPoint(title: 'נקודה חדשה', startMs: startMs);
  app.save();
  app.livePointLessonId = lesson.id;
  app.livePointIndex = index;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddPointDialog(lesson: lesson, index: index, live: live),
  ).whenComplete(() {
    if (app.livePointLessonId == lesson.id && app.livePointIndex == index && (!live || lesson.pointHasEnd(index))) {
      app.livePointLessonId = null;
      app.livePointIndex = null;
    }
  });
}

/// סגירת טווח של נקודה פתוחה מתוך הנגן (בלי לפתוח חלון)
void stopLivePoint(Lesson lesson) {
  final i = app.livePointIndex;
  if (app.livePointLessonId != lesson.id || i == null || i >= lesson.pointCount) return;
  final now = player.p.position.inMilliseconds;
  lesson.updatePoint(i, endMs: now > lesson.pointStart(i) ? now : lesson.pointStart(i) + 1000);
  app.livePointLessonId = null;
  app.livePointIndex = null;
  app.save();
}

class _AddPointDialog extends StatefulWidget {
  final Lesson lesson;
  final int index;
  final bool live;
  const _AddPointDialog({required this.lesson, required this.index, required this.live});
  @override
  State<_AddPointDialog> createState() => _AddPointDialogState();
}

class _AddPointDialogState extends State<_AddPointDialog> {
  Lesson get l => widget.lesson;
  int get i => widget.index;
  final title = TextEditingController();
  final note = TextEditingController();
  late final start = TextEditingController(text: _clock(l.pointStart(i)));
  final end = TextEditingController();
  String cat = '', sub = '';
  bool stopped = false;

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    start.dispose();
    end.dispose();
    super.dispose();
  }

  void _stop() {
    final now = player.p.position.inMilliseconds;
    final s = parseClock(start.text) ?? l.pointStart(i);
    end.text = _clock(now > s ? now : s + 1000);
    setState(() => stopped = true);
    _persist();
  }

  void _persist() {
    final s = parseClock(start.text);
    final e = parseClock(end.text);
    l.updatePoint(i,
        title: title.text.trim().isEmpty ? 'נקודה חדשה' : title.text.trim(),
        note: note.text.trim(),
        startMs: s,
        endMs: (e != null && s != null && e > s) ? e : null,
        cat: cat,
        sub: sub);
    app.save();
  }

  void _close() {
    _persist();
    if (l.pointHasEnd(i) && app.livePointIndex == i) {
      app.livePointLessonId = null;
      app.livePointIndex = null;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('הוספת נקודה'),
      content: SizedBox(
        width: size.width > 640 ? 520 : size.width,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.live)
              StreamBuilder<Duration>(
                stream: player.p.positionStream,
                builder: (_, snap) => Text(
                  stopped ? 'הטווח נסגר' : 'מקליט טווח… עכשיו: ${_clock(snap.data?.inMilliseconds ?? 0)}',
                  style: TextStyle(color: stopped ? c.onSurfaceVariant : c.primary, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'כותרת', hintText: 'נקודה חדשה')),
            const SizedBox(height: 10),
            TextField(
                controller: note,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'פירוט', alignLabelWithHint: true)),
            const SizedBox(height: 10),
            PointCategoryFields(cat: cat, sub: sub, onChanged: (a, b) => setState(() {
                  cat = a;
                  sub = b;
                })),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: start,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(labelText: 'התחלה', hintText: '00:00'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: end,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(labelText: 'סיום', hintText: 'לחץ "עצור"'))),
            ]),
          ]),
        ),
      ),
      actions: [
        if (widget.live)
          FilledButton.icon(
            icon: Icon(stopped ? Icons.check_rounded : Icons.stop_circle_outlined),
            label: Text(stopped ? 'הטווח נסגר' : 'עצור'),
            onPressed: stopped ? null : _stop,
          ),
        TextButton(onPressed: _close, child: const Text('סגור')),
      ],
    );
  }
}
