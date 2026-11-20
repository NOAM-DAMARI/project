import 'media.dart';

enum ItemKind { lesson, song }

/// פריט ברשימה: רק מזהה, שם וקובץ השמע. כל שאר הפרטים (תמלול, נקודות,
/// זמרים וכו') לא נטענים באפליקציה הזו.
class Item with MediaFields {
  final String id;
  final String title;
  final ItemKind kind;

  /// לסידור בלבד (לא מוצג)
  final DateTime? date;

  Item({required this.id, required this.title, required this.kind, this.date});

  factory Item.fromJson(Map j, ItemKind kind) => Item(
        id: j['id']?.toString() ?? '',
        title: (j['title']?.toString() ?? '').trim(),
        kind: kind,
        date: DateTime.tryParse(
            (j['date'] ?? j['added'] ?? '').toString()),
      )..readMedia(j);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date?.toIso8601String(),
        ...mediaJson(),
      };
}
