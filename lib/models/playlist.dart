class Playlist {
  String id, name;
  List<String> songIds;
  Playlist({required this.id, required this.name, List<String>? songIds}) : songIds = songIds ?? [];
  Map toJson() => {'id': id, 'name': name, 'songIds': songIds};
  factory Playlist.fromJson(Map j) => Playlist(id: j['id'], name: j['name'], songIds: List<String>.from(j['songIds'] ?? []));
}
