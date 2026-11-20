import '../services/app_state.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import '../widgets/ui.dart';
import 'package:flutter/material.dart';
import 'song_form.dart';

class SongsScreen extends StatefulWidget {
  final String? singerId, initialQuery;
  final String title;
  final bool onlyFav, embedded;
  const SongsScreen(
      {super.key, this.singerId, this.initialQuery, required this.title, this.onlyFav = false, this.embedded = false});
  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  late String q = widget.initialQuery ?? '';
  String sort = 'title';
  bool inLyrics = true;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final query = q.trim().toLowerCase();
          final list = app.songs.where((s) {
            if (widget.singerId != null && s.singerId != widget.singerId) return false;
            if (widget.onlyFav && !s.fav) return false;
            if (query.isEmpty) return true;
            return s.title.toLowerCase().contains(query) ||
                (app.singer(s.singerId)?.name.toLowerCase().contains(query) ?? false) ||
                (inLyrics && s.lyrics.toLowerCase().contains(query));
          }).toList();
          list.sort((a, b) => switch (sort) {
                'singer' => (app.singer(a.singerId)?.name ?? '').compareTo(app.singer(b.singerId)?.name ?? ''),
                'year' => (b.year ?? 0).compareTo(a.year ?? 0),
                'recent' => b.added.compareTo(a.added),
                _ => a.title.compareTo(b.title),
              });
          final playable = list.where((s) => s.hasMedia).toList();

          final body = Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SearchField(
                hint: 'שם שיר / זמר / מילים',
                initial: q,
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                for (final e in {'title': 'א-ב', 'singer': 'זמר', 'year': 'שנה', 'recent': 'חדשים'}.entries)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                        label: Text(e.value), selected: sort == e.key, onSelected: (_) => setState(() => sort = e.key)),
                  ),
                FilterChip(
                    label: const Text('חיפוש במילים'), selected: inLyrics, onSelected: (v) => setState(() => inLyrics = v)),
              ]),
            ),
            if (playable.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(children: [
                  Text('${list.length} שירים', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('ערבוב'),
                    onPressed: () => player.playQueue(playable.map(Track.song).toList(), shuffled: true),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('השמע הכל'),
                    onPressed: () => player.playQueue(playable.map(Track.song).toList()),
                  ),
                ]),
              ),
            Expanded(
              child: list.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: query.isEmpty ? 'אין שירים' : 'לא נמצאו שירים',
                      subtitle: query.isEmpty ? null : 'נסה מילת חיפוש אחרת',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                      itemCount: list.length,
                      itemBuilder: (_, i) => SongTile(list[i], queue: list),
                    ),
            ),
          ]);
          if (widget.embedded) return body;
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            floatingActionButton: FloatingActionButton(
              onPressed: () => go(context, SongForm(initialSingerId: widget.singerId)),
              child: const Icon(Icons.add_rounded),
            ),
            bottomNavigationBar: const WithMiniPlayer(),
            body: body,
          );
        },
      );
}
