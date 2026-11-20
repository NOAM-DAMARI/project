import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import '../widgets/mini_player.dart';
import '../widgets/ui.dart';
import 'song_player_page.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('רשימות השמעה')),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add_rounded),
            label: const Text('רשימה חדשה'),
            onPressed: () async {
              final t = await askText(context, 'שם הרשימה');
              if (t != null) {
                app.playlists.add(Playlist(id: app.newId(), name: t));
                app.save();
              }
            },
          ),
          bottomNavigationBar: const WithMiniPlayer(),
          body: app.playlists.isEmpty
              ? const EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: 'אין רשימות השמעה',
                  subtitle: 'צור רשימה והוסף אליה שירים',
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                  for (final p in app.playlists)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.queue_music_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          ),
                          title: Text(p.name),
                          subtitle: Text('${p.songIds.length} שירים'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton.filledTonal(
                              tooltip: 'השמעת הרשימה',
                              icon: const Icon(Icons.play_arrow_rounded),
                              onPressed: () => _play(p, false),
                            ),
                            IconButton(
                              tooltip: 'מחיקת הרשימה',
                              icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                              onPressed: () async {
                                if (await confirm(context, 'למחוק את הרשימה "${p.name}"?')) {
                                  app.playlists.remove(p);
                                  app.save();
                                }
                              },
                            ),
                          ]),
                          onTap: () => go(context, PlaylistPage(p)),
                        ),
                      ),
                    ),
                ]),
        ),
      );
}

List<Song> _songsOf(Playlist pl) =>
    pl.songIds.map(app.songById).whereType<Song>().toList();

void _play(Playlist pl, bool shuffled) {
  final songs = _songsOf(pl).where((s) => s.hasMedia).toList();
  player.playQueue(songs.map(Track.song).toList(), shuffled: shuffled);
}

class PlaylistPage extends StatelessWidget {
  final Playlist pl;
  const PlaylistPage(this.pl, {super.key});

  Future<void> pick(BuildContext c) async {
    final sel = {...pl.songIds};
    final ok = await showDialog<bool>(
      context: c,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('בחירת שירים'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final s in app.songs)
                CheckboxListTile(
                  value: sel.contains(s.id),
                  title: Text(s.title),
                  subtitle: Text(app.singer(s.singerId)?.name ?? ''),
                  onChanged: (v) => set(() {
                    v! ? sel.add(s.id) : sel.remove(s.id);
                  }),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('שמירה')),
          ],
        ),
      ),
    );
    if (ok == true) {
      // שומרים על הסדר הקיים ומוסיפים חדשים בסוף
      pl.songIds = [...pl.songIds.where(sel.contains), ...sel.where((id) => !pl.songIds.contains(id))];
      app.save();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final songs = _songsOf(pl);
          return Scaffold(
            appBar: AppBar(title: Text(pl.name), actions: [
              IconButton(tooltip: 'הוספת שירים', icon: const Icon(Icons.playlist_add_rounded), onPressed: () => pick(context)),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'rename') {
                    final t = await askText(context, 'שם הרשימה', init: pl.name);
                    if (t != null) {
                      pl.name = t;
                      app.save();
                    }
                  } else if (v == 'delete' && await confirm(context, 'למחוק את הרשימה?')) {
                    app.playlists.remove(pl);
                    app.save();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('שינוי שם')),
                  PopupMenuItem(value: 'delete', child: Text('מחיקת הרשימה')),
                ],
              ),
            ]),
            bottomNavigationBar: const WithMiniPlayer(),
            body: songs.isEmpty
                ? EmptyState(
                    icon: Icons.playlist_add_rounded,
                    title: 'הרשימה ריקה',
                    action: FilledButton.tonal(onPressed: () => pick(context), child: const Text('הוספת שירים')),
                  )
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('השמעה'),
                              onPressed: () => _play(pl, false)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                              icon: const Icon(Icons.shuffle_rounded), label: const Text('ערבוב'), onPressed: () => _play(pl, true)),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                        itemCount: songs.length,
                        onReorder: (a, b) {
                          if (b > a) b--;
                          final ids = songs.map((s) => s.id).toList();
                          ids.insert(b, ids.removeAt(a));
                          pl.songIds = ids;
                          app.save();
                        },
                        itemBuilder: (context, i) {
                          final s = songs[i];
                          return ListTile(
                            key: ValueKey(s.id),
                            leading: avatar(app.singer(s.singerId)),
                            title: Text(s.title),
                            subtitle: Text(app.singer(s.singerId)?.name ?? ''),
                            trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline_rounded),
                                onPressed: () {
                                  pl.songIds.remove(s.id);
                                  app.save();
                                }),
                            onTap: () {
                              final playable = songs.where((x) => x.hasMedia).toList();
                              if (s.hasMedia) {
                                player.playQueue(playable.map(Track.song).toList(), start: playable.indexOf(s));
                              }
                              go(context, SongPlayerPage(s));
                            },
                          );
                        },
                      ),
                    ),
                  ]),
          );
        },
      );
}

Future<void> addToPlaylist(BuildContext c, Song s) => showModalBottomSheet(
      context: c,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('הוספה לרשימת השמעה', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          for (final p in app.playlists)
            ListTile(
              leading: Icon(p.songIds.contains(s.id) ? Icons.check_circle_rounded : Icons.queue_music_rounded),
              title: Text(p.name),
              onTap: () {
                if (!p.songIds.contains(s.id)) p.songIds.add(s.id);
                app.save();
                Navigator.pop(ctx);
                snack(c, 'נוסף ל"${p.name}"');
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('רשימה חדשה'),
            onTap: () async {
              Navigator.pop(ctx);
              final t = await askText(c, 'שם הרשימה');
              if (t != null) {
                app.playlists.add(Playlist(id: app.newId(), name: t, songIds: [s.id]));
                app.save();
              }
            },
          ),
        ]),
      ),
    );
