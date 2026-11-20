import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import '../widgets/mini_player.dart';
import 'connect_screen.dart';
import 'player_screen.dart';

/// הרשימה: שם בלבד, לחיצה משמיעה.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ItemKind _kind = ItemKind.lesson;

  /// משמיע את הפריט, וממשיך לבאים ברשימה (רק פריטים שיש להם קובץ שמע)
  void _play(List<Item> items, Item chosen) {
    final playable = items.where((i) => i.hasMedia).toList();
    player.playQueue([for (final i in playable) Track.item(i)],
        start: playable.indexOf(chosen));
    go(context, const PlayerScreen());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([app, player]),
        builder: (context, _) {
          final lib = app.library;
          final both = lib.lessons.isNotEmpty && lib.songs.isNotEmpty;
          final kind = both
              ? _kind
              : (lib.lessons.isEmpty && lib.songs.isNotEmpty
                  ? ItemKind.song
                  : ItemKind.lesson);
          final items = kind == ItemKind.lesson ? lib.lessons : lib.songs;
          final c = Theme.of(context).colorScheme;

          return Scaffold(
            appBar: AppBar(
              title: const Text('נגן שיעורים'),
              actions: [
                IconButton(
                  tooltip: 'רענון מהמאגר',
                  icon: app.refreshing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Icons.refresh_rounded),
                  onPressed: app.refreshing ? null : app.refresh,
                ),
                IconButton(
                  tooltip: 'חיבור ל-GitHub',
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () => go(context, const ConnectScreen()),
                ),
              ],
            ),
            bottomNavigationBar: const WithMiniPlayer(),
            body: Column(children: [
              if (app.error != null)
                MaterialBanner(
                  content: Text(app.error!),
                  leading: Icon(Icons.cloud_off_rounded, color: c.error),
                  actions: [
                    TextButton(onPressed: app.refresh, child: const Text('נסה שוב')),
                  ],
                ),
              if (both)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SegmentedButton<ItemKind>(
                    segments: [
                      ButtonSegment(
                          value: ItemKind.lesson,
                          label: Text('שיעורים (${lib.lessons.length})')),
                      ButtonSegment(
                          value: ItemKind.song,
                          label: Text('שירים (${lib.songs.length})')),
                    ],
                    selected: {kind},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: app.refresh,
                  child: items.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          Icon(Icons.library_music_outlined,
                              size: 48, color: c.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(
                            app.refreshing ? 'טוען מהמאגר…' : 'אין עדיין פריטים במאגר',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.onSurfaceVariant),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final item = items[i];
                            final current = player.isCurrent(item.id);
                            final playing = current && player.p.playing;
                            return Card(
                              child: ListTile(
                                enabled: item.hasMedia,
                                selected: current,
                                leading: Icon(
                                  !item.hasMedia
                                      ? Icons.music_off_rounded
                                      : playing
                                          ? Icons.graphic_eq_rounded
                                          : Icons.play_circle_fill_rounded,
                                  size: 32,
                                  color: item.hasMedia ? c.primary : null,
                                ),
                                title: Text(
                                  item.title.isEmpty ? 'ללא שם' : item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: item.hasMedia
                                    ? null
                                    : const Text('אין קובץ שמע'),
                                onTap: item.hasMedia
                                    ? () => _play(items, item)
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ]),
          );
        },
      );
}
