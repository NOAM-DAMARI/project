import '../models/song.dart';
import '../screens/song_player_page.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import 'package:flutter/material.dart';

class SongTile extends StatelessWidget {
  final Song s;

  /// הרשימה שממנה השיר נבחר – ההשמעה ממשיכה לשיר הבא ברשימה
  final List<Song>? queue;
  const SongTile(this.s, {super.key, this.queue});

  @override
  Widget build(BuildContext context) {
    final sg = app.singer(s.singerId);
    final c = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final now = player.isCurrent(s.id);
        return ListTile(
          selected: now,
          selectedTileColor: c.primaryContainer.withValues(alpha: .35),
          leading: avatar(sg),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [sg?.name ?? '', if (s.year != null) '${s.year}', if (s.duration?.isNotEmpty ?? false) s.duration!].join(' · '),
            maxLines: 1,
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (s.hasMedia)
              IconButton(
                tooltip: 'השמעה',
                icon: Icon(now ? Icons.graphic_eq_rounded : Icons.play_circle_outline_rounded, color: now ? c.primary : null),
                onPressed: () {
                  if (now) {
                    player.togglePlay();
                  } else if (queue != null && queue!.length > 1) {
                    final playable = queue!.where((x) => x.hasMedia).toList();
                    player.playQueue(playable.map(Track.song).toList(), start: playable.indexOf(s));
                  } else {
                    player.open(Track.song(s));
                  }
                },
              ),
            IconButton(
              tooltip: 'מועדף',
              icon: Icon(s.fav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: s.fav ? const Color(0xFFF2A541) : c.onSurfaceVariant),
              onPressed: () {
                s.fav = !s.fav;
                app.save();
              },
            ),
            IconButton(
              tooltip: 'מחיקת השיר',
              icon: Icon(Icons.delete_outline_rounded, color: c.error),
              onPressed: () async {
                if (await confirm(context, 'למחוק את השיר "${s.title}"?')) {
                  app.deleteSong(s);
                }
              },
            ),
          ]),
          onTap: () => go(context, SongPlayerPage(s)),
        );
      },
    );
  }
}
