import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/transcriber.dart';
import '../utils/helpers.dart';

/// הגדרות תמלול בלשוניות – לשונית לכל מנוע, כל אחד עם מפתח ומודל משלו.
/// אפשר לחבר כמה מנועים במקביל ולבחור אחד כברירת מחדל.
class TranscriptionSettings extends StatefulWidget {
  const TranscriptionSettings({super.key});
  @override
  State<TranscriptionSettings> createState() => _TranscriptionSettingsState();
}

class _TranscriptionSettingsState extends State<TranscriptionSettings> with SingleTickerProviderStateMixin {
  final providers = Transcriber.providers;
  late final tabs = TabController(
    length: providers.length,
    vsync: this,
    initialIndex: providers.indexWhere((p) => p.id == Transcriber.providerId).clamp(0, providers.length - 1),
  );
  late final keys = {for (final p in providers) p.id: TextEditingController(text: app.prefs.getString('tr_key_${p.id}') ?? '')};
  late final models = {for (final p in providers) p.id: TextEditingController(text: Transcriber.modelFor(p.id))};
  late final endpoint = TextEditingController(text: Transcriber.customEndpoint);
  final showKey = <String>{};
  final testing = <String>{};
  final testResult = <String, (bool, String)>{};
  late String language = Transcriber.language;

  @override
  void initState() {
    super.initState();
    tabs.addListener(() {
      if (!tabs.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tabs.dispose();
    for (final c in [...keys.values, ...models.values, endpoint]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String id, {bool makeDefault = false}) async {
    await Transcriber.configure(
      providerId: id,
      key: keys[id]!.text,
      model: models[id]!.text,
      endpoint: id == 'custom' ? endpoint.text : null,
      language: language,
      makeDefault: makeDefault,
    );
    if (!mounted) return;
    setState(() {});
    final p = Transcriber.providerById(id);
    snack(
        context,
        Transcriber.readyFor(id)
            ? (makeDefault ? '${p.label} מחובר ומוגדר כברירת מחדל' : '${p.label} מחובר')
            : 'נשמר – חסר מפתח API ל-${p.label}');
  }

  Future<void> _test(String id) async {
    await _save(id);
    setState(() => testing.add(id));
    try {
      final msg = await Transcriber.testConnection(id);
      testResult[id] = (true, msg);
    } catch (e) {
      testResult[id] = (false, e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => testing.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final p = providers[tabs.index];
    final id = p.id;
    final isDefault = Transcriber.providerId == id;
    final ready = Transcriber.readyFor(id);
    final suggestions = Transcriber.modelSuggestions[id] ?? const <String>[];
    final result = testResult[id];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('חבר כמה מנועים שתרצה. בשיעור אפשר לתמלל בכמה מהם במקביל ולהשוות בין התמלולים.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
      const SizedBox(height: 8),
      TabBar(
        controller: tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: c.outlineVariant,
        tabs: [
          for (final x in providers)
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  Transcriber.readyFor(x.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: Transcriber.readyFor(x.id) ? c.primary : c.outline,
                ),
                const SizedBox(width: 6),
                Text(x.label),
                if (Transcriber.providerId == x.id) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.star_rounded, size: 16, color: c.tertiary),
                ],
              ]),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(children: [
        Chip(
          avatar: Icon(ready ? Icons.link_rounded : Icons.link_off_rounded, size: 16),
          label: Text(ready ? 'מחובר' : 'לא מחובר'),
          backgroundColor: ready ? c.primaryContainer : c.surfaceContainerHighest,
        ),
        const SizedBox(width: 6),
        if (isDefault) Chip(avatar: const Icon(Icons.star_rounded, size: 16), label: const Text('ברירת מחדל')),
      ]),
      const SizedBox(height: 4),
      Text(p.hint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
      if (id == 'custom') ...[
        const SizedBox(height: 10),
        TextField(
          controller: endpoint,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'כתובת השרת', hintText: 'https://.../v1/audio/transcriptions'),
        ),
      ],
      const SizedBox(height: 10),
      TextField(
        controller: keys[id],
        obscureText: !showKey.contains(id),
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: p.needsKey ? 'מפתח API' : 'מפתח API (לא חובה)',
          helperText: id.startsWith('openai') && keys[id]!.text.isEmpty && Transcriber.apiKeyFor(id).isNotEmpty
              ? 'משתמש במפתח של מנוע OpenAI השני'
              : null,
          suffixIcon: IconButton(
            icon: Icon(showKey.contains(id) ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => setState(() => showKey.contains(id) ? showKey.remove(id) : showKey.add(id)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: models[id],
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(labelText: 'מודל'),
      ),
      if (suggestions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final m in suggestions)
              ActionChip(
                label: Text(m),
                onPressed: () => setState(() => models[id]!.text = m),
              ),
          ]),
        ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: ['he', 'en', 'ar', 'yi', ''].contains(language) ? language : 'he',
        decoration: const InputDecoration(labelText: 'שפת התמלול (לכל המנועים)'),
        items: const [
          DropdownMenuItem(value: 'he', child: Text('עברית')),
          DropdownMenuItem(value: 'en', child: Text('אנגלית')),
          DropdownMenuItem(value: 'ar', child: Text('ערבית')),
          DropdownMenuItem(value: 'yi', child: Text('יידיש')),
          DropdownMenuItem(value: '', child: Text('זיהוי אוטומטי')),
        ],
        onChanged: (v) => setState(() => language = v ?? 'he'),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          icon: const Icon(Icons.save_rounded),
          label: const Text('שמירה'),
          onPressed: () => _save(id),
        ),
        OutlinedButton.icon(
          icon: testing.contains(id)
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.network_check_rounded),
          label: const Text('בדיקת חיבור'),
          onPressed: testing.contains(id) ? null : () => _test(id),
        ),
        if (!isDefault)
          OutlinedButton.icon(
            icon: const Icon(Icons.star_outline_rounded),
            label: const Text('קבע כברירת מחדל'),
            onPressed: () => _save(id, makeDefault: true),
          ),
      ]),
      if (result != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(result.$2, style: TextStyle(color: result.$1 ? c.primary : c.error, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 8),
      Text(
        'מחוברים כרגע: ${Transcriber.readyProviders.isEmpty ? 'אין' : Transcriber.readyProviders.map((e) => e.label).join(', ')}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }
}
