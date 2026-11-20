import '../services/player_service.dart';
import '../services/app_state.dart';
import '../models/lesson.dart';
import '../utils/helpers.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'point_dialog.dart';

/// בקרי נגן מלאים: פס התקדמות, קדימה/אחורה, מהירות, טיימר שינה, ערבוב וחזרה.
/// אם הקטע אינו זה שמתנגן כרגע – מוצג כפתור "השמעה" שאינו קוטע את מה שמתנגן עד הלחיצה.
class PlayerControls extends StatelessWidget {
  final Track track;
  const PlayerControls(this.track, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final c = Theme.of(context).colorScheme;
          final isLesson = track.kind == TrackKind.lesson;

          if (!track.media.hasMedia) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.music_off_rounded, color: c.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('לא הועלה קובץ שמע', style: TextStyle(color: c.onSurfaceVariant)),
              ]),
            );
          }

          if (!player.isCurrent(track.id)) {
            final saved = isLesson ? player.savedPosition(track.id) : null;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                icon: const Icon(Icons.play_arrow_rounded, size: 28),
                label: Text(saved != null && saved > 5000
                    ? 'המשך האזנה מ-${fmt(Duration(milliseconds: saved))}'
                    : 'השמעה'),
                onPressed: () => player.open(track),
              ),
            );
          }

          final p = player.p;
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (player.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, color: c.error, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(player.error!, style: TextStyle(color: c.error))),
                    TextButton(onPressed: player.retry, child: const Text('נסה שוב')),
                  ]),
                ),
              if (player.loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(children: [
                    LinearProgressIndicator(value: player.downloadProgress),
                    if (player.downloadProgress != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('מוריד לשמירה במכשיר ${(player.downloadProgress! * 100).toStringAsFixed(0)}%',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ]),
                ),
              _SeekBar(p),
              // שורה אחת: מהירות, שינה, חזרה, ערבוב – ומימין עוצמת שמע
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  _SpeedButton(p),
                  _SleepButton(),
                  IconButton(
                    tooltip: 'חזרה',
                    visualDensity: VisualDensity.compact,
                    isSelected: player.repeat != LoopSetting.off,
                    icon: const Icon(Icons.repeat_rounded),
                    selectedIcon: Icon(player.repeat == LoopSetting.one ? Icons.repeat_one_on_rounded : Icons.repeat_on_rounded,
                        color: c.primary),
                    onPressed: () {
                      if (player.queue.length > 1) {
                        player.cycleRepeat();
                      } else {
                        player.repeat = player.repeat == LoopSetting.one ? LoopSetting.off : LoopSetting.all;
                        player.cycleRepeat();
                      }
                    },
                  ),
                  if (player.queue.length > 1)
                    IconButton(
                      tooltip: 'ערבוב',
                      visualDensity: VisualDensity.compact,
                      isSelected: player.shuffle,
                      icon: const Icon(Icons.shuffle_rounded),
                      selectedIcon: Icon(Icons.shuffle_on_rounded, color: c.primary),
                      onPressed: player.toggleShuffle,
                    ),
                  Expanded(
                    child: Row(children: [
                      IconButton(
                        tooltip: player.volume == 0 ? 'הפעלת שמע' : 'השתקה',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(player.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 20),
                        onPressed: player.toggleMute,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          ),
                          child: Slider(
                            value: player.volume.clamp(0.0, player.maxVolume).toDouble(),
                            min: 0,
                            max: player.maxVolume,
                            label: '${(player.volume * 100).round()}%',
                            divisions: (player.maxVolume * 20).round(),
                            onChanged: player.setVolume,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
              // בקרי מדיה נשארים משמאל לימין (כמו בכל נגן), צמודים למרכז
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _gap(IconButton(tooltip: 'אחורה 30 שניות', icon: const Icon(Icons.replay_30_rounded), onPressed: () => player.skip(-30))),
                  _gap(IconButton(tooltip: 'אחורה 10 שניות', icon: const Icon(Icons.replay_10_rounded), onPressed: () => player.skip(-10))),
                  if (player.queue.length > 1)
                    _gap(IconButton(tooltip: 'הקודם', icon: const Icon(Icons.skip_previous_rounded), onPressed: player.previous)),
                  StreamBuilder<PlayerState>(
                    stream: p.playerStateStream,
                    builder: (_, s) {
                      final playing = s.data?.playing ?? false;
                      final buffering = s.data?.processingState == ProcessingState.buffering ||
                          s.data?.processingState == ProcessingState.loading;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: IconButton.filled(
                            iconSize: 36,
                            icon: buffering && playing
                                ? SizedBox.square(
                                    dimension: 26, child: CircularProgressIndicator(strokeWidth: 3, color: c.onPrimary))
                                : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            onPressed: player.togglePlay,
                          ),
                        ),
                      );
                    },
                  ),
                  if (player.queue.length > 1)
                    _gap(IconButton(
                        tooltip: 'הבא',
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: player.hasNext ? () => player.next() : null)),
                  _gap(IconButton(tooltip: 'קדימה 10 שניות', icon: const Icon(Icons.forward_10_rounded), onPressed: () => player.skip(10))),
                  _gap(IconButton(tooltip: 'קדימה 30 שניות', icon: const Icon(Icons.forward_30_rounded), onPressed: () => player.skip(30))),
                ]),
              ),
              if (isLesson)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 64),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(app.livePointLessonId == track.id && app.livePointIndex != null
                        ? Icons.stop_circle_outlined
                        : Icons.add_circle_outline_rounded),
                    label: Text(app.livePointLessonId == track.id && app.livePointIndex != null
                        ? 'עצור וסגור נקודה'
                        : 'הוסף נקודה מהשנייה הנוכחית'),
                    onPressed: () {
                      final lesson = track.media as Lesson;
                      if (app.livePointLessonId == lesson.id && app.livePointIndex != null) {
                        stopLivePoint(lesson);
                        snack(context, 'טווח הנקודה נסגר');
                      } else {
                        showAddPointDialog(context, lesson);
                      }
                    },
                  ),
                ),
            ]),
          );
        },
      );
}

/// מצמצם רווחים בין כפתורי הנגן כדי שיהיו צמודים למרכז
Widget _gap(Widget button) => Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: button);

class _SeekBar extends StatefulWidget {
  final AudioPlayer p;
  const _SeekBar(this.p);
  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? dragging;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
        stream: widget.p.positionStream,
        builder: (context, s) {
          final pos = s.data ?? Duration.zero;
          final dur = widget.p.duration ?? Duration.zero;
          final mx = dur.inMilliseconds.toDouble();
          final value = (dragging ?? pos.inMilliseconds.toDouble()).clamp(0.0, mx > 0 ? mx : 1.0);
          final buffered = widget.p.bufferedPosition.inMilliseconds.toDouble().clamp(0.0, mx > 0 ? mx : 1.0);
          final style = Theme.of(context).textTheme.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
          return Column(children: [
            // פס ההתקדמות תמיד משמאל לימין, כמו בכל נגן
            Directionality(
              textDirection: TextDirection.ltr,
              child: Slider(
                value: value,
                secondaryTrackValue: buffered,
                max: mx > 0 ? mx : 1,
                onChanged: mx > 0 ? (v) => setState(() => dragging = v) : null,
                onChangeEnd: (v) {
                  widget.p.seek(Duration(milliseconds: v.toInt()));
                  setState(() => dragging = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(fmt(Duration(milliseconds: value.toInt())), style: style),
                  Text('-${fmt(dur - Duration(milliseconds: value.toInt()))}', style: style),
                ]),
              ),
            ),
          ]);
        },
      );
}

class _SpeedButton extends StatelessWidget {
  final AudioPlayer p;
  const _SpeedButton(this.p);

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
        stream: p.speedStream,
        builder: (context, s) {
          final speed = s.data ?? 1.0;
          return PopupMenuButton<double>(
            tooltip: 'מהירות השמעה',
            initialValue: speed,
            onSelected: player.setSpeed,
            itemBuilder: (_) => [
              for (final x in PlayerService.speeds) PopupMenuItem(value: x, child: Text('x$x${x == 1.0 ? ' (רגיל)' : ''}')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.speed_rounded, size: 20),
                const SizedBox(width: 2),
                Text('x$speed', style: Theme.of(context).textTheme.labelMedium),
              ]),
            ),
          );
        },
      );
}

class _SleepButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final label = player.sleepAtEnd
        ? 'טיימר שינה: בסוף הקטע'
        : player.sleepAt != null
            ? 'טיימר שינה: עד ${TimeOfDay.fromDateTime(player.sleepAt!).format(context)}'
            : 'טיימר שינה';
    return PopupMenuButton<int>(
      tooltip: label,
      padding: EdgeInsets.zero,
      icon: Icon(player.sleepActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
          size: 22, color: player.sleepActive ? Theme.of(context).colorScheme.primary : null),
      onSelected: (m) => player.setSleep(m < 0 ? null : Duration(minutes: m)),
      itemBuilder: (_) => [
        for (final m in [5, 15, 30, 45, 60]) PopupMenuItem(value: m, child: Text('$m דקות')),
        const PopupMenuItem(value: 0, child: Text('בסוף הקטע הנוכחי')),
        if (player.sleepActive) const PopupMenuItem(value: -1, child: Text('ביטול טיימר')),
      ],
    );
  }
}
