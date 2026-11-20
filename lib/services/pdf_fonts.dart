import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// גופנים לייצוא PDF.
///
/// גופן העברית (Noto Sans Hebrew) מכיל רק אותיות ניקוד וגרשיים – **אין בו
/// ספרות, נקודתיים, מקפים, סוגריים או אותיות לטיניות**, ולכן מספרים הופיעו
/// ב-PDF כריבועים / "XXXX". DejaVu Sans מצורף כגופן משלים (fallback):
/// כל תו שחסר בגופן העברי נלקח ממנו.
class PdfFonts {
  final pw.Font base;
  final pw.Font bold;
  final pw.Font fallback;
  final pw.Font fallbackBold;

  const PdfFonts._(this.base, this.bold, this.fallback, this.fallbackBold);

  static Future<PdfFonts> load() async {
    Future<pw.Font> font(String asset) async =>
        pw.Font.ttf(await rootBundle.load(asset));
    return PdfFonts._(
      await font('assets/fonts/NotoSansHebrew-Regular.ttf'),
      await font('assets/fonts/NotoSansHebrew-Bold.ttf'),
      await font('assets/fonts/DejaVuSans.ttf'),
      await font('assets/fonts/DejaVuSans-Bold.ttf'),
    );
  }

  /// ערכת נושא לעמוד: גופן עברי + גופן משלים לספרות ופיסוק.
  pw.ThemeData get theme => pw.ThemeData.withFont(
        base: base,
        bold: bold,
        fontFallback: [fallback, fallbackBold],
      );

  /// סגנון טקסט עם גופן משלים (גם כשמגדירים font במפורש).
  pw.TextStyle style({double size = 11, bool isBold = false}) => pw.TextStyle(
        font: isBold ? bold : base,
        fontSize: size,
        fontFallback: [isBold ? fallbackBold : fallback],
      );
}
