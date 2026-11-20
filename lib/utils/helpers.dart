import 'package:flutter/material.dart';

Future<T?> go<T>(BuildContext c, Widget w) =>
    Navigator.push<T>(c, MaterialPageRoute(builder: (_) => w));

void snack(BuildContext c, String msg) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String fmt(Duration d) {
  String t(int x) => x.toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}'
      : '${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}';
}
