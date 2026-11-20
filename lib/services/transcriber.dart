import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/lesson.dart';
import '../models/media.dart';
import '../utils/mp3.dart';
import 'app_state.dart';
import 'media_resolver.dart';
import 'storage.dart';

typedef _Cfg = ({TranscribeProvider provider, String key, String endpoint, String model});

class TranscribeProvider {
  final String id, label, endpoint, model, hint;
  final bool needsKey;
  const TranscribeProvider(this.id, this.label, this.endpoint, this.model, this.needsKey, this.hint);
}

/// מנועי תמלול בענן (OpenAI / Soniox / Groq / שרת מותאם). השירות החינמי המובנה שנסגר הוסר.
class Transcriber {
  static const providers = [
    TranscribeProvider('soniox', 'Soniox בזמן אמת', 'wss://stt-rt.soniox.com/transcribe-websocket', 'stt-rt-v6',
        true, 'תמלול WebSocket מהיר. נדרש API key מ־console.soniox.com.'),
    TranscribeProvider('groq', 'Groq Whisper (מהיר מאוד)', 'https://api.groq.com/openai/v1/audio/transcriptions',
        'whisper-large-v3', true, 'מפתח: console.groq.com ← API Keys'),
    TranscribeProvider('openai', 'OpenAI Whisper', 'https://api.openai.com/v1/audio/transcriptions', 'whisper-1', true,
        'מודל whisper-1 – מחזיר זמנים לכל קטע (מומלץ לכתוביות). מפתח: platform.openai.com ← API keys'),
    TranscribeProvider('openai-gpt-transcribe', 'OpenAI GPT-4o Transcribe', 'https://api.openai.com/v1/audio/transcriptions', 'gpt-4o-transcribe', true,
        'מודל OpenAI מדויק מאוד למילים (ללא זמנים לכל שורה – מומלץ whisper-1 כשצריך זמנים). דורש חשבון פעיל ומפתח API.'),
    TranscribeProvider('custom', 'שרת מותאם אישית', '', 'whisper-1', false, 'כל שרת תואם OpenAI'),
  ];

  /// גודל כל חלק שנשלח לשרת (רוב השרתים מגבילים ל-25MB)
  static const chunkBytes = 20 * 1024 * 1024;

  static String get providerId {
    final saved = app.prefs.getString('tr_provider');
    return providers.any((p) => p.id == saved) ? saved! : providers.first.id;
  }
  static TranscribeProvider get provider => providerById(providerId);
  static TranscribeProvider providerById(String id) =>
      providers.firstWhere((p) => p.id == id, orElse: () => providers.first);

  /// מפתח לכל מנוע בנפרד. שני מנועי OpenAI חולקים מפתח אם הוזן רק באחד מהם.
  static String apiKeyFor(String id) {
    final own = app.prefs.getString('tr_key_$id') ?? '';
    if (own.isNotEmpty) return own;
    if (id == 'openai-gpt-transcribe') return app.prefs.getString('tr_key_openai') ?? '';
    if (id == 'openai') return app.prefs.getString('tr_key_openai-gpt-transcribe') ?? '';
    return '';
  }

  static String endpointFor(String id) => id == 'custom' ? customEndpoint : providerById(id).endpoint;
  static String modelFor(String id) {
    final saved = app.prefs.getString('tr_model_$id') ?? (id == 'custom' ? app.prefs.getString('tr_model') : null);
    return (saved == null || saved.trim().isEmpty) ? providerById(id).model : saved;
  }
  static bool readyFor(String id) =>
      endpointFor(id).isNotEmpty && (!providerById(id).needsKey || apiKeyFor(id).isNotEmpty);

  /// כל המנועים שמוגדרים ומוכנים לשימוש
  static List<TranscribeProvider> get readyProviders => [for (final p in providers) if (readyFor(p.id)) p];

  /// הצעות מודל לכל מנוע (אפשר גם להקליד שם אחר)
  static const modelSuggestions = {
    'soniox': ['stt-rt-v6', 'stt-rt-preview'],
    'groq': ['whisper-large-v3', 'whisper-large-v3-turbo'],
    'openai': ['whisper-1', 'gpt-4o-transcribe', 'gpt-4o-mini-transcribe'],
    'openai-gpt-transcribe': ['gpt-4o-transcribe', 'gpt-4o-mini-transcribe'],
    'custom': ['whisper-1'],
  };

  static String get apiKey => apiKeyFor(providerId);
  static String get customEndpoint => app.prefs.getString('tr_endpoint') ?? '';
  static String get language => app.prefs.getString('tr_lang') ?? 'he';

  static String get endpoint => endpointFor(providerId);
  static String get model => modelFor(providerId);

  static bool get ready => readyFor(providerId);

  /// בדיקת חיבור אמיתית מול הספק – בלי לשלוח קובץ שמע.
  static Future<String> testConnection(String id) async {
    final key = apiKeyFor(id);
    final p = providerById(id);
    if (p.needsKey && key.isEmpty) throw Exception('חסר מפתח API');
    Uri? uri;
    switch (id) {
      case 'openai':
      case 'openai-gpt-transcribe':
        uri = Uri.parse('https://api.openai.com/v1/models/${modelFor(id)}');
      case 'groq':
        uri = Uri.parse('https://api.groq.com/openai/v1/models');
      case 'soniox':
        uri = Uri.parse('https://api.soniox.com/v1/models');
      default:
        final ep = endpointFor(id);
        if (ep.isEmpty) throw Exception('חסרה כתובת שרת');
        return 'הכתובת נשמרה. הבדיקה המלאה תתבצע בתמלול הראשון.';
    }
    final res = await http
        .get(uri, headers: {if (key.isNotEmpty) 'Authorization': 'Bearer $key'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 401 || res.statusCode == 403) throw Exception('המפתח שגוי או שאין לו הרשאה (${res.statusCode})');
    if (res.statusCode == 404) throw Exception('המודל "${modelFor(id)}" לא זמין בחשבון הזה (404)');
    if (res.statusCode == 429) throw Exception(explain429(utf8.decode(res.bodyBytes, allowMalformed: true), res.headers, p.label));
    if (res.statusCode != 200) throw Exception('הספק החזיר ${res.statusCode}');
    if (id == 'openai' || id == 'openai-gpt-transcribe') {
      // רשימת המודלים עובדת גם בלי יתרה – לכן שולחים שנייה של שקט כדי לוודא שהחיוב פעיל
      final req = http.MultipartRequest('POST', Uri.parse(p.endpoint))
        ..headers['Authorization'] = 'Bearer $key'
        ..fields['model'] = modelFor(id)
        ..files.add(http.MultipartFile.fromBytes('file', _silentWav(), filename: 'test.wav'));
      final t = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
      if (t.statusCode == 429) throw Exception(explain429(utf8.decode(t.bodyBytes, allowMalformed: true), t.headers, p.label));
      if (t.statusCode == 401 || t.statusCode == 403) throw Exception('למפתח אין הרשאה לתמלול (${t.statusCode})');
      if (t.statusCode >= 300 && t.statusCode != 400) throw Exception('בדיקת התמלול החזירה ${t.statusCode}');
      return 'החיבור תקין ✓ – המפתח פעיל, יש יתרה והמודל ${modelFor(id)} זמין';
    }
    return 'החיבור תקין ✓';
  }

  static Future<List<Seg>> alignTextWithAI(String sourceText, List<Seg> transcript) async {
    if (apiKey.isEmpty) throw Exception('נדרש מפתח API בתפריט התמלול');
    final endpointBase = provider.id == 'groq'
        ? 'https://api.groq.com/openai/v1/chat/completions'
        : 'https://api.openai.com/v1/chat/completions';
    final payload = {
      'model': provider.id == 'groq' ? 'llama-3.3-70b-versatile' : 'gpt-4o-mini',
      'temperature': 0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': 'You align Hebrew text lines to transcript timestamps. Return JSON only: {"segments":[{"ms":number,"text":string}]}. Preserve every source line in order. Use the nearest matching transcript timestamp; do not invent timestamps.'},
        {'role': 'user', 'content': jsonEncode({'source_lines': sourceText.split(RegExp(r'\r?\n')).where((x) => x.trim().isNotEmpty).toList(), 'transcript': transcript.map((s) => {'ms': s.ms, 'text': s.text}).toList()})},
      ],
    };
    final response = await http.post(Uri.parse(endpointBase), headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    }, body: jsonEncode(payload)).timeout(const Duration(minutes: 3));
    if (response.statusCode == 429) {
      throw Exception(explain429(utf8.decode(response.bodyBytes, allowMalformed: true), response.headers, provider.label));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('AI התאמת הטקסט נכשלה (${response.statusCode})');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices']?[0]?['message']?['content']?.toString() ?? '';
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    final rows = decoded['segments'] as List<dynamic>? ?? const [];
    return rows.whereType<Map>().map((row) => Seg((row['ms'] as num?)?.round() ?? 0, row['text']?.toString() ?? '')).where((s) => s.text.trim().isNotEmpty).toList();
  }

  static Future<void> configure({
    required String providerId,
    String? key,
    String? endpoint,
    String? model,
    String? language,
    bool makeDefault = true,
  }) async {
    if (makeDefault) await app.prefs.setString('tr_provider', providerId);
    if (key != null) await app.prefs.setString('tr_key_$providerId', key.trim());
    if (endpoint != null) await app.prefs.setString('tr_endpoint', endpoint.trim());
    if (model != null) await app.prefs.setString('tr_model_$providerId', model.trim());
    if (language != null) await app.prefs.setString('tr_lang', language);
  }

  /// מתמלל קובץ שמע. קבצי MP3 גדולים נחתכים אוטומטית לחלקים.
  static Future<List<Seg>> transcribe(MediaFields m, {void Function(String status)? onStatus, String? providerId}) async {
    final id = providerId ?? Transcriber.providerId;
    final cfg = (
      provider: providerById(id),
      key: apiKeyFor(id),
      endpoint: endpointFor(id),
      model: modelFor(id),
    );
    if (!readyFor(id)) throw Exception('המנוע "${cfg.provider.label}" לא מחובר – יש להזין מפתח API בהגדרות ← תמלול');
    final name = m.fileName ?? 'audio.mp3';
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'mp3';

    onStatus?.call('מכין את הקובץ...');
    String? path;
    List<int>? bytes;
    if (kIsWeb) {
      final url = m.remoteUrl;
      if (url == null) throw Exception('בדפדפן אפשר לתמלל רק קבצים שהועלו ל-GitHub');
      onStatus?.call('מוריד את הקובץ...');
      final r = await http.get(Uri.parse(url));
      if (r.statusCode != 200) throw Exception('הורדת הקובץ נכשלה (${r.statusCode})');
      bytes = r.bodyBytes;
    } else {
      path = await MediaResolver.ensureLocal(m, onProgress: (g, t) {
        if (t != null) onStatus?.call('מוריד את הקובץ... ${(g * 100 ~/ t)}%');
      });
      if (path == null) throw Exception('לא נמצא קובץ שמע');
    }
    final size = bytes?.length ?? localFileSize(path) ?? 0;
    if (size == 0) throw Exception('קובץ השמע ריק');

    Future<List<int>> range(int s, int e) async =>
        bytes != null ? bytes.sublist(s, e) : await readLocalRange(path!, s, e);

    if (cfg.provider.id == 'soniox') {
      onStatus?.call('מתחבר ל־Soniox...');
      return _transcribeSoniox(cfg, size, range, onStatus);
    }

    if (size <= chunkBytes) {
      onStatus?.call('מתמלל...');
      final r = await _send(cfg, await range(0, size), name);
      return r.segs;
    }

    if (ext != 'mp3') {
      throw Exception('קבצים מעל 20MB נתמכים לתמלול בפורמט MP3 בלבד. '
          'המר את הקובץ ל-MP3 (למשל באפליקציה חינמית) ונסה שוב.');
    }

    final head = await range(0, size < 65536 ? size : 65536);
    final header = findMp3Header(head);
    final out = <Seg>[];
    var start = 0, offsetMs = 0, part = 1;
    final parts = (size / chunkBytes).ceil();
    while (start < size) {
      var end = start + chunkBytes;
      if (end >= size) {
        end = size;
      } else {
        // חותכים בתחילת פריים כדי שכל חלק יהיה קובץ MP3 תקין
        final window = await range(end, end + 8192 > size ? size : end + 8192);
        final sync = findFrameSync(window, 0);
        if (sync != null) end += sync;
      }
      onStatus?.call('מתמלל חלק $part מתוך $parts...');
      final chunk = await range(start, end);
      final r = await _send(cfg, chunk, 'part$part.mp3');
      out.addAll(r.segs.map((s) => Seg(s.ms + offsetMs, s.text)));
      final estimated = header != null && header.bitrate > 0 ? (chunk.length * 8 * 1000 / header.bitrate).round() : 0;
      offsetMs += r.durationMs ?? estimated;
      start = end;
      part++;
    }
    return out;
  }

  static Future<List<Seg>> _transcribeSoniox(
    _Cfg cfg,
    int size,
    Future<List<int>> Function(int start, int end) readRange,
    void Function(String status)? onStatus,
  ) async {
    final socket = WebSocketChannel.connect(
      Uri.parse(cfg.endpoint),
      protocols: ['soniox-api-key', cfg.key],
    );
    final segments = <Seg>[];
    var lastMs = 0;
    try {
      await socket.ready;
      socket.sink.add(jsonEncode({
        'model': cfg.model,
        'audio_format': 'auto',
        'language_hints': [language],
        'enable_endpoint_detection': true,
      }));

      const frameBytes = 256 * 1024;
      var sent = 0;
      while (sent < size) {
        final end = sent + frameBytes > size ? size : sent + frameBytes;
        socket.sink.add(Uint8List.fromList(await readRange(sent, end)));
        sent = end;
        onStatus?.call('שולח אודיו... ${(sent * 100 ~/ size)}%');
      }
      socket.sink.add('');

      await for (final message in socket.stream.timeout(const Duration(minutes: 15))) {
        if (message is! String || message.isEmpty) continue;
        final decoded = jsonDecode(message);
        if (decoded is! Map) continue;
        if (decoded['error_code'] != null) {
          final code = decoded['error_code'].toString();
          final detail = decoded['error_message']?.toString() ?? 'שגיאה';
          throw Exception(_friendlyProviderError(code, detail));
        }
        final tokens = decoded['tokens'];
        if (tokens is List) {
          for (final token in tokens) {
            if (token is! Map || token['translation_status'] == 'translation') continue;
            if (token['is_final'] == false) continue; // רק טוקנים סופיים – אחרת יש כפילויות
            final text = token['text']?.toString() ?? '';
            if (text.isEmpty || text == '<end>') continue;
            final ms = (token['start_ms'] as num?)?.round() ?? 0;
            // Soniox מחזיר חלקי מילים – מאחדים למשפטים: סוף משפט, הפסקה או שורה ארוכה
            final startNew = segments.isEmpty ||
                RegExp(r'[.?!:]\s*$').hasMatch(segments.last.text) ||
                ms - lastMs > 1500 ||
                (segments.last.text.length > 120 && text.startsWith(' '));
            if (startNew) {
              segments.add(Seg(ms, text.trimLeft()));
            } else {
              segments.last.text += text;
            }
            lastMs = (token['end_ms'] as num?)?.round() ?? ms;
          }
        }
        if (decoded['finished'] == true) break;
      }
      for (final seg in segments) {
        seg.text = seg.text.trim();
      }
      return segments.where((x) => x.text.isNotEmpty).toList();
    } finally {
      await socket.sink.close();
    }
  }

  /// שנייה של שקט (WAV 8kHz מונו) לבדיקת חיבור
  static List<int> _silentWav() {
    const rate = 8000, n = 8000;
    final b = BytesBuilder();
    void u32(int v) => b.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
    void u16(int v) => b.add([v & 255, (v >> 8) & 255]);
    b.add('RIFF'.codeUnits);
    u32(36 + n * 2);
    b.add('WAVEfmt '.codeUnits);
    u32(16);
    u16(1);
    u16(1);
    u32(rate);
    u32(rate * 2);
    u16(2);
    u16(16);
    b.add('data'.codeUnits);
    u32(n * 2);
    b.add(List<int>.filled(n * 2, 0));
    return b.toBytes();
  }

  /// הסבר ברור בעברית לשגיאת 429 – מבחין בין חוסר יתרה, מגבלת הוצאה ועומס בקשות
  static String explain429(String body, Map<String, String> headers, String providerLabel) {
    String code = '', type = '', message = '';
    try {
      final j = jsonDecode(body);
      final e = j is Map ? (j['error'] ?? j) : null;
      if (e is Map) {
        code = e['code']?.toString() ?? '';
        type = e['type']?.toString() ?? '';
        message = e['message']?.toString() ?? '';
      }
    } catch (_) {}
    final all = '$code $type $message $body'.toLowerCase();
    if (all.contains('billing_hard_limit') || all.contains('hard limit') || all.contains('spend limit') ||
        all.contains('budget') || all.contains('usage limit')) {
      return 'שגיאה 429 – הגעת למגבלת ההוצאה החודשית שהוגדרה בחשבון ($providerLabel). '
          'יש להיכנס ל-platform.openai.com ← Settings ← Limits ולהעלות את המגבלה (Monthly budget), ואז לנסות שוב.';
    }
    if (all.contains('insufficient_quota') || all.contains('exceeded your current quota') || all.contains('credit')) {
      return 'שגיאה 429 – אין יתרה בחשבון ($providerLabel, insufficient_quota). '
          'ה-API עובד רק עם יתרה בתשלום מראש: platform.openai.com ← Settings ← Billing ← Add credit. '
          'מנוי ChatGPT Plus אינו כולל שימוש ב-API. אחרי טעינת יתרה ייתכן שיידרשו כמה דקות.';
    }
    final retry = headers['retry-after'] ?? headers['x-ratelimit-reset-requests'] ?? headers['x-ratelimit-reset-tokens'];
    final kind = all.contains('tokens') ? 'טוקנים' : 'בקשות';
    return 'שגיאה 429 – עומס: נשלחו יותר מדי $kind בזמן קצר ($providerLabel). '
        '${retry != null ? 'אפשר לנסות שוב בעוד $retry. ' : 'המתן דקה ונסה שוב. '}'
        'אם זה חוזר – בדוק את רמת החשבון (Usage tier) ומגבלות הקצב ב-Limits.';
  }

  static String _friendlyProviderError(String code, String detail) {
    if (code == '402' || detail.toLowerCase().contains('balance')) {
      return 'אין יתרה או שהחיוב אצל ספק התמלול חסום (402). הוסף כספים או הפעל חיוב אוטומטי בחשבון הספק.';
    }
    if (code == '429') return explain429(detail, const {}, 'Soniox');
    if (code == '401' || code == '403') return 'מפתח התמלול שגוי או שאין לו הרשאה.';
    return 'Soniox החזיר שגיאה $code: $detail';
  }

  static Future<({List<Seg> segs, int? durationMs})> _send(_Cfg cfg, List<int> bytes, String filename) async {
    Future<http.Response> post(String format) async {
      final req = http.MultipartRequest('POST', Uri.parse(cfg.endpoint));
      if (cfg.key.isNotEmpty) req.headers['Authorization'] = 'Bearer ${cfg.key}';
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      req.fields['model'] = cfg.model;
      req.fields['response_format'] = format;
      if (language.isNotEmpty) req.fields['language'] = language;
      return http.Response.fromStream(await req.send().timeout(const Duration(minutes: 10)));
    }

    final verbose = !cfg.model.startsWith('gpt-');
    var res = await post(verbose ? 'verbose_json' : 'json');
    if (res.statusCode == 400 || res.statusCode == 422) res = await post('json');
    if (res.statusCode == 401 || res.statusCode == 403) throw Exception('מפתח ה-API שגוי, חסר או שאין לו הרשאה לתמלול');
    if (res.statusCode == 402) throw Exception('החיוב של ספק התמלול חסום או שאין יתרה בחשבון. יש להוסיף אמצעי תשלום/יתרה בלוח הבקרה של הספק.');
    if (res.statusCode == 429) {
      throw Exception(explain429(utf8.decode(res.bodyBytes, allowMalformed: true), res.headers, cfg.provider.label));
    }
    if (res.statusCode == 413) throw Exception('השרת דחה את הקובץ כי הוא גדול מדי');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('שירות התמלול החזיר שגיאה ${res.statusCode}');
    }
    // חשוב: פענוח UTF-8 מפורש, אחרת עברית עלולה להשתבש
    final body = utf8.decode(res.bodyBytes);
    final decoded = jsonDecode(body);
    if (decoded is! Map) return (segs: [Seg(0, body.trim())], durationMs: null);

    final durationMs = decoded['duration'] is num ? ((decoded['duration'] as num) * 1000).round() : null;
    final segments = decoded['segments'];
    if (segments is List && segments.isNotEmpty) {
      final segs = <Seg>[
        for (final s in segments)
          if ((s['text'] ?? '').toString().trim().isNotEmpty)
            Seg((((s['start'] as num?) ?? 0) * 1000).round(), s['text'].toString().trim()),
      ];
      return (segs: segs, durationMs: durationMs);
    }
    final text = decoded['text']?.toString().trim() ?? '';
    if (text.isEmpty) throw Exception('לא התקבל תמלול');
    return (segs: [Seg(0, text)], durationMs: durationMs);
  }
}
