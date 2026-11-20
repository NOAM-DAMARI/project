import 'package:flutter/material.dart';

import '../services/player_service.dart';
import '../widgets/player_controls.dart';

/// מסך הנגן המלא – מציג את מה שמתנגן עכשיו, עם אותו נגן של האפליקציה המלאה.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  String? _marked;

  void _mark(String? id) {
    if (id == _marked) return;
    if (_marked != null) player.markFullScreen(_marked!, false);
    if (id != null) player.markFullScreen(id, true);
    _marked = id;
  }

  @override
  void dispose() {
    if (_marked != null) player.markFullScreen(_marked!, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final t = player.current;
          _mark(t?.id);
          final c = Theme.of(context).colorScheme;
          return Scaffold(
            appBar: AppBar(),
            body: t == null
                ? const Center(child: Text('לא מתנגן כלום'))
                : SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          children: [
                            Center(
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  color: c.primaryContainer,
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                child: Icon(
                                  t.kind == TrackKind.lesson
                                      ? Icons.menu_book_rounded
                                      : Icons.music_note_rounded,
                                  size: 64,
                                  color: c.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                t.title.isEmpty ? 'ללא שם' : t.title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (player.queue.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${player.index + 1} מתוך ${player.queue.length}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: c.onSurfaceVariant),
                                ),
                              ),
                            const SizedBox(height: 16),
                            PlayerControls(t),
                          ],
                        ),
                      ),
                    ),
                  ),
          );
        },
      );
}
