import 'dart:convert';

import '../models/item.dart';

/// התוכן שנקרא מהמאגר: רשימת שיעורים ורשימת שירים.
class Library {
  final List<Item> lessons;
  final List<Item> songs;
  const Library(this.lessons, this.songs);

  static const empty = Library([], []);

  bool get isEmpty => lessons.isEmpty && songs.isEmpty;

  /// קורא את data/music_manager.json של האפליקציה המלאה ולוקח ממנו רק
  /// מזהה, שם וקובץ לכל שיעור ושיר.
  /// שיעורים: החדש ביותר למעלה. שירים: לפי שם.
  factory Library.parse(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map) throw const FormatException('קובץ הנתונים לא תקין');
    List<Item> read(String key, ItemKind kind) => [
          for (final e in (data[key] as List? ?? const []))
            if (e is Map && (e['id']?.toString() ?? '').isNotEmpty)
              Item.fromJson(e, kind),
        ];
    final lessons = read('lessons', ItemKind.lesson)
      ..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    final songs = read('songs', ItemKind.song)
      ..sort((a, b) => a.title.compareTo(b.title));
    return Library(lessons, songs);
  }

  /// עותק קטן לשמירה במכשיר (כדי שהרשימה תופיע גם בלי אינטרנט)
  String toCache() => jsonEncode({
        'lessons': [for (final i in lessons) i.toJson()],
        'songs': [for (final i in songs) i.toJson()],
      });
}
