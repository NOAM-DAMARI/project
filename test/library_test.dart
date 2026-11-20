import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lesson_player/models/item.dart';
import 'package:lesson_player/services/library.dart';

void main() {
  final raw = jsonEncode({
    'singers': [
      {'id': 's1', 'name': 'זמר'}
    ],
    'lessons': [
      {
        'id': 'l1',
        'title': 'שיעור ישן',
        'date': '2025-01-01T00:00:00.000',
        'transcript': [
          {'ms': 0, 'text': 'תמלול'}
        ],
        'remoteUrl': 'https://example.com/a.mp3',
      },
      {
        'id': 'l2',
        'title': 'שיעור חדש',
        'date': '2026-05-01T00:00:00.000',
        'assetApi': 'https://api.github.com/x',
        'clipStartMs': 1000,
        'clipEndMs': 5000,
      },
      {'id': 'l3', 'title': 'בלי קובץ', 'date': '2024-01-01T00:00:00.000'},
      {'title': 'בלי מזהה'},
    ],
    'songs': [
      {'id': 'b', 'title': 'בית', 'singerId': 's1', 'remoteUrl': 'https://e/b.mp3'},
      {'id': 'a', 'title': 'אור', 'singerId': 's1', 'remoteUrl': 'https://e/a.mp3'},
    ],
  });

  test('lessons are listed newest first', () {
    final lib = Library.parse(raw);
    expect(lib.lessons.map((e) => e.id).toList(), ['l2', 'l1', 'l3']);
  });

  test('songs are listed by name', () {
    final lib = Library.parse(raw);
    expect(lib.songs.map((e) => e.title).toList(), ['אור', 'בית']);
  });

  test('items without an id are skipped', () {
    final lib = Library.parse(raw);
    expect(lib.lessons.any((e) => e.title == 'בלי מזהה'), isFalse);
  });

  test('audio file details are kept so the player can play them', () {
    final l2 = Library.parse(raw).lessons.first;
    expect(l2.kind, ItemKind.lesson);
    expect(l2.assetApi, 'https://api.github.com/x');
    expect(l2.isClip, isTrue);
    expect(l2.clipStartMs, 1000);
    expect(l2.clipEndMs, 5000);
  });

  test('a lesson without an audio file is marked as such', () {
    final l3 = Library.parse(raw).lessons.last;
    expect(l3.hasMedia, isFalse);
  });

  test('the saved copy reads back to the same list', () {
    final lib = Library.parse(raw);
    final again = Library.parse(lib.toCache());
    expect(again.lessons.map((e) => e.id).toList(), ['l2', 'l1', 'l3']);
    expect(again.songs.map((e) => e.id).toList(), ['a', 'b']);
    expect(again.lessons[1].remoteUrl, 'https://example.com/a.mp3');
  });
}
