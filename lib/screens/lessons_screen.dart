import '../models/lesson.dart';
import '../services/app_state.dart';
import '../services/export_service.dart';
import '../utils/helpers.dart';
import '../widgets/lesson_tile.dart';
import '../widgets/mini_player.dart';
import '../widgets/ui.dart';
import 'lesson_form.dart';
import '../services/points.dart';
import '../widgets/point_dialog.dart';
import '../utils/parashot.dart';
import 'package:flutter/material.dart';

class LessonsScreen extends StatefulWidget {
  final String? initialQuery;
  final bool onlyFav;
  const LessonsScreen({super.key, this.initialQuery, this.onlyFav = false});
  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  late String q = widget.initialQuery ?? '';
  String sort = 'date';
  bool newestFirst = true;
  late bool onlyFav = widget.onlyFav;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final query = q.trim().toLowerCase();
          bool has(String s) => s.toLowerCase().contains(query);
          final list = app.lessons
              .where((l) => !onlyFav || l.fav)
              .where((l) =>
                  query.isEmpty ||
                  has(l.title) ||
                  has(l.parasha) ||
                  (l.number != null && l.number.toString() == query) ||
                  has(l.summary) ||
                  has(l.notes) ||
                  l.points.any(has) ||
                  l.pointNotes.any(has) ||
                  l.transcript.any((x) => has(x.text)) ||
                  l.marks.any((x) => has(x.text)))
              .toList();
          int pIdx(Lesson l) {
            final i = parashot.indexOf(l.parasha);
            return i < 0 ? 9999 : i;
          }
          list.sort((a, b) {
            final r = switch (sort) {
              'title' => a.title.compareTo(b.title),
              'number' => (a.number ?? 99999).compareTo(b.number ?? 99999),
              'parasha' => pIdx(a).compareTo(pIdx(b)) != 0 ? pIdx(a).compareTo(pIdx(b)) : a.date.compareTo(b.date),
              'added' => a.added.compareTo(b.added),
              'points' => a.pointCount.compareTo(b.pointCount),
              _ => a.date.compareTo(b.date),
            };
            // 'date' / 'added' / 'points': ברירת מחדל מהחדש/הגדול; השאר: מהקטן. לחיצה נוספת הופכת
            final descDefault = sort == 'date' || sort == 'added' || sort == 'points';
            return (descDefault == newestFirst) ? -r : r;
          });
          return Scaffold(
            appBar: AppBar(
              title: Text(onlyFav ? 'שיעורים מועדפים' : 'חיפוש ורשימת שיעורים'),
              actions: [
                // טבלת PDF: מספר – שם – תאריך עברי (לפי הסינון והמיון שמוצגים)
                IconButton(
                  tooltip: 'PDF – מספר, שם ותאריך עברי',
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  onPressed: list.isEmpty
                      ? null
                      : () => printNumberNameDate(context, lessonTableRows(list),
                          title: onlyFav ? 'שיעורים מועדפים' : 'רשימת שיעורים',
                          nameHeader: 'שם השיעור'),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
                onPressed: () => go(context, const LessonForm()), child: const Icon(Icons.add_rounded)),
            bottomNavigationBar: const WithMiniPlayer(),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchField(
                  hint: 'שם / מספר / פרשה / תמלול / סיכום / נקודות',
                  initial: q,
                  onChanged: (v) => setState(() => q = v),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  for (final e in {
                    'date': 'תאריך',
                    'number': 'מספר שיעור',
                    'parasha': 'פרשה',
                    'title': 'שם',
                    'added': 'נוסף לאחרונה',
                    'points': 'כמות נקודות',
                  }.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                          avatar: sort == e.key
                              ? Icon(newestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 16)
                              : null,
                          label: Text(e.value),
                          selected: sort == e.key,
                          onSelected: (_) => setState(() {
                                if (sort == e.key) {
                                  newestFirst = !newestFirst;
                                } else {
                                  sort = e.key;
                                  newestFirst = true;
                                }
                              })),
                    ),
                  FilterChip(
                    avatar: Icon(onlyFav ? Icons.star_rounded : Icons.star_outline_rounded, size: 18),
                    label: const Text('מועדפים'),
                    selected: onlyFav,
                    onSelected: (v) => setState(() => onlyFav = v),
                  ),
                ]),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(icon: Icons.search_off_rounded, title: query.isEmpty ? 'אין שיעורים' : 'לא נמצאו שיעורים')
                    : Builder(builder: (context) {
                        // נקודות שתואמות לחיפוש – לחיצה פותחת חלון נקודה
                        final pointHits = query.isEmpty
                            ? const <({Lesson lesson, int index})>[]
                            : [
                                for (final l in list)
                                  for (var i = 0; i < l.pointCount; i++)
                                    if (has(l.pointTitle(i)) || has(l.pointNote(i))) (lesson: l, index: i),
                              ];
                        return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 88), children: [
                          if (pointHits.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                              child: Text('נקודות שנמצאו (${pointHits.length})',
                                  style: Theme.of(context).textTheme.titleSmall),
                            ),
                            for (final h in pointHits.take(30))
                              Card(
                                child: ListTile(
                                  leading: const Icon(Icons.push_pin_outlined),
                                  title: Text(h.lesson.pointTitle(h.index), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      '${h.lesson.title} · ${fmt(Duration(milliseconds: h.lesson.pointStart(h.index)))}'
                                      '${h.lesson.pointNote(h.index).isEmpty ? '' : '\n${h.lesson.pointNote(h.index)}'}',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis),
                                  onTap: () => showPointDialog(context, h.lesson, h.index),
                                ),
                              ),
                            const Divider(),
                          ],
                          for (final l in list) LessonTile(l, hint: query.isEmpty ? null : matchHint(l, query)),
                        ]);
                      }),
              ),
            ]),
          );
        },
      );
}

/// מחזיר היכן נמצאה מילת החיפוש (לא בשם), עם קטע קצר מסביב
String? matchHint(Lesson l, String query) {
  bool has(String s) => s.toLowerCase().contains(query);
  if (has(l.title) || has(l.parasha)) return null;
  String cut(String s) {
    final i = s.toLowerCase().indexOf(query);
    final start = i - 30 < 0 ? 0 : i - 30;
    final end = i + query.length + 40 > s.length ? s.length : i + query.length + 40;
    return '${start > 0 ? '…' : ''}${s.substring(start, end).replaceAll('\n', ' ')}${end < s.length ? '…' : ''}';
  }
  for (final x in l.transcript) {
    if (has(x.text)) return 'בתמלול (${fmt(Duration(milliseconds: x.ms))}): ${cut(x.text)}';
  }
  if (has(l.summary)) return 'בסיכום: ${cut(l.summary)}';
  for (var i = 0; i < l.points.length; i++) {
    if (has(l.points[i])) return 'בנקודות: ${cut(l.points[i])}';
    if (i < l.pointNotes.length && has(l.pointNotes[i])) return 'בפירוט נקודה: ${cut(l.pointNotes[i])}';
  }
  for (final m in l.marks) {
    if (has(m.text)) return 'בסימניות (${fmt(Duration(milliseconds: m.ms))}): ${cut(m.text)}';
  }
  if (has(l.notes)) return 'בהערות: ${cut(l.notes)}';
  return null;
}
