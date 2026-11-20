import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/models/lesson.dart';
import 'package:music_manager/services/media_download.dart';

void main() {
  test('download uses the original file name, not the technical GitHub name',
      () {
    final lesson = Lesson(id: '1', title: 'כותרת')
      ..fileName = 'שיעור 12 - בראשית.mp3'
      ..remoteUrl =
          'https://raw.githubusercontent.com/o/r/main/media/media_songs_1794258587101_11_-_________.mp3';
    expect(originalDownloadName(lesson, fallbackTitle: lesson.title),
        'שיעור 12 - בראשית.mp3');
  });

  test('falls back to the title and the extension of the stored file', () {
    final lesson = Lesson(id: '2', title: 'שיעור: א/ב')
      ..remoteUrl = 'https://example.com/media/lessons_1_____.wav?raw=1';
    expect(originalDownloadName(lesson, fallbackTitle: lesson.title),
        'שיעור א ב.wav');
  });

  test('adds a default extension when the stored name has none', () {
    final lesson = Lesson(id: '3', title: 'x')..fileName = 'הקלטה';
    expect(originalDownloadName(lesson), 'הקלטה.mp3');
  });

  test('mime type follows the extension', () {
    expect(mimeForFileName('a.mp3'), 'audio/mpeg');
    expect(mimeForFileName('a.WAV'), 'audio/wav');
  });
}
