import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/models/lesson.dart';
import 'package:music_manager/services/transcript_compare.dart';

void main() {
  test('identical transcripts are 100% similar', () {
    final a = [Seg(0, 'שלום לכם חברים'), Seg(5000, 'היום נלמד')];
    final r = compareTranscripts(a, a);
    expect(r.similarity, 100);
    expect(r.rows.every((x) => x.diffCount == 0), true);
  });

  test('differing words are marked, niqqud and punctuation ignored', () {
    final a = [Seg(0, 'שָׁלוֹם לכם, חברים')];
    final b = [Seg(0, 'שלום לכן חברים')];
    final r = compareTranscripts(a, b);
    expect(r.rows.single.a.map((w) => w.same).toList(), [true, false, true]);
    expect(r.rows.single.b.map((w) => w.same).toList(), [true, false, true]);
    expect(r.matched, 2);
  });

  test('lesson keeps several transcripts through save/load', () {
    final l = Lesson(id: '1', title: 't')
      ..transcripts = [TranscriptVersion(id: 'v1', providerId: 'groq', label: 'Groq', segs: [Seg(0, 'א')])];
    final back = Lesson.fromJson(jsonDecode(jsonEncode(l.toJson())) as Map);
    expect(back.transcripts.single.providerId, 'groq');
  });
}
