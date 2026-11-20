import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../services/app_state.dart';
import '../services/export_service.dart';
import '../services/player_service.dart';
import '../services/points.dart';
import '../utils/helpers.dart';
import '../widgets/point_dialog.dart';
import '../widgets/ui.dart';

typedef PointRef = ({Lesson lesson, int index});

/// מרכז נקודות גלובלי: חיפוש, סינון לפי נושא ותת-נושא, מיון מתקדם, קיבוץ והדפסה.
class PointsScreen extends StatefulWidget {
  /// אם הוגדר – מציג רק נקודות של שיעור זה
  final Lesson? only;
  const PointsScreen({super.key, this.only});
  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
  String query = '';
  String sort = 'lesson';
  bool asc = true;
  String cat = '';
  String sub = '';
  bool grouped = false;

  static const sorts = {
    'lesson': 'שיעור וזמן',
    'time': 'דקה בשיעור',
    'date': 'תאריך שיעור',
    'number': 'מספר שיעור',
    'title': 'כותרת',
    'cat': 'נושא',
    'length': 'אורך קטע',
  };

  int _cmp(PointRef a, PointRef b) {
    final la = a.lesson, lb = b.lesson;
    int byTime() => la.pointStart(a.index).compareTo(lb.pointStart(b.index));
    final r = switch (sort) {
      'time' => byTime(),
      'date' => la.date.compareTo(lb.date) != 0 ? la.date.compareTo(lb.date) : byTime(),
      'number' => (la.number ?? 99999).compareTo(lb.number ?? 99999) != 0
          ? (la.number ?? 99999).compareTo(lb.number ?? 99999)
          : byTime(),
      'title' => la.pointTitle(a.index).compareTo(lb.pointTitle(b.index)),
      'cat' => _catKey(la.pointCat(a.index)).compareTo(_catKey(lb.pointCat(b.index))) != 0
          ? _catKey(la.pointCat(a.index)).compareTo(_catKey(lb.pointCat(b.index)))
          : la.pointSub(a.index).compareTo(lb.pointSub(b.index)),
      'length' => (la.pointEnd(a.index) - la.pointStart(a.index)).compareTo(lb.pointEnd(b.index) - lb.pointStart(b.index)),
      _ => la.title.compareTo(lb.title) != 0 ? la.title.compareTo(lb.title) : byTime(),
    };
    return asc ? r : -r;
  }

  static int _catKey(String c) {
    final i = pointCategories.indexOf(c);
    return i < 0 ? 99 : i;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final q = query.trim().toLowerCase();
          bool has(String s) => s.toLowerCase().contains(q);
          final source = widget.only != null ? [widget.only!] : app.lessons;
          final subs = <String>{
            for (final l in source)
              for (var i = 0; i < l.pointCount; i++)
                if ((cat.isEmpty || l.pointCat(i) == cat) && l.pointSub(i).isNotEmpty) l.pointSub(i)
          }.toList()
            ..sort();
          final items = <PointRef>[
            for (final lesson in source)
              for (var i = 0; i < lesson.pointCount; i++)
                if ((cat.isEmpty || lesson.pointCat(i) == cat || (cat == '-' && lesson.pointCat(i).isEmpty)) &&
                    (sub.isEmpty || lesson.pointSub(i) == sub) &&
                    (q.isEmpty ||
                        has(lesson.pointTitle(i)) ||
                        has(lesson.pointNote(i)) ||
                        has(lesson.pointSub(i)) ||
                        has(lesson.title)))
                  (lesson: lesson, index: i),
          ]..sort(_cmp);
          final c = Theme.of(context).colorScheme;

          Widget tile(PointRef r) {
            final lesson = r.lesson, i = r.index;
            final start = lesson.pointStart(i), end = lesson.pointEnd(i);
            final tag = [lesson.pointCat(i), lesson.pointSub(i)].where((e) => e.isNotEmpty).join(' › ');
            return Card(
              child: ListTile(
                onTap: () => showPointDialog(context, lesson, i),
                leading: ListenableBuilder(
                  listenable: player,
                  builder: (_, __) {
                    final active = player.isCurrent(lesson.id) && player.segmentEndMs != null;
                    return IconButton(
                      tooltip: active ? 'עצירה' : 'הפעל קטע',
                      icon: Icon(active ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded),
                      onPressed: () async {
                        if (active) {
                          await player.p.pause();
                          player.cancelSegment();
                        } else {
                          await player.playSegment(Track.lesson(lesson), start, end);
                        }
                      },
                    );
                  },
                ),
                title: Text(lesson.pointTitle(i), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${tag.isEmpty ? '' : '$tag\n'}'
                  '${lesson.number != null ? '#${lesson.number} ' : ''}${lesson.title} · '
                  '${fmt(Duration(milliseconds: start))}–${fmt(Duration(milliseconds: end))}'
                  '${lesson.pointNote(i).isEmpty ? '' : '\n${lesson.pointNote(i)}'}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'עריכה',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => showPointDialog(context, lesson, i, startEditing: true),
                  ),
                  IconButton(
                    tooltip: 'מחיקה',
                    icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                    onPressed: () async {
                      if (await confirm(context, 'למחוק את הנקודה "${lesson.pointTitle(i)}"?')) {
                        lesson.removePoint(i);
                        app.save();
                      }
                    },
                  ),
                ]),
              ),
            );
          }

          final children = <Widget>[];
          if (grouped) {
            for (final k in [...pointCategories, '']) {
              final group = items.where((r) => r.lesson.pointCat(r.index) == k).toList();
              if (group.isEmpty) continue;
              children.add(Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                child: Text('${k.isEmpty ? 'ללא נושא' : k} (${group.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.primary)),
              ));
              children.addAll(group.map(tile));
            }
          } else {
            children.addAll(items.map(tile));
          }

          return Scaffold(
            appBar: AppBar(title: Text('מרכז נקודות (${items.length})'), actions: [
              IconButton(
                tooltip: grouped ? 'רשימה רגילה' : 'קיבוץ לפי נושא',
                icon: Icon(grouped ? Icons.view_list_rounded : Icons.category_rounded),
                onPressed: () => setState(() => grouped = !grouped),
              ),
              IconButton(
                tooltip: 'הדפסה / PDF של הרשימה',
                icon: const Icon(Icons.print_rounded),
                onPressed: items.isEmpty
                    ? null
                    : () async {
                        try {
                          await printPoints(context, items, title: widget.only?.title ?? 'רשימת נקודות');
                        } catch (e) {
                          if (context.mounted) snack(context, 'ההדפסה נכשלה: $e');
                        }
                      },
              ),
            ]),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SearchField(
                    hint: 'חיפוש בכותרת, פירוט, תת-נושא או שיעור', onChanged: (value) => setState(() => query = value)),
              ),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  for (final k in ['', ...pointCategories, '-'])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: FilterChip(
                        label: Text(k.isEmpty ? 'כל הנושאים' : (k == '-' ? 'ללא נושא' : k)),
                        selected: cat == k,
                        onSelected: (_) => setState(() {
                          cat = k;
                          sub = '';
                        }),
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: sort,
                      items: [
                        for (final e in sorts.entries) DropdownMenuItem(value: e.key, child: Text('מיון: ${e.value}')),
                      ],
                      onChanged: (v) => setState(() => sort = v ?? sort),
                    ),
                  ),
                  IconButton(
                    tooltip: asc ? 'סדר עולה' : 'סדר יורד',
                    icon: Icon(asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                    onPressed: () => setState(() => asc = !asc),
                  ),
                  if (subs.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: subs.contains(sub) ? sub : '',
                        items: [
                          const DropdownMenuItem(value: '', child: Text('כל תתי-הנושאים')),
                          for (final s in subs) DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) => setState(() => sub = v ?? ''),
                      ),
                    ),
                  ],
                ]),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(q.isEmpty && cat.isEmpty ? 'עדיין אין נקודות' : 'לא נמצאו נקודות',
                            style: TextStyle(color: c.onSurfaceVariant)))
                    : ListView(padding: const EdgeInsets.all(12), children: children),
              ),
            ]),
          );
        },
      );
}
