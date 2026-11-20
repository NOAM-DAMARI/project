import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../utils/helpers.dart';

class OfflineModel {
  final String id, label, size, note, url;
  const OfflineModel(this.id, this.label, this.size, this.note, this.url);
}

/// ניהול מודלי תמלול מקומיים (Whisper בפורמט ggml) לאנדרואיד.
class OfflineModelsScreen extends StatefulWidget {
  const OfflineModelsScreen({super.key});

  static const models = [
    OfflineModel('fast', 'מהיר', '190MB', 'מתאים לטלפונים חלשים, דיוק בסיסי',
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin'),
    OfflineModel('recommended', 'מומלץ', '574MB', 'איזון טוב בין מהירות לדיוק',
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin'),
    OfflineModel('hebrew', 'מודל עברית מותאם', '1.6GB', 'ivrit.ai – הדיוק הגבוה ביותר בעברית, דורש טלפון חזק',
        'https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin'),
  ];

  static Future<File> fileFor(OfflineModel m) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/models/${m.id}.bin');
  }

  @override
  State<OfflineModelsScreen> createState() => _OfflineModelsScreenState();
}

class _OfflineModelsScreenState extends State<OfflineModelsScreen> {
  final progress = <String, double?>{};
  final present = <String, bool>{};
  final cancelled = <String>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (kIsWeb) return;
    for (final m in OfflineModelsScreen.models) {
      present[m.id] = (await OfflineModelsScreen.fileFor(m)).existsSync();
    }
    if (mounted) setState(() {});
  }

  Future<void> _download(OfflineModel m) async {
    final target = await OfflineModelsScreen.fileFor(m);
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.part');
    setState(() => progress[m.id] = null);
    cancelled.remove(m.id);
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(m.url)));
      if (res.statusCode != 200) throw Exception('שגיאת הורדה ${res.statusCode}');
      final total = res.contentLength;
      final sink = tmp.openWrite();
      var got = 0;
      var last = -1;
      await for (final chunk in res.stream) {
        if (cancelled.contains(m.id)) break;
        sink.add(chunk);
        got += chunk.length;
        if (total != null) {
          final pct = got * 100 ~/ total;
          if (pct != last && mounted) {
            last = pct;
            setState(() => progress[m.id] = got / total);
          }
        }
      }
      await sink.close();
      if (cancelled.contains(m.id)) {
        await tmp.delete();
      } else {
        if (target.existsSync()) await target.delete();
        await tmp.rename(target.path);
        if (mounted) snack(context, 'המודל "${m.label}" הורד');
      }
    } catch (e) {
      if (tmp.existsSync()) await tmp.delete();
      if (mounted) snack(context, 'ההורדה נכשלה: $e');
    } finally {
      client.close();
      progress.remove(m.id);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('תמלול מקומי (ללא אינטרנט)')),
      body: kIsWeb
          ? const Center(child: Text('תמלול מקומי זמין רק באפליקציה לאנדרואיד'))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('בחר מודל להורדה. הקבצים נשמרים במכשיר בלבד. קבצי שמע מומרים אוטומטית לפורמט המתאים לפני התמלול.',
                  style: TextStyle(color: c.onSurfaceVariant)),
              const SizedBox(height: 12),
              for (final m in OfflineModelsScreen.models)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                            child: Text('${m.label} · ${m.size}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (present[m.id] == true) Icon(Icons.check_circle_rounded, color: c.primary),
                      ]),
                      Text(m.note, style: TextStyle(color: c.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      if (progress.containsKey(m.id)) ...[
                        LinearProgressIndicator(value: progress[m.id]),
                        TextButton(onPressed: () => cancelled.add(m.id), child: const Text('ביטול')),
                      ] else
                        Wrap(spacing: 8, children: [
                          if (present[m.id] != true)
                            FilledButton.icon(
                                icon: const Icon(Icons.download_rounded),
                                label: const Text('הורדה'),
                                onPressed: () => _download(m)),
                          if (present[m.id] == true)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('מחיקה'),
                              onPressed: () async {
                                final f = await OfflineModelsScreen.fileFor(m);
                                if (f.existsSync()) await f.delete();
                                await _refresh();
                              },
                            ),
                        ]),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
