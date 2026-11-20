import 'dart:convert';

import '../models/lesson.dart';

/// פענוח קובץ טקסט מכל קידוד נפוץ ב-Windows, בלי לשנות אף אות:
/// UTF-8 (עם/בלי BOM), UTF-16 LE/BE, ו-Windows-1255 (עברית ישנה של פנקס רשימות / Word).
String decodeTextBytes(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return _utf16(bytes.sublist(2), little: true);
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return _utf16(bytes.sublist(2), little: false);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return decodeWindows1255(bytes);
  }
}

String _utf16(List<int> b, {required bool little}) {
  final units = <int>[];
  for (var i = 0; i + 1 < b.length; i += 2) {
    units.add(little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// טבלת Windows-1255 (0x80–0xFF). 0 = לא מוגדר.
const _cp1255 = <int>[
  0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0, 0x2039, 0, 0, 0, 0, //
  0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0, 0x203A, 0, 0, 0, 0, //
  0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x20AA, 0x00A5, 0x00A6, 0x00A7, 0x00A8, 0x00A9, 0x00D7, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, //
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, 0x00B8, 0x00B9, 0x00F7, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF, //
  0x05B0, 0x05B1, 0x05B2, 0x05B3, 0x05B4, 0x05B5, 0x05B6, 0x05B7, 0x05B8, 0x05B9, 0x05BA, 0x05BB, 0x05BC, 0x05BD, 0x05BE, 0x05BF, //
  0x05C0, 0x05C1, 0x05C2, 0x05C3, 0x05F0, 0x05F1, 0x05F2, 0x05F3, 0x05F4, 0, 0, 0, 0, 0, 0, 0, //
  0x05D0, 0x05D1, 0x05D2, 0x05D3, 0x05D4, 0x05D5, 0x05D6, 0x05D7, 0x05D8, 0x05D9, 0x05DA, 0x05DB, 0x05DC, 0x05DD, 0x05DE, 0x05DF, //
  0x05E0, 0x05E1, 0x05E2, 0x05E3, 0x05E4, 0x05E5, 0x05E6, 0x05E7, 0x05E8, 0x05E9, 0x05EA, 0, 0, 0x200E, 0x200F, 0, //
];

String decodeWindows1255(List<int> bytes) {
  final b = StringBuffer();
  for (final x in bytes) {
    if (x < 0x80) {
      b.writeCharCode(x);
    } else {
      final cp = _cp1255[x - 0x80];
      b.writeCharCode(cp == 0 ? 0xFFFD : cp);
    }
  }
  return b.toString();
}

/// קטע כתובית עם התחלה וסוף (סוף 0 = עד הקטע הבא)
typedef Cue = ({int start, int end, String text});

final _srtTime = RegExp(r'(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})');
final _vttShort = RegExp(r'^(\d{1,2}):(\d{2})[.,](\d{1,3})');
final _lrcTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

int _ms(String frac) => int.parse(frac.padRight(3, '0').substring(0, 3));

int? _parseCueTime(String s) {
  s = s.trim();
  final m = _srtTime.firstMatch(s);
  if (m != null) {
    return ((int.parse(m[1]!) * 60 + int.parse(m[2]!)) * 60 + int.parse(m[3]!)) * 1000 + _ms(m[4]!);
  }
  final v = _vttShort.firstMatch(s);
  if (v != null) return (int.parse(v[1]!) * 60 + int.parse(v[2]!)) * 1000 + _ms(v[3]!);
  return null;
}

/// מזהה האם הטקסט הוא קובץ כתוביות מתוזמן (SRT / VTT / LRC)
bool looksTimed(String text) =>
    text.contains('-->') || RegExp(r'^\s*\[\d{1,3}:\d{1,2}', multiLine: true).hasMatch(text);

/// פענוח SRT / VTT / LRC. טקסט רגיל מחזיר רשימה ריקה.
List<Cue> parseSubtitles(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final out = <Cue>[];
  if (text.contains('-->')) {
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('-->')) continue;
      final parts = lines[i].split('-->');
      final s = _parseCueTime(parts[0]);
      final e = _parseCueTime(parts[1].trim().split(RegExp(r'\s+')).first);
      if (s == null) continue;
      final buf = <String>[];
      var j = i + 1;
      while (j < lines.length && lines[j].trim().isNotEmpty && !lines[j].contains('-->')) {
        buf.add(lines[j].replaceAll(RegExp(r'<[^>]+>'), ''));
        j++;
      }
      // שורה אחרונה שהיא מספר של הכתובית הבאה (SRT)
      if (buf.isNotEmpty && j < lines.length && lines[j].contains('-->') && RegExp(r'^\d+$').hasMatch(buf.last.trim())) {
        buf.removeLast();
      }
      out.add((start: s, end: e ?? 0, text: buf.join('\n')));
      i = j - 1;
    }
    return out;
  }
  for (final line in lines) {
    final tags = _lrcTag.allMatches(line).toList();
    if (tags.isEmpty) continue;
    final body = line.substring(tags.last.end).trim();
    for (final t in tags) {
      final ms = (int.parse(t[1]!) * 60 + int.parse(t[2]!)) * 1000 + (t[3] == null ? 0 : _ms(t[3]!));
      out.add((start: ms, end: 0, text: body));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _three(int n) => n.toString().padLeft(3, '0');

String _clock(int ms, String sep) {
  final h = ms ~/ 3600000, m = (ms ~/ 60000) % 60, s = (ms ~/ 1000) % 60;
  return '${_two(h)}:${_two(m)}:${_two(s)}$sep${_three(ms % 1000)}';
}

int _endOf(List<Seg> segs, int i, int? totalMs) {
  if (i + 1 < segs.length && segs[i + 1].ms > segs[i].ms) return segs[i + 1].ms;
  final t = totalMs ?? 0;
  return t > segs[i].ms ? t : segs[i].ms + 4000;
}

String toTxt(List<Seg> segs, {bool withTimes = true}) => segs
    .map((s) => withTimes ? '[${_clock(s.ms, '.').substring(0, 8)}] ${s.text}' : s.text)
    .join('\r\n');

String toSrt(List<Seg> segs, {int? totalMs}) {
  final b = StringBuffer();
  for (var i = 0; i < segs.length; i++) {
    b
      ..write('${i + 1}\r\n')
      ..write('${_clock(segs[i].ms, ',')} --> ${_clock(_endOf(segs, i, totalMs), ',')}\r\n')
      ..write('${segs[i].text}\r\n\r\n');
  }
  return b.toString();
}

String toVtt(List<Seg> segs, {int? totalMs}) {
  final b = StringBuffer('WEBVTT\n\n');
  for (var i = 0; i < segs.length; i++) {
    b
      ..write('${_clock(segs[i].ms, '.')} --> ${_clock(_endOf(segs, i, totalMs), '.')}\n')
      ..write('${segs[i].text}\n\n');
  }
  return b.toString();
}

String toLrc(List<Seg> segs, {String? title}) {
  final b = StringBuffer();
  if (title != null && title.isNotEmpty) b.write('[ti:$title]\n');
  for (final s in segs) {
    final m = s.ms ~/ 60000, sec = (s.ms ~/ 1000) % 60, cs = (s.ms % 1000) ~/ 10;
    b.write('[${_two(m)}:${_two(sec)}.${_two(cs)}]${s.text.replaceAll('\n', ' ')}\n');
  }
  return b.toString();
}

/// פיצול קטעים ארוכים לפי מגבלת מילים, תוך חלוקת הזמן לפי מספר המילים.
/// הטקסט עצמו לא משתנה – רק מתחלק בין קטעים (בנקודות רווח).
List<Seg> splitByWordLimit(List<Seg> segs, int maxWords, {int? totalMs}) {
  if (maxWords <= 0) return segs;
  final out = <Seg>[];
  for (var i = 0; i < segs.length; i++) {
    final parts = RegExp(r'\S+\s*').allMatches(segs[i].text).map((m) => m[0]!).toList();
    if (parts.length <= maxWords) {
      out.add(Seg(segs[i].ms, segs[i].text));
      continue;
    }
    final start = segs[i].ms, end = _endOf(segs, i, totalMs);
    for (var w = 0; w < parts.length; w += maxWords) {
      final chunk = parts.sublist(w, w + maxWords > parts.length ? parts.length : w + maxWords).join();
      out.add(Seg(start + ((end - start) * w / parts.length).round(), chunk.trimRight()));
    }
  }
  return out;
}
