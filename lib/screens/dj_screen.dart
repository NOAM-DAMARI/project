import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../models/song.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';

class DjScreen extends StatefulWidget {
  const DjScreen({super.key});

  @override
  State<DjScreen> createState() => _DjScreenState();
}

class _DjScreenState extends State<DjScreen> {
  String lessonQuery = '';
  String songQuery = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final lessons = app.lessons
              .where((item) => item.hasMedia)
              .where((item) => _matches(item.title, lessonQuery) ||
                  _matches(item.parasha, lessonQuery))
              .toList();
          final songs = app.songs
              .where((item) => item.hasMedia)
              .where((item) => _matches(item.title, songQuery) ||
                  _matches(app.singer(item.singerId)?.name ?? '', songQuery))
              .toList();
          return Scaffold(
            appBar: AppBar(title: const Text('DJ · השמעה ותור')),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('בחר שיעור או שיר להפעלה, או הוסף אותו לסוף התור.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final lessonList = _librarySection<Lesson>(
                        title: 'שיעורים',
                        query: lessonQuery,
                        onQuery: (value) => setState(() => lessonQuery = value),
                        items: lessons,
                        label: (item) => item.title,
                        sublabel: (item) => item.parasha,
                        play: (item) => Track.lesson(item),
                      );
                      final songList = _librarySection<Song>(
                        title: 'שירים',
                        query: songQuery,
                        onQuery: (value) => setState(() => songQuery = value),
                        items: songs,
                        label: (item) => item.title,
                        sublabel: (item) => app.singer(item.singerId)?.name ?? '',
                        play: (item) => Track.song(item),
                      );
                      return wide
                          ? Row(children: [
                              Expanded(child: lessonList),
                              const SizedBox(width: 12),
                              Expanded(child: songList),
                            ])
                          : Column(children: [
                              Expanded(child: lessonList),
                              const SizedBox(height: 8),
                              Expanded(child: songList),
                            ]);
                    }),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(height: 180, child: _queueSection()),
                ],
              ),
            ),
          );
        },
      );

  bool _matches(String value, String query) =>
      query.trim().isEmpty || value.toLowerCase().contains(query.trim().toLowerCase());

  Widget _librarySection<T>({
    required String title,
    required String query,
    required ValueChanged<String> onQuery,
    required List<T> items,
    required String Function(T) label,
    required String Function(T) sublabel,
    required Track Function(T) play,
  }) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            TextField(
              onChanged: onQuery,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'חיפוש $title',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('לא נמצאו פריטים עם קובץ שמע'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(label(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(sublabel(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                          leading: const Icon(Icons.graphic_eq_rounded),
                          trailing: Wrap(spacing: 4, children: [
                            IconButton.filledTonal(
                              tooltip: 'הוסף לתור',
                              onPressed: () {
                                player.enqueue(play(item));
                                snack(context, 'נוסף לתור');
                              },
                              icon: const Icon(Icons.playlist_add_rounded),
                            ),
                            IconButton.filled(
                              tooltip: 'הפעל עכשיו',
                              onPressed: () => player.open(play(item)),
                              icon: const Icon(Icons.play_arrow_rounded),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      );

  Widget _queueSection() => ListenableBuilder(
        listenable: player,
        builder: (context, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('תור השמעה', style: Theme.of(context).textTheme.titleLarge)),
                Text('${player.queue.length} פריטים'),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: player.queue.isEmpty
                    ? const Center(child: Text('התור ריק. הוסף שיעור או שיר מהרשימות למעלה.'))
                    : ReorderableListView.builder(
                  itemCount: player.queue.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    player.reorderQueue(oldIndex, newIndex);
                  },
                  itemBuilder: (context, i) => ListTile(
                    key: ValueKey('dj-queue-${player.queue[i].id}'),
                    dense: true,
                    leading: CircleAvatar(radius: 15, child: Text('${i + 1}')),
                    title: Text(player.queue[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(player.queue[i].kind == TrackKind.lesson ? 'שיעור' : 'שיר'),
                    trailing: Wrap(spacing: 2, children: [
                      IconButton(tooltip: 'הפעל', onPressed: () => player.open(player.queue[i]), icon: const Icon(Icons.play_arrow_rounded)),
                      IconButton(tooltip: 'הסר מהתור', onPressed: () => player.removeQueuedTrack(i), icon: const Icon(Icons.close_rounded)),
                    ]),
                  ),
                    ),
              ),
            ]),
          ),
        ),
      );
}
