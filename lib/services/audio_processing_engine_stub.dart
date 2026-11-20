import 'dart:typed_data';

Future<bool> ffmpegAvailable() async => false;

Future<Uint8List> runFfmpeg({
  required Uint8List input,
  required String inputName,
  required String outputName,
  required List<String> args,
}) =>
    throw UnsupportedError('FFmpeg לא זמין');
