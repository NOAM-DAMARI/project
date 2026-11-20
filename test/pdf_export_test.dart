import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/models/lesson.dart';
import 'package:music_manager/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lesson PDF builds with number, name and Hebrew date', () async {
    final lesson = Lesson(
        id: '1', title: 'שיעור לדוגמה', summary: 'סיכום 123', date: DateTime(2026, 11, 12))
      ..number = 1234;
    final bytes = await buildLessonPdf(lesson);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('lessons table has number, name and Hebrew date columns', () async {
    final lesson =
        Lesson(id: '1', title: 'שיעור א', date: DateTime(2026, 11, 12))
          ..number = 7;
    final rows = lessonTableRows([lesson]);
    expect(rows.single.number, '7');
    expect(rows.single.name, 'שיעור א');
    expect(rows.single.hebrewDate, isNotEmpty);
    final bytes = await buildNumberNameDatePdf(rows);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
