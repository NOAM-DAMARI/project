import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lesson.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../services/subtitle_formats.dart';
import '../utils/helpers.dart';

/// מצב עריכת כתוביות ממוקד: רק הכתוביות וכפתורי הפעלה/עצירה, ושליטה מלאה במקלדת.
///
/// קיצורים:
///  Enter / ↓ – שמירה ומעבר לכתובית הבאה (והנגן קופץ אליה)
///  Shift+Enter / ↑ – כתובית קודמת
///  Ctrl+Space / F2 – הפעלה / עצירה
///  Ctrl+R / F3 – השמעה חוזרת של קטע הכתובית הנוכחית
///  Ctrl+T / F4 – קביעת זמן הכתובית לרגע הנוכחי בנגן
///  Esc – יציאה
class SubtitleEditorScreen extends StatefulWidget {
  final Lesson lesson;
  const SubtitleEditorScreen(this.lesson, {super.key});
  @override
  State<SubtitleEditorScreen> createState() => _SubtitleEditorState();
}

class _SubtitleEditorState extends State<SubtitleEditorScreen> {
  Lesson get l => widget.lesson;
  Track get track => Track.lesson(l);
  int current = 0;
  late final ctl = TextEditingController(text: _textAt(0));
  final focus = FocusNode();
  final scroll = ScrollController();
  bool followPlayer = true;
  StreamSubscription<Duration>? sub;

  int get maxWords => app.prefs.getInt('sub_max_words') ?? 0;

  String _textAt(int i) => i < l.transcript.length ? l.transcript[i].text : '';

  @override
  void initState() {
    super.initState();
    player.markFullScreen(l.id, true);
    if (!player.isCurrent(l.id) && l.hasMedia) player.open(track, autoplay: false);
    sub = player.p.positionStream.listen((pos) {
      if (!followPlayer || !player.isCurrent(l.id) || !player.p.playing) return;
      var idx = 0;
      for (var i = 0; i < l.transcript.length; i++) {
        if (l.transcript[i].ms <= pos.inMilliseconds) idx = i;
      }
      if (idx != current && mounted) _goTo(idx, seek: false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  void dispose() {
    _commit();
    sub?.cancel();
    player.markFullScreen(l.id, false);
    ctl.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  int _words(String s) => s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

  void _commit() {
    if (current >= l.transcript.length) return;
    if (l.transcript[current].text != ctl.text) {
      l.transcript[current].text = ctl.text;
      app.save(notify: false);
    }
  }

  void _goTo(int i, {bool seek = true}) {
    if (l.transcript.isEmpty) return;
    _commit();
    final n = i.clamp(0, l.transcript.length - 1);
    setState(() {
      current = n;
      ctl.text = _textAt(n);
      ctl.selection = TextSelection.collapsed(offset: ctl.text.length);
    });
    if (seek && player.isCurrent(l.id)) player.p.seek(Duration(milliseconds: l.transcript[n].ms));
    focus.requestFocus();
    if (scroll.hasClients) {
      final target = (n * 56.0 - 120).clamp(0.0, scroll.position.maxScrollExtent);
      scroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  int _endOf(int i) =>
      i + 1 < l.transcript.length ? l.transcript[i + 1].ms : l.transcript[i].ms + 6000;

  Future<void> _replay() async {
    if (l.transcript.isEmpty) return;
    await player.playSegment(track, l.transcript[current].ms, _endOf(current));
  }

  void _togglePlay() {
    if (!player.isCurrent(l.id)) {
      player.open(track);
      return;
    }
    player.togglePlay();
  }

  void _stampNow() {
    if (!player.isCurrent(l.id) || l.transcript.isEmpty) return;
    final ms = player.p.position.inMilliseconds;
    final prev = current > 0 ? l.transcript[current - 1].ms : 0;
    l.transcript[current].ms = ms < prev ? prev : ms;
    app.save(notify: false);
    setState(() {});
  }

  void _applyWordLimit() {
    _commit();
    if (maxWords <= 0) return;
    final before = l.transcript.length;
    l.transcript = splitByWordLimit(l.transcript, maxWords);
    app.save();
    setState(() => ctl.text = _textAt(current));
    snack(context, 'פוצלו ${l.transcript.length - before} קטעים לפי מגבלה של $maxWords מילים');
  }

  Future<void> _setWordLimit() async {
    final v = await askText(context, 'מגבלת מילים לכל כתובית (0 = ללא מגבלה)', init: '$maxWords');
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n < 0) return;
    await app.prefs.setInt('sub_max_words', n);
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    final ctrl = hw.isControlPressed || hw.isMetaPressed;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      hw.isShiftPressed ? _goTo(current - 1) : _goTo(current + 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown && !hw.isShiftPressed) {
      _goTo(current + 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && !hw.isShiftPressed) {
      _goTo(current - 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f2 || (ctrl && k == LogicalKeyboardKey.space)) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f3 || (ctrl && k == LogicalKeyboardKey.keyR)) {
      _replay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f4 || (ctrl && k == LogicalKeyboardKey.keyT)) {
      _stampNow();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final words = _words(ctl.text);
    final over = maxWords > 0 && words > maxWords;
    return Scaffold(
      appBar: AppBar(
        title: const Text('עריכת כתוביות'),
        actions: [
          IconButton(
            tooltip: followPlayer ? 'מעקב אחרי הנגן: פעיל' : 'מעקב אחרי הנגן: כבוי',
            icon: Icon(followPlayer ? Icons.my_location_rounded : Icons.location_disabled_rounded),
            onPressed: () => setState(() => followPlayer = !followPlayer),
          ),
          TextButton.icon(
            icon: const Icon(Icons.format_list_numbered_rtl_rounded),
            label: Text(maxWords > 0 ? 'עד $maxWords מילים' : 'מגבלת מילים'),
            onPressed: _setWordLimit,
          ),
          if (maxWords > 0)
            IconButton(tooltip: 'פיצול כל הכתוביות לפי המגבלה', icon: const Icon(Icons.call_split_rounded), onPressed: _applyWordLimit),
        ],
      ),
      body: l.transcript.isEmpty
          ? Center(child: Text('אין כתוביות לעריכה. צור קודם תמלול.', style: TextStyle(color: c.onSurfaceVariant)))
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: l.transcript.length,
                  itemExtent: 56,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    selected: i == current,
                    selectedTileColor: c.primaryContainer.withValues(alpha: .5),
                    leading: Text(fmt(Duration(milliseconds: l.transcript[i].ms)),
                        style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
                    title: Text(i == current ? ctl.text : l.transcript[i].text, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _goTo(i),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: ctl,
                    focusNode: focus,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 4,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 20, height: 1.4),
                    decoration: InputDecoration(
                      labelText: 'כתובית ${current + 1} / ${l.transcript.length} · '
                          '${fmt(Duration(milliseconds: l.transcript[current].ms))}',
                      helperText: maxWords > 0 ? '$words / $maxWords מילים' : '$words מילים',
                      helperStyle: TextStyle(color: over ? c.error : null, fontWeight: over ? FontWeight.w700 : null),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton.filledTonal(
                          tooltip: 'כתובית קודמת (↑)', icon: const Icon(Icons.skip_next_rounded), onPressed: () => _goTo(current - 1)),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                          tooltip: 'השמעה חוזרת של הקטע (F3 / Ctrl+R)', icon: const Icon(Icons.replay_rounded), onPressed: _replay),
                      const SizedBox(width: 10),
                      ListenableBuilder(
                        listenable: player,
                        builder: (_, __) => StreamBuilder<bool>(
                          stream: player.p.playingStream,
                          builder: (_, snap) {
                            final playing = player.isCurrent(l.id) && (snap.data ?? false);
                            return IconButton.filled(
                              iconSize: 36,
                              tooltip: 'הפעלה / עצירה (F2 / Ctrl+רווח)',
                              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                              onPressed: _togglePlay,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                          tooltip: 'קביעת זמן לרגע הנוכחי (F4 / Ctrl+T)', icon: const Icon(Icons.timer_rounded), onPressed: _stampNow),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                          tooltip: 'כתובית הבאה (Enter / ↓)', icon: const Icon(Icons.skip_previous_rounded), onPressed: () => _goTo(current + 1)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      'Enter / ↓ הבאה · Shift+Enter / ↑ קודמת · F2 או Ctrl+רווח הפעלה/עצירה · '
                      'F3 או Ctrl+R השמעה חוזרת · F4 או Ctrl+T קביעת זמן · Esc יציאה',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}
