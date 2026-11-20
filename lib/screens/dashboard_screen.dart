import 'playlists_screen.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui.dart';
import 'package:flutter/material.dart';
import 'singer_form.dart';
import 'singers_screen.dart';
import 'song_form.dart';
import 'songs_screen.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final recent = ([...app.songs]..sort((a, b) => b.added.compareTo(a.added))).take(6).toList();
          final favs = app.songs.where((s) => s.fav).length;
          final playable = app.songs.where((s) => s.hasMedia).toList();
          final c = Theme.of(context).colorScheme;

          return Scaffold(
            body: SafeArea(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                HeroHeader(
                  title: 'הספרייה שלי',
                  subtitle: '${app.songs.length} שירים · ${app.singers.length} זמרים · ${app.playlists.length} רשימות',
                  icon: Icons.graphic_eq_rounded,
                  bottom: SearchField(
                    hint: 'חיפוש זמר, שיר או מילים',
                    onHero: true,
                    onSubmitted: (q) => go(context, SongsScreen(initialQuery: q, title: 'חיפוש')),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  StatCard(
                      icon: Icons.mic_rounded,
                      value: '${app.singers.length}',
                      label: 'זמרים',
                      onTap: () => go(context, const SingersScreen())),
                  const SizedBox(width: 10),
                  StatCard(
                      icon: Icons.music_note_rounded,
                      value: '${app.songs.length}',
                      label: 'שירים',
                      onTap: () => go(context, const SongsScreen(title: 'כל השירים'))),
                  const SizedBox(width: 10),
                  StatCard(
                      icon: Icons.star_rounded,
                      value: '$favs',
                      label: 'מועדפים',
                      onTap: () => go(context, const SongsScreen(title: 'מועדפים', onlyFav: true))),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.library_add_rounded),
                      label: const Text('שיר חדש'),
                      onPressed: () => go(context, const SongForm()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('זמר חדש'),
                      onPressed: () => go(context, const SingerForm()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    if (playable.isNotEmpty) ...[
                      ActionChip(
                        avatar: Icon(Icons.shuffle_rounded, size: 18, color: c.primary),
                        label: const Text('השמעה אקראית'),
                        onPressed: () => player.playQueue(playable.map(Track.song).toList(), shuffled: true),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ActionChip(
                      avatar: Icon(Icons.queue_music_rounded, size: 18, color: c.primary),
                      label: const Text('רשימות השמעה'),
                      onPressed: () => go(context, const PlaylistsScreen()),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: Icon(Icons.star_rounded, size: 18, color: c.primary),
                      label: const Text('מועדפים'),
                      onPressed: () => go(context, const SongsScreen(title: 'מועדפים', onlyFav: true)),
                    ),
                  ]),
                ),
                SectionTitle('נוספו לאחרונה',
                    actionLabel: app.songs.isEmpty ? null : 'הכל',
                    onAction: () => go(context, const SongsScreen(title: 'כל השירים'))),
                if (recent.isEmpty)
                  EmptyState(
                    icon: Icons.music_note_rounded,
                    title: 'עדיין אין שירים',
                    subtitle: app.singers.isEmpty ? 'התחל בהוספת זמר, ואז הוסף לו שירים' : 'הוסף את השיר הראשון שלך',
                    action: FilledButton.tonal(
                      onPressed: () => go(context, app.singers.isEmpty ? const SingerForm() : const SongForm()),
                      child: Text(app.singers.isEmpty ? 'הוספת זמר' : 'הוספת שיר'),
                    ),
                  )
                else
                  Card(child: Column(children: [for (final s in recent) SongTile(s, queue: recent)])),
              ]),
            ),
          );
        },
      );
}
