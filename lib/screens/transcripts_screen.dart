import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lesson.dart';
import '../services/app_state.dart';
import '../services/media_resolver.dart';
import '../services/player_service.dart';
import '../services/transcriber.dart';
import '../services/transcript_compare.dart';
import '../utils/helpers.dart';
import '../widgets/player_controls.dart';
import 'settings_screen.dart';

const _mainId = '__main__';

List<Seg> _copy(List<Seg> s) => [for (final x in s) Seg(x.ms, x.text)];

bool _sameSegs(List<Seg> a, List<Seg> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].ms != b[i].ms || a[i].text != b[i].text) return false;
  }
  return true;
}

/// שומר את התמלול הראשי הנוכחי כגרסה (אם הוא לא שמור כבר), כדי שלא ילך לאיבוד כשמחליפים אותו.
void preserveMainTranscript(Lesson l) {
  if (l.transcript.isEmpty) return;
  if (l.transcripts.any((v) => _sameSegs(v.segs, l.transcript))) return;
  l.transcripts.insert(
    0,
    TranscriptVersion(id: app.newId(), providerId: '', label: 'תמלול ראשי קודם · ${fmtDate(DateTime.now())}', segs: _copy(l.transcript)),
  );
}

/// מוסיף תוצאת תמלול כגרסה; אם אין עדיין תמלול ראשי – היא הופכת לראשי.
TranscriptVersion addTranscriptVersion(Lesson l, String providerId, List<Seg> segs) {
  final p = Transcriber.providerById(providerId);
  final v = TranscriptVersion(
    id: app.newId(),
    providerId: providerId,
    label: '${p.label} (${Transcriber.modelFor(providerId)}) · ${fmtDate(DateTime.now())}',
    segs: _copy(segs),
  );
  l.transcripts.add(v);
  if (l.transcript.isEmpty) l.transcript = _copy(segs);
  return v;
}

/// תמלולים מרובים לשיעור: הרצה במקביל בכמה מנועים, ניהול גרסאות והשוואה ביניהן.
class TranscriptsScreen extends StatefulWidget {
  final Lesson lesson;
  final int initialTab;
  const TranscriptsScreen(this.lesson, {super.key, this.initialTab = 0});
  @override
  State<TranscriptsScreen> createState() => _TranscriptsScreenState();
}

class _TranscriptsScreenState extends State<TranscriptsScreen> with SingleTickerProviderStateMixin {
  Lesson get l => widget.lesson;
  late final tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  /// סטטוס לכל מנוע שרץ כרגע (id → הודעה)
  final running = <String, String>{};
  final errors = <String, String>{};

  String aId = _mainId;
  String? bId;
  bool onlyDiffs = false;

  List<Seg> _segsOf(String? id) {
    if (id == null) return const [];
    if (id == _mainId) return l.transcript;
    for (final v in l.transcripts) {
      if (v.id == id) return v.segs;
    }
    return const [];
  }

  List<(String, String)> get _sources => [
        if (l.transcript.isNotEmpty) (_mainId, 'התמלול הראשי'),
        for (final v in l.transcripts) (v.id, v.label),
      ];

  @override
  void initState() {
    super.initState();
    final src = _sources;
    if (src.isNotEmpty) aId = src.first.$1;
    if (src.length > 1) bId = src[1].$1;
  }

  Future<void> _runEngines() async {
    if (!l.hasMedia) {
      snack(context, 'יש להעלות קודם הקלטה לשיעור');
      return;
    }
    final chosen = await showDialog<List<String>>(context: context, builder: (_) => const _ChooseEnginesDialog());
    if (chosen == null || chosen.isEmpty || !mounted) return;

    setState(() {
      for (final id in chosen) {
        running[id] = 'ממתין...';
        errors.remove(id);
      }
    });

    // מורידים את הקובץ פעם אחת לפני ההרצה המקבילית
    if (!kIsWeb) {
      try {
        await MediaResolver.ensureLocal(l, onProgress: (g, t) {
          if (t != null && mounted) setState(() => running.updateAll((_, __) => 'מוריד את הקובץ... ${g * 100 ~/ t}%'));
        });
      } catch (_) {}
    }

    await Future.wait([
      for (final id in chosen)
        () async {
          try {
            final segs = await Transcriber.transcribe(l, providerId: id, onStatus: (s) {
              if (mounted) setState(() => running[id] = s);
            });
            final v = addTranscriptVersion(l, id, segs);
            app.save();
            if (mounted) {
              setState(() {
                if (bId == null || bId == aId) bId = v.id;
              });
            }
          } catch (e) {
            errors[id] = e.toString().replaceFirst('Exception: ', '');
          } finally {
            running.remove(id);
            if (mounted) setState(() {});
          }
        }(),
    ]);
    if (mounted) {
      final ok = chosen.where((id) => !errors.containsKey(id)).length;
      snack(context, 'הסתיים: $ok מתוך ${chosen.length} מנועים הצליחו');
    }
  }

  void _setMain(TranscriptVersion v) {
    preserveMainTranscript(l);
    l.transcript = _copy(v.segs);
    app.save();
    setState(() {});
    snack(context, '"${v.label}" הוגדר כתמלול הראשי');
  }

  Future<void> _rename(TranscriptVersion v) async {
    final t = await askText(context, 'שם התמלול', init: v.label);
    if (t == null || t.trim().isEmpty) return;
    v.label = t.trim();
    app.save();
    setState(() {});
  }

  Future<void> _delete(TranscriptVersion v) async {
    if (!await confirm(context, 'למחוק את "${v.label}"?')) return;
    l.transcripts.remove(v);
    if (aId == v.id) aId = _mainId;
    if (bId == v.id) bId = null;
    app.save();
    setState(() {});
  }

  void _view(String title, List<Seg> segs) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 600,
          height: MediaQuery.of(ctx).size.height * .6,
          child: ListView(children: [
            for (final s in segs)
              InkWell(
                onTap: () => player.seekTo(Track.lesson(l), s.ms),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${fmt(Duration(milliseconds: s.ms))}  ',
                        style: TextStyle(color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w600)),
                    TextSpan(text: s.text),
                  ])),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: const Text('העתקה'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: segs.map((e) => e.text).join('\n')));
              snack(context, 'הועתק');
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('סגור')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('תמלולים והשוואה'),
        bottom: TabBar(controller: tabs, tabs: const [Tab(text: 'כל התמלולים'), Tab(text: 'השוואה')]),
      ),
      body: Column(children: [
        Expanded(child: TabBarView(controller: tabs, children: [_versionsTab(), _compareTab()])),
        const Divider(height: 1),
        SafeArea(top: false, child: PlayerControls(Track.lesson(l))),
      ]),
    );
  }

  Widget _versionsTab() {
    final c = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('תמלול עם כמה מנועים במקביל'),
        onPressed: running.isEmpty ? _runEngines : null,
      ),
      const SizedBox(height: 8),
      for (final e in running.entries)
        Card(
          child: ListTile(
            leading: const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text(Transcriber.providerById(e.key).label),
            subtitle: Text(e.value),
          ),
        ),
      for (final e in errors.entries)
        Card(
          color: c.errorContainer,
          child: ListTile(
            leading: Icon(Icons.error_outline_rounded, color: c.onErrorContainer),
            title: Text(Transcriber.providerById(e.key).label, style: TextStyle(color: c.onErrorContainer)),
            subtitle: Text(e.value, style: TextStyle(color: c.onErrorContainer)),
            trailing: IconButton(
                icon: Icon(Icons.close_rounded, color: c.onErrorContainer),
                onPressed: () => setState(() => errors.remove(e.key))),
          ),
        ),
      const SizedBox(height: 8),
      if (l.transcript.isNotEmpty)
        Card(
          child: ListTile(
            leading: Icon(Icons.star_rounded, color: c.primary),
            title: const Text('התמלול הראשי', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${l.transcript.length} שורות · מוצג בלשונית התמלול ובחיפוש'),
            onTap: () => _view('התמלול הראשי', l.transcript),
          ),
        ),
      if (l.transcripts.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'עדיין אין תמלולים נוספים. לחץ על הכפתור למעלה, בחר כמה מנועים מחוברים, ותקבל תמלול מכל אחד מהם להשוואה.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.onSurfaceVariant),
          ),
        ),
      for (final v in l.transcripts)
        Card(
          child: ListTile(
            leading: Icon(_sameSegs(v.segs, l.transcript) ? Icons.check_circle_rounded : Icons.description_outlined,
                color: _sameSegs(v.segs, l.transcript) ? c.primary : null),
            title: Text(v.label, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${v.segs.length} שורות${_sameSegs(v.segs, l.transcript) ? ' · זה התמלול הראשי' : ''}'),
            onTap: () => _view(v.label, v.segs),
            trailing: PopupMenuButton<String>(
              onSelected: (x) {
                if (x == 'main') _setMain(v);
                if (x == 'rename') _rename(v);
                if (x == 'delete') _delete(v);
                if (x == 'compare') {
                  setState(() {
                    aId = l.transcript.isNotEmpty ? _mainId : aId;
                    bId = v.id;
                  });
                  tabs.animateTo(1);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'main', child: Text('הגדר כתמלול ראשי')),
                PopupMenuItem(value: 'compare', child: Text('השווה לתמלול הראשי')),
                PopupMenuItem(value: 'rename', child: Text('שינוי שם')),
                PopupMenuItem(value: 'delete', child: Text('מחיקה')),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _compareTab() {
    final c = Theme.of(context).colorScheme;
    final src = {
      for (final source in _sources) source.$1: source,
    }.values.toList(growable: false);
    if (src.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('כדי להשוות צריך לפחות שני תמלולים. הרץ תמלול עם כמה מנועים בלשונית "כל התמלולים".',
              textAlign: TextAlign.center, style: TextStyle(color: c.onSurfaceVariant)),
        ),
      );
    }
    final ids = src.map((e) => e.$1).toSet();
    if (!ids.contains(aId)) aId = src.first.$1;
    if (bId == null || !ids.contains(bId)) bId = src.firstWhere((e) => e.$1 != aId).$1;

    final result = compareTranscripts(_segsOf(aId), _segsOf(bId));
    final rows = onlyDiffs ? result.rows.where((r) => r.diffCount > 0).toList() : result.rows;
    final wide = MediaQuery.of(context).size.width > 640;

    DropdownButtonFormField<String> picker(String label, String? value, ValueChanged<String?> onChanged, Color color) =>
        DropdownButtonFormField<String>(
          key: ValueKey('cmp-$label-$value'),
          initialValue: src.any((s) => s.$1 == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            prefixIcon: Icon(Icons.circle, size: 12, color: color),
          ),
          items: [for (final s in src) DropdownMenuItem(value: s.$1, child: Text(s.$2, overflow: TextOverflow.ellipsis))],
          onChanged: onChanged,
        );

    Widget words(List<DiffWord> ws, Color bg, Color fg) => Text.rich(
          TextSpan(children: [
            for (final w in ws)
              TextSpan(
                text: '${w.text} ',
                style: w.same ? null : TextStyle(backgroundColor: bg, color: fg, fontWeight: FontWeight.w600),
              ),
          ]),
          style: const TextStyle(height: 1.6),
        );

    final aColor = c.primary, bColor = c.tertiary;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Flex(direction: wide ? Axis.horizontal : Axis.vertical, children: [
          Flexible(
              fit: FlexFit.loose,
              child: picker('תמלול א', aId, (v) => setState(() => aId = v ?? aId), aColor)),
          SizedBox(width: wide ? 10 : 0, height: wide ? 0 : 10),
          Flexible(fit: FlexFit.loose, child: picker('תמלול ב', bId, (v) => setState(() => bId = v), bColor)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          Chip(
            avatar: const Icon(Icons.percent_rounded, size: 16),
            label: Text('דמיון ${result.similarity.toStringAsFixed(1)}%'),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text('א: ${result.wordsA} מילים · ב: ${result.wordsB} מילים',
                style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ),
          FilterChip(label: const Text('רק הבדלים'), selected: onlyDiffs, onSelected: (v) => setState(() => onlyDiffs = v)),
        ]),
      ),
      Expanded(
        child: rows.isEmpty
            ? Center(child: Text('אין הבדלים 🎉', style: TextStyle(color: c.onSurfaceVariant)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final colA = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('א', style: TextStyle(color: aColor, fontWeight: FontWeight.w700)),
                    words(r.a, c.primaryContainer, c.onPrimaryContainer),
                  ]);
                  final colB = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ב', style: TextStyle(color: bColor, fontWeight: FontWeight.w700)),
                    words(r.b, c.tertiaryContainer, c.onTertiaryContainer),
                  ]);
                  return Card(
                    child: InkWell(
                      onTap: () => player.seekTo(Track.lesson(l), r.startMs),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Icon(Icons.play_arrow_rounded, size: 18, color: c.primary),
                            Text(fmt(Duration(milliseconds: r.startMs)),
                                style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            if (r.diffCount > 0)
                              Text('${r.diffCount} הבדלים', style: Theme.of(context).textTheme.bodySmall),
                          ]),
                          const SizedBox(height: 6),
                          if (wide)
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: colA),
                              const VerticalDivider(width: 20),
                              Expanded(child: colB),
                            ])
                          else ...[
                            colA,
                            const Divider(height: 16),
                            colB,
                          ],
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _ChooseEnginesDialog extends StatefulWidget {
  const _ChooseEnginesDialog();
  @override
  State<_ChooseEnginesDialog> createState() => _ChooseEnginesDialogState();
}

class _ChooseEnginesDialogState extends State<_ChooseEnginesDialog> {
  late final selected = {for (final p in Transcriber.readyProviders) p.id};

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('באילו מנועים לתמלל?'),
      content: SizedBox(
        width: 460,
        child: ListView(shrinkWrap: true, children: [
          for (final p in Transcriber.providers)
            CheckboxListTile(
              value: selected.contains(p.id),
              onChanged: Transcriber.readyFor(p.id)
                  ? (v) => setState(() => v == true ? selected.add(p.id) : selected.remove(p.id))
                  : null,
              title: Text(p.label),
              subtitle: Text(
                Transcriber.readyFor(p.id) ? 'מודל: ${Transcriber.modelFor(p.id)}' : 'לא מחובר – יש להזין מפתח בהגדרות',
                style: TextStyle(color: Transcriber.readyFor(p.id) ? null : c.error),
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            go(context, const SettingsScreen(standalone: true));
          },
          child: const Text('חיבור מנועים'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ביטול')),
        FilledButton(
          onPressed: selected.isEmpty ? null : () => Navigator.pop(context, selected.toList()),
          child: Text('תמלול (${selected.length})'),
        ),
      ],
    );
  }
}
