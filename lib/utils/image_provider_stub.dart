import 'dart:convert';
import 'package:flutter/widgets.dart';

ImageProvider<Object>? imageProviderFor(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return NetworkImage(path);
  if (path.startsWith('data:')) return MemoryImage(base64Decode(path.split(',').last));
  return null;
}
