import '../models/singer.dart';
import '../services/app_state.dart';
import '../utils/helpers.dart';
import '../widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'singer_form.dart';
import 'song_form.dart';
import 'songs_screen.dart';

class SingerPage extends StatelessWidget {
  final Singer s;
  const SingerPage(this.s, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final c = Theme.of(context).colorScheme;
          final color = Color(s.color);
          return Scaffold(
            appBar: AppBar(actions: [
              IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => go(context, SingerForm(singer: s))),
            ]),
            floatingActionButton: FloatingActionButton(
              onPressed: () => go(context, SongForm(initialSingerId: s.id)),
              child: const Icon(Icons.add_rounded),
            ),
            bottomNavigationBar: const WithMiniPlayer(),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color.withValues(alpha: .28), c.surface.withValues(alpha: 0)]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(children: [
                    avatar(s, r: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.name,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        if (s.notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(s.notes, style: TextStyle(color: c.onSurfaceVariant)),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
              Expanded(child: SongsScreen(singerId: s.id, title: s.name, embedded: true)),
            ]),
          );
        },
      );
}
