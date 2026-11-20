import '../screens/player_screen.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// נגן מוקטן שמופיע בתחתית המסכים כשמשהו מתנגן.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  void _openFull(BuildContext context, Track t) => go(context, const PlayerScreen());

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([player, player.fullScreenOpen]),
        builder: (context, _) {
          final t = player.current;
          if (t == null || player.fullScreenOpen.value == t.id) return const SizedBox.shrink();
          final c = Theme.of(context).colorScheme;
          final accent = t.color != null ? Color(t.color!) : c.primary;

          return Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Material(
                color: c.surfaceContainerHighest,
                elevation: 3,
                shadowColor: c.shadow.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openFull(context, t),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
                      child: Row(children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: accent.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
                          child: Icon(t.kind == TrackKind.song ? Icons.music_note_rounded : Icons.headphones_rounded, color: accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(t.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              player.error ??
                                  (player.downloadProgress != null
                                      ? 'מוריד ${(player.downloadProgress! * 100).toStringAsFixed(0)}%'
                                      : t.subtitle),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: player.error != null ? c.error : c.onSurfaceVariant),
                            ),
                          ]),
                        ),
                        StreamBuilder<PlayerState>(
                          stream: player.p.playerStateStream,
                          builder: (_, s) {
                            final playing = s.data?.playing ?? false;
                            if (player.loading) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                              );
                            }
                            return IconButton(
                              icon: Icon(player.error != null
                                  ? Icons.refresh_rounded
                                  : playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded),
                              iconSize: 30,
                              onPressed: player.togglePlay,
                            );
                          },
                        ),
                        if (player.hasNext)
                          IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: () => player.next()),
                        IconButton(icon: const Icon(Icons.close_rounded, size: 20), tooltip: 'סגירה', onPressed: player.close),
                      ]),
                    ),
                    StreamBuilder<Duration>(
                      stream: player.p.positionStream,
                      builder: (_, s) {
                        final d = player.p.duration?.inMilliseconds ?? 0;
                        final v = d == 0 ? 0.0 : ((s.data?.inMilliseconds ?? 0) / d).clamp(0.0, 1.0);
                        return Directionality(
                          textDirection: TextDirection.ltr,
                          child: LinearProgressIndicator(value: v, minHeight: 3, color: accent),
                        );
                      },
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

/// עוטף מסך כך שהנגן המוקטן יופיע מעל התחתית שלו
class WithMiniPlayer extends StatelessWidget {
  final Widget? bottom;
  const WithMiniPlayer({super.key, this.bottom});

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        bottom: bottom == null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const MiniPlayer(),
          if (bottom != null) bottom!,
        ]),
      );
}
