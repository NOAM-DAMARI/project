

class Singer {
  String id, name, notes;
  String? image;
  int color;
  Singer({required this.id, required this.name, this.notes = '', this.image, this.color = 0xFF2196F3});
  Map toJson() => {'id': id, 'name': name, 'notes': notes, 'image': image, 'color': color};
  factory Singer.fromJson(Map j) => Singer(
      id: j['id'], name: j['name'], notes: j['notes'] ?? '', image: j['image'], color: j['color'] ?? 0xFF2196F3);
}
