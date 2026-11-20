import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// גישה ל-window.lessonFfmpeg (מוגדר ב-web/ffmpeg_bridge.js) בלי extension types
/// ובלי בדיקות טיפוס JS בזמן ריצה, כך שהקוד תקין גם בבניית JS וגם בבניית Wasm.
JSObject? _bridge() {
  if (!globalContext.has('lessonFfmpeg')) return null;
  return globalContext.getProperty<JSObject?>('lessonFfmpeg'.toJS);
}

Future<bool> ffmpegAvailable() async {
  try {
    final bridge = _bridge();
    if (bridge == null) return false;
    final result = await bridge
        .callMethod<JSPromise<JSBoolean>>('available'.toJS)
        .toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}

Future<Uint8List> runFfmpeg({
  required Uint8List input,
  required String inputName,
  required String outputName,
  required List<String> args,
}) async {
  try {
    final bridge = _bridge();
    if (bridge == null) throw StateError('מנוע עיבוד השמע אינו זמין');
    final output = await bridge
        .callMethodVarArgs<JSPromise<JSUint8Array>>('run'.toJS, <JSAny?>[
          input.toJS,
          inputName.toJS,
          outputName.toJS,
          jsonEncode(args).toJS,
        ])
        .toDart;
    return output.toDart;
  } catch (error) {
    throw Exception('עיבוד השמע נכשל: $error');
  }
}
