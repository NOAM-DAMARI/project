import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/models/lesson.dart';
import 'package:music_manager/services/points.dart';
import 'package:music_manager/services/text_aligner.dart';

void main() {
  test('alignment keeps every letter of the source text', () {
    final transcript = [Seg(0, 'שלום לכם חברים'), Seg(5000, 'היום נלמד על שבת'), Seg(12000, 'וזה סוף השיעור')];
    const text = 'שָׁלוֹם לָכֶם, חברים!\nהיום נלמד על שבת.\nוזה סוף השיעור';
    final out = TextAligner.align(text, transcript);
    expect(out.map((e) => e.text).join('\n'), text);
    expect(out.map((e) => e.ms).toList(), [0, 5000, 12000]);
  });

  test('final letters and punctuation are ignored when matching', () {
    expect(TextAligner.norm('שלום,'), TextAligner.norm('שלומ'));
  });

  test('clock parsing in 00:00 format', () {
    expect(parseClock('01:30'), 90000);
    expect(parseClock('1:02:03'), 3723000);
    expect(parseClock('5'), 300000);
    expect(parseClock('1:75'), null);
  });

  test('point helpers keep lists in sync', () {
    final l = Lesson(id: '1', title: 't');
    final i = l.addPoint(title: 'a', note: 'n', startMs: 1000, endMs: 3000);
    expect(l.pointEnd(i), 3000);
    l.updatePoint(i, endMs: 0);
    expect(l.pointEnd(i), 1000 + 5 * 60 * 1000);
    l.removePoint(i);
    expect([l.points.length, l.pointNotes.length, l.pointTimes.length, l.pointEnds.length], [0, 0, 0, 0]);
  });
}
