/// לוח עברי – חישוב מלא ב-Dart טהור (ללא תלות בספריות חיצוניות),
/// עובד זהה בטלפון, במחשב ובדפדפן.
///
/// מספור החודשים: ניסן = 1 ... אדר = 12, אדר ב׳ = 13 (בשנה מעוברת).
class HebrewDate {
  final int year;
  final int month;
  final int day;
  const HebrewDate(this.year, this.month, this.day);

  static const nisan = 1, iyar = 2, sivan = 3, tammuz = 4, av = 5, elul = 6;
  static const tishrei = 7, cheshvan = 8, kislev = 9, tevet = 10, shevat = 11, adar = 12, adar2 = 13;

  /// R.D. (מספר ימים מ-1.1.1 לועזי) של א׳ תשרי שנה 1, פחות יום
  static const _epoch = -1373428;

  // ---------- חוקי הלוח ----------

  static bool isLeapYear(int y) => (7 * y + 1) % 19 < 7;
  static int monthsInYear(int y) => isLeapYear(y) ? 13 : 12;

  static final Map<int, int> _elapsedCache = {};

  /// ימים שעברו ממולד תוהו עד ראש השנה של y (כולל דחיות)
  static int _elapsedDays(int y) => _elapsedCache.putIfAbsent(y, () {
        final prev = y - 1;
        final mElapsed = 235 * (prev ~/ 19) + 12 * (prev % 19) + ((prev % 19) * 7 + 1) ~/ 19;
        final pElapsed = 204 + 793 * (mElapsed % 1080);
        final hElapsed = 5 + 12 * mElapsed + 793 * (mElapsed ~/ 1080) + pElapsed ~/ 1080;
        final parts = (pElapsed % 1080) + 1080 * (hElapsed % 24);
        final d = 1 + 29 * mElapsed + hElapsed ~/ 24;
        var alt = d;
        if (parts >= 19440 ||
            (d % 7 == 2 && parts >= 9924 && !isLeapYear(y)) ||
            (d % 7 == 1 && parts >= 16789 && isLeapYear(prev))) {
          alt++;
        }
        if (alt % 7 == 0 || alt % 7 == 3 || alt % 7 == 5) alt++;
        return alt;
      });

  static int daysInYear(int y) => _elapsedDays(y + 1) - _elapsedDays(y);
  static bool _longCheshvan(int y) => daysInYear(y) % 10 == 5;
  static bool _shortKislev(int y) => daysInYear(y) % 10 == 3;

  static int daysInMonth(int m, int y) {
    if (m == iyar || m == tammuz || m == elul || m == tevet || m == adar2) return 29;
    if (m == adar && !isLeapYear(y)) return 29;
    if (m == cheshvan && !_longCheshvan(y)) return 29;
    if (m == kislev && _shortKislev(y)) return 29;
    return 30;
  }

  /// חודשי השנה לפי הסדר (מתשרי עד אלול)
  static List<int> monthsOrdered(int y) => [
        for (var m = tishrei; m <= monthsInYear(y); m++) m,
        for (var m = nisan; m <= elul; m++) m,
      ];

  bool get isValid =>
      year >= 1 && month >= 1 && month <= monthsInYear(year) && day >= 1 && day <= daysInMonth(month, year);

  // ---------- המרות ----------

  int _toAbs() {
    var t = day;
    if (month < tishrei) {
      for (var m = tishrei; m <= monthsInYear(year); m++) {
        t += daysInMonth(m, year);
      }
      for (var m = nisan; m < month; m++) {
        t += daysInMonth(m, year);
      }
    } else {
      for (var m = tishrei; m < month; m++) {
        t += daysInMonth(m, year);
      }
    }
    return _epoch + _elapsedDays(year) + t - 1;
  }

  static HebrewDate _fromAbs(int abs) {
    var y = ((abs - _epoch) / 365.25).floor() + 1;
    while (_yearStart(y) > abs) {
      y--;
    }
    while (_yearStart(y + 1) <= abs) {
      y++;
    }
    var m = abs < HebrewDate(y, nisan, 1)._toAbs() ? tishrei : nisan;
    while (abs > HebrewDate(y, m, daysInMonth(m, y))._toAbs()) {
      m++;
    }
    final d = 1 + abs - HebrewDate(y, m, 1)._toAbs();
    return HebrewDate(y, m, d);
  }

  static int _yearStart(int y) => HebrewDate(y, tishrei, 1)._toAbs();

  // R.D. של 1.1.1970
  static const _unixRd = 719163;

  static int _gregToAbs(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay + _unixRd;

  /// המרה מתאריך לועזי. [afterSunset] – אחרי השקיעה היום העברי כבר התחלף.
  factory HebrewDate.fromGregorian(DateTime date, {bool afterSunset = false}) =>
      _fromAbs(_gregToAbs(date) + (afterSunset ? 1 : 0));

  /// התאריך הלועזי (בשעה 12:00 כדי להימנע מבעיות שעון קיץ)
  DateTime toGregorian() {
    final abs = _toAbs();
    final utc = DateTime.fromMillisecondsSinceEpoch((abs - _unixRd) * Duration.millisecondsPerDay, isUtc: true);
    return DateTime(utc.year, utc.month, utc.day, 12);
  }

  /// יום בשבוע: 1 = ראשון ... 7 = שבת
  int get dayOfWeek => _toAbs() % 7 + 1;

  // ---------- תצוגה ----------

  static String monthName(int m, int y) {
    if (m == adar) return isLeapYear(y) ? 'אדר א׳' : 'אדר';
    return const {
      nisan: 'ניסן',
      iyar: 'אייר',
      sivan: 'סיוון',
      tammuz: 'תמוז',
      av: 'אב',
      elul: 'אלול',
      tishrei: 'תשרי',
      cheshvan: 'חשוון',
      kislev: 'כסלו',
      tevet: 'טבת',
      shevat: 'שבט',
      adar2: 'אדר ב׳',
    }[m]!;
  }

  static const dayNames = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];

  String get dayName => dayNames[dayOfWeek - 1];

  /// לדוגמה: כ״ה חשוון תשפ״ז
  String format() => '${gematria(day)} ${monthName(month, year)} ${gematria(year % 1000)}';

  @override
  String toString() => format();

  @override
  bool operator ==(Object o) => o is HebrewDate && o.year == year && o.month == month && o.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// מספר באותיות עבריות עם גרש/גרשיים (1–999)
  static String gematria(int n) {
    if (n <= 0) return '$n';
    n %= 1000;
    final sb = StringBuffer();
    var h = n ~/ 100;
    while (h >= 4) {
      sb.write('ת');
      h -= 4;
    }
    if (h > 0) sb.write(' קרש'[h]);
    var rest = n % 100;
    if (rest == 15) {
      sb.write('טו');
    } else if (rest == 16) {
      sb.write('טז');
    } else {
      if (rest >= 10) sb.write(' יכלמנסעפצ'[rest ~/ 10]);
      if (rest % 10 > 0) sb.write(' אבגדהוזחט'[rest % 10]);
    }
    final s = sb.toString();
    if (s.isEmpty) return '';
    return s.length == 1 ? '$s׳' : '${s.substring(0, s.length - 1)}״${s[s.length - 1]}';
  }

  /// שנה עברית מלאה, לדוגמה: ה׳תשפ״ז
  static String yearLabel(int y) => '${gematria(y ~/ 1000)}${gematria(y % 1000)}';
}
