import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../services/player_service.dart';

/// כתוביות רצות: השורה הנוכחית מודגשת במרכז, והרשימה גוללת אוטומטית בזמן ההאזנה.
/// [showTimes]=false – תצוגת טקסט נקי (לשירים).
class LiveSubtitles extends StatefulWidget {
  final List<Seg> segs;
  final Track track;
  final bool showTimes;
  final double fontScale;
  final Color? accent;
  final EdgeInsets padding;
  const LiveSubtitles({
    super.key,
    required this.segs,
    required this.track,
    this.showTimes = true,
    this.fontScale = 1,
    this.accent,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  @override
  State<LiveSubtitles> createState() => _LiveSubtitlesState();
}

class _LiveSubtitlesState extends State<LiveSubtitles> {
  final _keys = <int, GlobalKey>{};
  int _active = -1;
  bool _userScrolling = false;

  GlobalKey _key(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  int _indexAt(int ms) {
    var lo = 0, hi = widget.segs.length - 1, best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (widget.segs[mid].ms <= ms) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  void _follow(int i) {
    if (i == _active) return;
    _active = i;
    if (_userScrolling || i < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[i]?.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx,
            alignment: .4, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
      }
    });
  }

  String _time(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0'), s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final accent = widget.accent ?? c.primary;
    return StreamBuilder<Duration>(
      stream: player.p.positionStream,
      builder: (context, snap) {
        final live = player.isCurrent(widget.track.id);
        final active = live ? _indexAt(snap.data?.inMilliseconds ?? 0) : -1;
        _follow(active);
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // גלילה ידנית עוצרת את המעקב ל-4 שניות
            if (n is UserScrollNotification) {
              _userScrolling = true;
              Future.delayed(const Duration(seconds: 4), () => _userScrolling = false);
            }
            return false;
          },
          child: SingleChildScrollView(
            padding: widget.padding.copyWith(top: 120, bottom: 200),
            child: Column(children: [
              for (var i = 0; i < widget.segs.length; i++)
                InkWell(
                  key: _key(i),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => player.seekTo(widget.track, widget.segs[i].ms),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: i == active ? accent.withValues(alpha: .12) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(children: [
                      if (widget.showTimes)
                        Text(_time(widget.segs[i].ms),
                            style: TextStyle(fontSize: 11, color: c.onSurfaceVariant, fontFeatures: const [])),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 260),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
                          fontSize: (i == active ? 24 : 19) * widget.fontScale,
                          height: 1.45,
                          fontWeight: i == active ? FontWeight.w800 : FontWeight.w500,
                          color: i == active
                              ? accent
                              : (active >= 0 ? c.onSurface.withValues(alpha: i < active ? .4 : .65) : c.onSurface),
                        ),
                        child: Text(widget.segs[i].text, textAlign: TextAlign.center),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
