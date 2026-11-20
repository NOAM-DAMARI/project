import 'dart:io' show Platform;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// just_audio לא כולל מנוע שמע ל-Windows ול-Linux (רק Android/iOS/macOS/web).
/// בלי השורה הזו האפליקציה כ-EXE לא מצליחה לנגן: ההורדה רצה אבל הנגן לא נטען.
/// חייב להיקרא לפני יצירת AudioPlayer (כלומר לפני שנוצר PlayerService).
void initAudioBackend() {
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: true);
  }
}
