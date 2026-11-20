import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';

ImageProvider<Object>? imageProviderFor(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return NetworkImage(path);
  if (path.startsWith('data:')) return MemoryImage(base64Decode(path.split(',').last));
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}
