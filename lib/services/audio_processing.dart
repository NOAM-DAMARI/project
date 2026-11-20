import 'package:flutter/foundation.dart';

import 'audio_processing_engine_stub.dart'
    if (dart.library.js_interop) 'audio_processing_engine_web.dart'
    if (dart.library.io) 'audio_processing_engine_io.dart' as engine;

/// עיבוד שמע (חיתוך + הפחתת רעש) עם FFmpeg.
/// בדפדפן: ffmpeg.wasm (נטען לפי דרישה).
/// במחשב: ffmpeg שנמצא בתיקיית האפליקציה (ffmpeg/ ליד הקובץ הרץ, או third_party/ffmpeg/bin בזמן פיתוח),
/// ואם אין – ffmpeg מה-PATH.
class AudioProcessingService {
  static Future<bool> isAvailable() => engine.ffmpegAvailable();

  /// משך ה-fade-in וה-fade-out בשתי נקודות החיתוך (שניות).
  /// מונע קליק / "טטוח" כשהקטע מתחיל או נגמר באמצע הגל.
  static const double edgeFadeSeconds = 0.03;

  static Future<Uint8List> exportM4a({
    required Uint8List sourceBytes,
    required String sourceName,
    required double startSeconds,
    required double endSeconds,
    required bool reduceNoise,
    double noiseReductionDb = 18,
  }) async {
    if (sourceBytes.isEmpty) throw Exception('קובץ המקור ריק');
    if (startSeconds < 0 || endSeconds <= startSeconds) {
      throw Exception('טווח החיתוך אינו תקין');
    }
    if (kIsWeb && sourceBytes.lengthInBytes > 80 * 1024 * 1024) {
      throw Exception('בדפדפן אפשר לעבד קבצים עד 80 MB.');
    }
    if (!await engine.ffmpegAvailable()) {
      throw Exception(
          'FFmpeg לא נבנה. במחשב: להריץ third_party/ffmpeg/build.sh (ואז לבנות את האפליקציה מחדש). בדפדפן נדרש חיבור לאינטרנט.');
    }
    final ext = _extension(sourceName);
    final duration = endSeconds - startSeconds;
    final fade = _fadeFor(duration);
    final filters = <String>[
      if (reduceNoise) _denoiseFilter(noiseReductionDb),
      // ה-fade חייב לבוא אחרי -ss שלפני -i (ציר הזמן מתחיל מ-0 בתוך הקטע)
      if (fade > 0) 'afade=t=in:st=0:d=${fade.toStringAsFixed(3)}',
      if (fade > 0)
        'afade=t=out:st=${(duration - fade).toStringAsFixed(3)}:d=${fade.toStringAsFixed(3)}',
    ];
    final args = <String>[
      '-hide_banner', '-y',
      // -ss לפני -i: חיתוך מדויק בכניסה, וציר הזמן של הפילטרים מתחיל מאפס
      '-ss', startSeconds.toStringAsFixed(3),
      '-i', 'input.$ext',
      '-t', duration.toStringAsFixed(3),
      if (filters.isNotEmpty) ...['-af', filters.join(',')],
      '-vn', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart',
      'output.m4a',
    ];
    return engine.runFfmpeg(
        input: sourceBytes, inputName: 'input.$ext', outputName: 'output.m4a', args: args);
  }

  /// הפחתת רעש עם anlmdn (NLMeans) – מוריד רעש רקע בצורה ניכרת ושומר על הדיבור.
  /// המחוון 0–30 dB ממופה לעוצמה 0.5–4 (מעל ~2 ההבדל כמעט לא נשמע).
  static String _denoiseFilter(double db) {
    final s = 0.5 + (db.clamp(0.0, 30.0).toDouble() / 30.0) * 3.5;
    return 'anlmdn=s=${s.toStringAsFixed(2)}:p=0.002:r=0.002:m=15';
  }

  static double _fadeFor(double duration) {
    if (duration <= 0.2) return 0;
    final cap = duration / 4;
    return cap < edgeFadeSeconds ? cap : edgeFadeSeconds;
  }

  static String _extension(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'}.contains(ext) ? ext : 'mp3';
  }
}
