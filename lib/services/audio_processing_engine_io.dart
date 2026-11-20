import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

String get _binaryName => Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';

/// מחפש את ה-FFmpeg שנבנה מהקוד המקורי בתוך הפרויקט בלבד (בלי PATH):
/// 1. ffmpeg/ ליד הקובץ הרץ (ב-Windows ה-CMake מעתיק לשם את bin/ בבנייה).
/// 2. third_party/ffmpeg/bin בתוך הפרויקט (בזמן flutter run).
Future<String?> _findFfmpeg() async {
  final name = _binaryName;
  final sep = Platform.pathSeparator;
  final candidates = <String>[];

  final appDir = File(Platform.resolvedExecutable).parent;
  candidates.add('${appDir.path}${sep}ffmpeg$sep$name');

  var dir = appDir;
  for (var i = 0; i < 8; i++) {
    candidates.add('${dir.path}${sep}third_party${sep}ffmpeg${sep}bin$sep$name');
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  for (final path in candidates) {
    if (await File(path).exists()) return path;
  }
  return null;
}

Future<bool> ffmpegAvailable() async {
  if (Platform.isAndroid || Platform.isIOS) return false;
  return (await _findFfmpeg()) != null;
}

Future<Uint8List> runFfmpeg({
  required Uint8List input,
  required String inputName,
  required String outputName,
  required List<String> args,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    throw UnsupportedError('FFmpeg לא זמין במכשיר הזה');
  }
  final exe = await _findFfmpeg();
  if (exe == null) throw Exception('FFmpeg לא נמצא');
  final base = await getTemporaryDirectory();
  final dir = await base.createTemp('lesson_ffmpeg_');
  try {
    await File('${dir.path}/$inputName').writeAsBytes(input, flush: true);
    final r = await Process.run(exe, args, workingDirectory: dir.path);
    if (r.exitCode != 0) {
      throw Exception('עיבוד השמע נכשל: ${r.stderr}');
    }
    return Uint8List.fromList(await File('${dir.path}/$outputName').readAsBytes());
  } finally {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
