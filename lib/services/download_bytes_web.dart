import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

web.Blob _blob(Uint8List bytes, String mime) =>
    web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mime));

Future<String?> createMediaObjectUrl(Uint8List bytes, String mime) async =>
    web.URL.createObjectURL(_blob(bytes, mime));

void revokeMediaObjectUrl(String url) => web.URL.revokeObjectURL(url);

void _clickAnchor(String url, String name, {bool newTab = false}) {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  if (newTab) anchor.target = '_blank';
  anchor.style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}

Future<void> downloadBytes(Uint8List bytes, String name, String mime) async {
  final url = web.URL.createObjectURL(_blob(bytes, mime));
  _clickAnchor(url, name);
  web.URL.revokeObjectURL(url);
}

/// הורדת קובץ מכתובת (בלי לטעון לזיכרון) – פותח קישור הורדה בדפדפן
Future<void> openDownloadUrl(String url, String name) async =>
    _clickAnchor(url, name, newTab: true);
