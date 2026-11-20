import '../models/lesson.dart';
import '../screens/lesson_page.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import 'ui.dart';
import 'package:flutter/material.dart';

class LessonTile extends StatelessWidget {
  final Lesson l;

  /// קטע טקסט שמראה היכן נמצאה מילת החיפוש
  final String? hint;
  const LessonTile(this.l, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final saved = player.savedPosition(l.id);
    return ListTile(
      selected: player.isCurrent(l.id),
      selectedTileColor: c.primaryContainer.withValues(alpha: .35),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: c.tertiaryContainer, borderRadius: BorderRadius.circular(14)),
        child: Icon(Icons.headphones_rounded, color: c.onTertiaryContainer),
      ),
      title: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(lessonMeta(l)),
          if (hint != null) Text(hint!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.primary, fontSize: 12)),
          if (l.transcript.isNotEmpty) const Pill('תומלל', icon: Icons.subject_rounded),
          if (saved != null && saved > 5000) Pill('הופסק ב-${fmt(Duration(milliseconds: saved))}', icon: Icons.history_rounded),
        ]),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: l.fav ? 'הסרה ממועדפים' : 'הוספה למועדפים',
          icon: Icon(l.fav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: l.fav ? const Color(0xFFF2A541) : c.onSurfaceVariant),
          onPressed: () {
            l.fav = !l.fav;
            app.save();
          },
        ),
        if (l.hasMedia)
          IconButton(
            tooltip: 'השמעה',
            icon: const Icon(Icons.play_circle_outline_rounded),
            onPressed: () => player.open(Track.lesson(l)),
          ),
        IconButton(
          tooltip: 'מחיקת השיעור',
          icon: Icon(Icons.delete_outline_rounded, color: c.error),
          onPressed: () async {
            if (await confirm(context, 'למחוק את השיעור "${l.title}"?')) {
              app.deleteLesson(l);
            }
          },
        ),
      ]),
      onTap: () => go(context, LessonPage(l)),
    );
  }
}
