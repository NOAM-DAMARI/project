import 'media.dart';

class Song with MediaFields {
  String id, title, singerId, lyrics, source, notes;
  int? year;
  String? duration;
  bool fav;
  List<int> stamps = [];
  DateTime added;
  DateTime? eventDate;
  String location;

  Song({
    required this.id,
    required this.title,
    required this.singerId,
    this.lyrics = '',
    this.source = '',
    this.notes = '',
    this.year,
    this.duration,
    this.fav = false,
    this.eventDate,
    this.location = '',
    DateTime? added,
  }) : added = added ?? DateTime.now();

  Map toJson() => {
        'id': id,
        'title': title,
        'singerId': singerId,
        'lyrics': lyrics,
        'source': source,
        'notes': notes,
        'year': year,
        'duration': duration,
        'fav': fav,
        'stamps': stamps,
        'added': added.toIso8601String(),
        'eventDate': eventDate?.toIso8601String(),
        'location': location,
        ...mediaJson(),
      };

  factory Song.fromJson(Map j) => Song(
        id: j['id'],
        title: j['title'] ?? '',
        singerId: j['singerId'] ?? '',
        lyrics: j['lyrics'] ?? '',
        source: j['source'] ?? '',
        notes: j['notes'] ?? '',
        year: (j['year'] as num?)?.toInt(),
        duration: j['duration'],
        fav: j['fav'] ?? false,
        added: DateTime.tryParse(j['added'] ?? ''),
        eventDate: DateTime.tryParse(j['eventDate'] ?? ''),
        location: j['location'] ?? '',
      )
        ..stamps = List<int>.from(j['stamps'] ?? [])
        ..readMedia(j);
}
