import '../services/app_state.dart';
import '../services/player_service.dart';
import '../models/lesson.dart';
import 'points_screen.dart';
import '../services/points.dart';
import '../widgets/point_dialog.dart';
import '../utils/helpers.dart';
import '../widgets/lesson_tile.dart';
import '../widgets/ui.dart';
import 'lesson_form.dart';
import 'lessons_screen.dart';
import 'package:flutter/material.dart';

Widget _lessonRows(List<Lesson> lessons) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        final width = columns == 1 ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final lesson in lessons)
              SizedBox(width: width, child: Card(margin: EdgeInsets.zero, child: LessonTile(lesson))),
          ],
        );
      },
    );

String _pointRangeFor(Lesson lesson, int index) {
  if (index >= lesson.pointTimes.length) return 'זמן לא הוגדר';
  final start = lesson.pointTimes[index].ms;
  final end = index < lesson.pointEnds.length && lesson.pointEnds[index] > start
      ? lesson.pointEnds[index]
      : start + const Duration(minutes: 5).inMilliseconds;
  return '${fmt(Duration(milliseconds: start))}–${fmt(Duration(milliseconds: end))}';
}

class LessonsDashboard extends StatelessWidget {
  const LessonsDashboard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([app, player]),
        builder: (context, _) {
          final recent = ([...app.lessons]..sort((a, b) => b.added.compareTo(a.added))).take(6).toList();
          final inProgress = app.lessons.where((l) => (player.savedPosition(l.id) ?? 0) > 5000).toList();
          final transcribed = app.lessons.where((l) => l.transcript.isNotEmpty).length;
          final favs = app.lessons.where((l) => l.fav).length;
          final pointsCount = app.lessons.fold<int>(0, (sum, l) => sum + l.points.length);

          return Scaffold(
            body: SafeArea(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                HeroHeader(
                  title: 'שיעורים',
                  subtitle: '${app.lessons.length} שיעורים · $transcribed תומללו',
                  icon: Icons.school_rounded,
                  bottom: SearchField(
                    hint: 'חיפוש בשם, פרשה, תמלול או סיכום',
                    onHero: true,
                    onSubmitted: (q) => go(context, LessonsScreen(initialQuery: q)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  StatCard(
                      icon: Icons.school_rounded,
                      value: '${app.lessons.length}',
                      label: 'שיעורים',
                      onTap: () => go(context, const LessonsScreen())),
                  const SizedBox(width: 10),
                  StatCard(
                      icon: Icons.subject_rounded,
                      value: '$transcribed',
                      label: 'תומללו',
                      onTap: () => go(context, const LessonsScreen())),
                  const SizedBox(width: 10),
                  StatCard(
                      icon: Icons.star_rounded,
                      value: '$favs',
                      label: 'מועדפים',
                      onTap: () => go(context, const LessonsScreen(onlyFav: true))),
                  const SizedBox(width: 10),
                  StatCard(
                      icon: Icons.format_list_bulleted_rounded,
                      value: '$pointsCount',
                      label: 'נקודות',
                      onTap: () => go(context, const PointsScreen())),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('שיעור חדש'),
                      onPressed: () => go(context, const LessonForm()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.manage_search_rounded),
                      label: const Text('חיפוש מתקדם'),
                      onPressed: () => go(context, const LessonsScreen()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (pointsCount > 0) ...[
                  const SectionTitle('נקודות מפתח מכל השיעורים'),
                  Card(
                    child: Column(children: [
                      for (final item in [
                        for (final lesson in app.lessons)
                          for (var i = 0; i < lesson.points.length; i++) (lesson: lesson, index: i),
                      ].take(12))
                        ListTile(
                          dense: true,
                          leading: IconButton(
                            tooltip: 'נגן מהנקודה',
                            icon: const Icon(Icons.play_circle_outline_rounded),
                            onPressed: () => player.playSegment(Track.lesson(item.lesson),
                                item.lesson.pointStart(item.index), item.lesson.pointEnd(item.index)),
                          ),
                          title: Text(item.lesson.points[item.index], maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${item.lesson.title} · ${_pointRangeFor(item.lesson, item.index)}'),
                          onTap: () => showPointDialog(context, item.lesson, item.index),
                        ),
                    ]),
                  ),
                ],
                if (inProgress.isNotEmpty) ...[
                  const SectionTitle('המשך האזנה'),
                  _lessonRows(inProgress),
                ],
                SectionTitle('נוספו לאחרונה',
                    actionLabel: app.lessons.isEmpty ? null : 'הכל', onAction: () => go(context, const LessonsScreen())),
                if (recent.isEmpty)
                  EmptyState(
                    icon: Icons.headphones_rounded,
                    title: 'עדיין אין שיעורים',
                    subtitle: 'הוסף שיעור עם הקלטה, וקבל תמלול אוטומטי בלחיצה',
                    action: FilledButton.tonal(onPressed: () => go(context, const LessonForm()), child: const Text('הוספת שיעור')),
                  )
                else
                  _lessonRows(recent),
              ]),
            ),
          );
        },
      );
}
