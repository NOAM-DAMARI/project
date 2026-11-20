import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/models/singer.dart';
import 'package:music_manager/screens/zip_import_dialog.dart';
import 'package:music_manager/services/app_state.dart';
import 'package:music_manager/services/folder_tools.dart';

Future<void> _openDialog(
  WidgetTester tester,
  List<ZipEntry> entries,
  void Function(List<ZipImportSelection>?) onResult, {
  ZipImportTarget defaultTarget = ZipImportTarget.lesson,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
        builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    onResult(await showDialog<List<ZipImportSelection>>(
                      context: context,
                      builder: (_) => ZipImportDialog(
                          entries: entries, defaultTarget: defaultTarget),
                    ));
                  },
                  child: const Text('פתח ZIP'),
                ),
              ),
            )),
  ));
  await tester.tap(find.text('פתח ZIP'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ZIP table edits lesson data and skips selected rows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const entries = [
      ZipEntry(path: 'audio/lesson.mp3', size: 512),
      ZipEntry(path: 'notes/readme.txt', size: 32),
    ];
    List<ZipImportSelection>? result;
    await _openDialog(tester, entries, (value) => result = value);
    expect(find.text('שם הקובץ'), findsOneWidget);
    expect(find.text('lesson.mp3'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('zip-title-audio/lesson.mp3')),
      'שיעור לדוגמה',
    );
    await tester.enterText(
      find.byKey(const ValueKey('zip-number-audio/lesson.mp3')),
      '42',
    );
    await tester.enterText(
      find.byKey(const ValueKey('zip-parasha-audio/lesson.mp3')),
      'בר מצווה',
    );
    await tester.enterText(
      find.byKey(const ValueKey('zip-notes-audio/lesson.mp3')),
      'הערה לדוגמה',
    );
    final kindDropdown =
        find.byKey(const ValueKey('zip-kind-audio/lesson.mp3'));
    await tester.ensureVisible(kindDropdown);
    await tester.pumpAndSettle();
    await tester.tap(kindDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('אירוע').last);
    await tester.pumpAndSettle();
    final skip = find.byKey(const ValueKey('zip-skip-notes/readme.txt'));
    await tester.ensureVisible(skip);
    await tester.pumpAndSettle();
    await tester.tap(skip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ייבא 1 קבצים'));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    final selection = result!.single;
    expect(selection.path, 'audio/lesson.mp3');
    // ברירת המחדל: נשמר כשיעור (ולא כ״לא משויך״)
    expect(selection.target, ZipImportTarget.lesson);
    expect(selection.title, 'שיעור לדוגמה');
    expect(selection.number, 42);
    expect(selection.parasha, 'בר מצווה');
    expect(selection.parashaKind, 'event');
    expect(selection.notes, 'הערה לדוגמה');
    expect(selection.date, isNotNull);
    expect(selection.dateKind, 'g');
  });

  testWidgets('song rows keep singer, year and location', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    app.singers
      ..clear()
      ..add(Singer(id: 'singer-1', name: 'זמר לדוגמה'));
    addTearDown(() => app.singers.clear());

    const entries = [ZipEntry(path: 'songs/one.mp3', size: 256)];
    List<ZipImportSelection>? result;
    await _openDialog(tester, entries, (value) => result = value,
        defaultTarget: ZipImportTarget.song);

    await tester.enterText(
        find.byKey(const ValueKey('zip-title-songs/one.mp3')), 'שיר לדוגמה');
    await tester.enterText(
        find.byKey(const ValueKey('zip-year-songs/one.mp3')), '1999');
    await tester.enterText(
        find.byKey(const ValueKey('zip-location-songs/one.mp3')), 'ירושלים');
    await tester.tap(find.text('ייבא 1 קבצים'));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    final selection = result!.single;
    expect(selection.target, ZipImportTarget.song);
    expect(selection.title, 'שיר לדוגמה');
    // זמר יחיד ברשימה נבחר אוטומטית
    expect(selection.singerId, 'singer-1');
    expect(selection.year, 1999);
    expect(selection.location, 'ירושלים');
    expect(selection.number, isNull);
  });
}
