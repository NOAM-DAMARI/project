import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/models/lesson.dart';
import 'package:music_manager/services/subtitle_formats.dart';

void main() {
  test('imports timed SRT captions without changing Hebrew text', () {
    final source = '1\r\n00:00:01,250 --> 00:00:02,500\r\nשלום עולם\r\n\r\n';
    final cues = parseSubtitles(decodeTextBytes(utf8.encode(source)));

    expect(cues, hasLength(1));
    expect(cues.single.start, 1250);
    expect(cues.single.end, 2500);
    expect(cues.single.text, 'שלום עולם');
  });

  test('imports WebVTT and LRC timestamps', () {
    final vtt =
        parseSubtitles('WEBVTT\n\n00:00:03.000 --> 00:00:04.000\nשיעור\n');
    final lrc = parseSubtitles('[00:05.20]שורה ראשונה\n[00:08.00]שורה שנייה');

    expect(vtt.single.start, 3000);
    expect(vtt.single.text, 'שיעור');
    expect(lrc.map((cue) => cue.start), [5200, 8000]);
  });

  test('preserves custom event category when a lesson is saved', () {
    final lesson = Lesson(id: 'event-1', title: 'שמחה')
      ..parasha = 'בר מצווה'
      ..parashaKind = 'event';
    final restored = Lesson.fromJson(lesson.toJson());

    expect(restored.parasha, 'בר מצווה');
    expect(restored.parashaKind, 'event');
  });
}
