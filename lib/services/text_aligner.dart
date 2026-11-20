import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/lesson.dart';
import 'subtitle_formats.dart';

/// התאמת טקסט חופשי לזמני תמלול קיים – בלי לשנות אף אות בטקסט המקור.
///
/// ההשוואה סלחנית: מתעלמת מניקוד וטעמים, סימני פיסוק, אותיות סופיות,
/// ומאפשרת שגיאת אות אחת במילים ארוכות. ההתאמה מונוטונית (הטקסט מתקדם רק קדימה בזמן),
/// כך שגם קטעים שלא זוהו מקבלים זמן משוער בין השכנים שלהם.
class TextAligner {
  static final _niqqud = RegExp(r'[\u0591-\u05C7]');
  static final _punct = RegExp(r'''[^\p{L}\p{N}]''', unicode: true);
  static const _finals = {'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'};

  static String norm(String w) {
    var s = w.toLowerCase().replaceAll(_niqqud, '').replaceAll(_punct, '');
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(_finals[ch] ?? ch);
    }
    return b.toString();
  }

  static const _prefixes = 'והבלמשכ';

  static String _stripPrefix(String w) =>
      w.length > 3 && _prefixes.contains(w[0]) ? w.substring(1) : w;

  /// מרחק עריכה (Levenshtein) עם עצירה מוקדמת מעל [max]
  static int _dist(String a, String b, int max) {
    if ((a.length - b.length).abs() > max) return max + 1;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > max) return max + 1;
      prev = cur;
    }
    return prev[b.length];
  }

  /// השוואה סלחנית: זהות, תחילית עברית (ו/ה/ב/ל/מ/ש/כ), ושגיאות כתיב לפי אורך המילה
  static bool _similar(String a, String b) {
    if (a == b) return true;
    final sa = _stripPrefix(a), sb = _stripPrefix(b);
    if (sa == sb || sa == b || a == sb) return true;
    final len = a.length < b.length ? a.length : b.length;
    if (len < 4) return false;
    final max = len >= 7 ? 2 : 1;
    return _dist(a, b, max) <= max;
  }

  /// מחזיר שורה לכל שורה לא ריקה בטקסט, עם זמן התחלה מדויק ככל האפשר.
  static List<Seg> align(String text, List<Seg> transcript, {int? totalMs}) {
    // השורות נשמרות בדיוק כפי שהן (כולל רווחים וסימנים) – רק שורות ריקות לגמרי מדולגות
    final lines = text.split(RegExp(r'\r\n|\n|\r')).where((e) => e.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];
    if (transcript.isEmpty) return [for (final l in lines) Seg(0, l)];

    // מילים מהתמלול עם זמן משוער לכל מילה (פריסה לינארית בתוך הקטע)
    final tWords = <String>[];
    final tTimes = <int>[];
    final lastMs = totalMs ?? (transcript.last.ms + 4000);
    for (var k = 0; k < transcript.length; k++) {
      final start = transcript[k].ms;
      final end = k + 1 < transcript.length ? transcript[k + 1].ms : lastMs;
      final words = transcript[k].text.split(RegExp(r'\s+')).map(norm).where((w) => w.isNotEmpty).toList();
      for (var w = 0; w < words.length; w++) {
        tWords.add(words[w]);
        tTimes.add(start + ((end - start) * w / words.length).round());
      }
    }
    if (tWords.isEmpty) return [for (final l in lines) Seg(0, l)];

    final lineTimes = List<int?>.filled(lines.length, null);
    var j = 0;
    var misses = 0;
    for (var li = 0; li < lines.length; li++) {
      final words = lines[li].split(RegExp(r'\s+')).map(norm).where((w) => w.isNotEmpty).toList();
      for (var wi = 0; wi < words.length; wi++) {
        final w = words[wi];
        // חלון חיפוש מתרחב ככל שמצטברות החטאות – כך מתאוששים מקטעים שלא תומללו
        final window = misses > 40 ? 2000 : (misses > 15 ? 600 : 120);
        var found = -1;
        for (var k = j; k < tWords.length && k < j + window; k++) {
          if (_similar(w, tWords[k])) {
            // בחלון רחב דורשים אישור מהמילה הבאה כדי לא לקפוץ למקום שגוי
            if (window > 120 && wi + 1 < words.length && k + 1 < tWords.length && !_similar(words[wi + 1], tWords[k + 1])) {
              continue;
            }
            found = k;
            break;
          }
        }
        if (found >= 0) {
          // אם המילה הראשונה לא זוהתה – מחסירים זמן משוער למילים שקדמו לה (~350ms למילה)
          if (lineTimes[li] == null) {
            final est = tTimes[found] - wi * 350;
            final floor = li > 0 && lineTimes[li - 1] != null ? lineTimes[li - 1]! : 0;
            lineTimes[li] = est < floor ? floor : est;
          }
          j = found + 1;
          misses = 0;
        } else {
          misses++;
        }
      }
    }

    // השלמת שורות שלא זוהו: אינטרפולציה בין השכנים
    final result = <Seg>[];
    for (var li = 0; li < lines.length; li++) {
      var t = lineTimes[li];
      if (t == null) {
        var prev = li - 1;
        while (prev >= 0 && lineTimes[prev] == null) {
          prev--;
        }
        var next = li + 1;
        while (next < lines.length && lineTimes[next] == null) {
          next++;
        }
        final a = prev >= 0 ? lineTimes[prev]! : 0;
        final b = next < lines.length ? lineTimes[next]! : lastMs;
        final pa = prev >= 0 ? prev : -1;
        final pb = next < lines.length ? next : lines.length;
        t = a + ((b - a) * (li - pa) / (pb - pa)).round();
      }
      if (result.isNotEmpty && t < result.last.ms) t = result.last.ms;
      result.add(Seg(t, lines[li]));
    }
    return result;
  }
}

/// חלון קבלת טקסט: הדבקה או בחירת קובץ txt. מחזיר את הטקסט כפי שהוא.
Future<String?> askTextForAlignment(BuildContext context, {String title = 'העלאת טקסט וסידור לפי זמנים'}) async {
  final ctl = TextEditingController();
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('הדבק את הטקסט המדויק (שורה לכל קטע) או בחר קובץ. הטקסט יישמר אות באות, רק יקבל זמנים.'),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(hintText: 'הדבק כאן טקסט...', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('בחירת קובץ טקסט'),
              onPressed: () async {
                final r = await FilePicker.platform
                    .pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'md', 'srt', 'vtt', 'lrc'], withData: true);
                final bytes = r?.files.firstOrNull?.bytes;
                if (bytes != null) ctl.text = decodeTextBytes(bytes);
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('סידור לפי זמנים')),
      ],
    ),
  );
  ctl.dispose();
  if (res == null || res.trim().isEmpty) return null;
  return res;
}
