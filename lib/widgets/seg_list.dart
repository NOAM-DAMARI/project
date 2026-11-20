import '../models/lesson.dart';
import '../services/player_service.dart';
import '../utils/helpers.dart';
import 'package:flutter/material.dart';

/// רשימת קטעים עם זמן (סימניות / שורות תמלול). לחיצה = קפיצה לזמן.
class SegList extends StatelessWidget {
  final List<Seg> list;
  final Track track;
  final String addLabel;
  final VoidCallback changed;
  final Widget? header;
  final String emptyText;

  const SegList(
    this.list,
    this.track,
    this.addLabel,
    this.changed, {
    super.key,
    this.header,
    this.emptyText = 'אין עדיין פריטים',
  });

  int get _nowMs => player.isCurrent(track.id) ? player.p.position.inMilliseconds : 0;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return StreamBuilder<Duration>(
      stream: player.p.positionStream,
      builder: (context, snap) {
        final live = player.isCurrent(track.id);
        final pos = live ? (snap.data?.inMilliseconds ?? 0) : -1;
        var activeIdx = -1;
        for (var i = 0; i < list.length; i++) {
          if (list[i].ms <= pos) activeIdx = i;
        }
        return Column(children: [
          if (header != null) header!,
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(emptyText, style: TextStyle(color: c.onSurfaceVariant)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final s = list[i];
                      final active = i == activeIdx;
                      return ListTile(
                        dense: true,
                        selected: active,
                        selectedTileColor: c.primaryContainer.withValues(alpha: .45),
                        leading: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => player.seekTo(track, s.ms),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: c.primary.withValues(alpha: active ? .2 : .08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(fmt(Duration(milliseconds: s.ms)),
                                style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ),
                        title: Text(s.text, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 15)),
                        onTap: () => player.seekTo(track, s.ms),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          onSelected: (v) async {
                            if (v == 'edit') {
                              final t = await askText(context, 'עריכה', init: s.text, lines: 4);
                              if (t != null) {
                                s.text = t;
                                changed();
                              }
                            } else if (v == 'now') {
                              s.ms = _nowMs;
                              list.sort((a, b) => a.ms.compareTo(b.ms));
                              changed();
                            } else if (v == 'del') {
                              list.remove(s);
                              changed();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'edit', child: Text('עריכת טקסט')),
                            if (live) const PopupMenuItem(value: 'now', child: Text('קבע לזמן הנוכחי')),
                            const PopupMenuItem(value: 'del', child: Text('מחיקה')),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
              icon: const Icon(Icons.add_rounded),
              label: Text(live ? '$addLabel (${fmt(Duration(milliseconds: pos))})' : addLabel),
              onPressed: () async {
                final ms = _nowMs;
                final t = await askText(context, addLabel, lines: 3);
                if (t != null) {
                  list.add(Seg(ms, t));
                  list.sort((a, b) => a.ms.compareTo(b.ms));
                  changed();
                }
              },
            ),
          ),
        ]);
      },
    );
  }
}
