import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_manager/models/lesson.dart';
import 'package:music_manager/models/lesson_import_info.dart';
import 'package:music_manager/models/unassigned_media.dart';
import 'package:music_manager/services/app_state.dart';
import 'package:music_manager/services/file_service.dart';
import 'package:music_manager/services/folder_tools.dart';
import 'package:music_manager/services/storage_provider.dart';
import 'package:music_manager/services/zip_bytes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('unassigned files', () {
    late Directory directory;
    late AppState state;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      directory =
          await Directory.systemTemp.createTemp('lesson-manager-files-');
      state = AppState();
      await state.load();
      await state.configureLocalFolder(directory.path);
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('removes media referenced by a lesson from the unassigned list',
        () async {
      final file = File('${directory.path}/inbox/lesson.mp3')
        ..createSync(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
      expect((await state.freeMediaFiles()).map((item) => item.name),
          ['lesson.mp3']);

      final lesson = Lesson(id: 'lesson-1', title: 'Lesson')
        ..filePath = file.path
        ..fileName = 'lesson.mp3';
      state.lessons.add(lesson);

      expect(await state.freeMediaFiles(), isEmpty);
    });
  });

  test('storage snapshots preserve their last-write timestamp', () {
    final timestamp = DateTime.utc(2026, 11, 12, 10, 30);
    final snapshot = StorageSnapshot.fromRaw(
        '{"_updatedAt":"${timestamp.toIso8601String()}"}');
    expect(snapshot.updatedAt, timestamp);
  });

  test(
      'ZIP preview filters unsupported and unsafe entries, then extracts only selected files',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('lesson-manager-zip-');
    try {
      final archive = Archive();
      final audio = [1, 2, 3, 4];
      archive.addFile(ArchiveFile('audio/lesson.mp3', audio.length, audio));
      archive.addFile(ArchiveFile('notes/readme.txt', 2, [5, 6]));
      archive.addFile(ArchiveFile('program.exe', 2, [7, 8]));
      archive.addFile(ArchiveFile('../escape.mp3', 2, [9, 10]));
      final zipBytes = ZipEncoder().encode(archive);
      final zip = File('${directory.path}/import.zip')
        ..writeAsBytesSync(zipBytes);

      final entries = await listImportableZipEntries(zip.path, importExts);
      expect(entries.map((entry) => entry.path).toSet(),
          {'audio/lesson.mp3'});

      final count = await extractSelectedZipEntries(
        directory.path,
        zip.path,
        {'audio/lesson.mp3'},
        sub: 'inbox/import',
      );

      expect(count, 1);
      expect(
          await File('${directory.path}/inbox/import/audio/lesson.mp3')
              .readAsBytes(),
          audio);
      expect(
          File('${directory.path}/inbox/import/notes/readme.txt').existsSync(),
          isFalse);
      expect(File('${directory.path}/escape.mp3').existsSync(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('ZIP byte import filters unsafe paths and extracts selected files only',
      () {
    final archive = Archive()
      ..addFile(ArchiveFile('audio/lesson.mp3', 3, [1, 2, 3]))
      ..addFile(ArchiveFile('../escape.mp3', 2, [8, 9]))
      ..addFile(ArchiveFile('setup.exe', 2, [4, 5]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    final entries = listImportableZipEntriesFromBytes(bytes, importExts);
    expect(entries.map((entry) => entry.path), ['audio/lesson.mp3']);
    final selected =
        extractSelectedZipEntriesFromBytes(bytes, {'audio/lesson.mp3'});
    expect(selected.keys, ['audio/lesson.mp3']);
    expect(selected['audio/lesson.mp3'], [1, 2, 3]);
  });

  test('ZIP suggestions, custom events, and unassigned uploads persist',
      () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.load();
    await state.addCustomParasha('בר מצווה');
    state.setImportedLessonInfo({
      'inbox/archive/lesson.mp3': const LessonImportInfo(
        title: 'שיעור מהארכיון',
        number: 27,
        parasha: 'בר מצווה',
        parashaKind: 'event',
      ),
    });
    state.unassignedMedia.add(UnassignedMedia(
      id: 'asset-1',
      lessonInfo: const LessonImportInfo(
          title: 'שיעור מהארכיון',
          number: 27,
          parasha: 'בר מצווה',
          parashaKind: 'event'),
    )
      ..fileName = 'lesson.mp3'
      ..fileSize = 3
      ..remoteUrl = 'https://example.com/lesson.mp3'
      ..assetApi = 'https://api.github.com/repos/example/media/1');
    state.save();
    await state.flushNow();

    final restored = AppState();
    await restored.load();
    expect(restored.customParashot, contains('בר מצווה'));
    expect(restored.importedInfoFor('inbox/archive/lesson.mp3')?.number, 27);
    expect(restored.unassignedMedia.single.lessonInfo?.parashaKind, 'event');
    expect(restored.unassignedMedia.single.fileName, 'lesson.mp3');
  });
}
