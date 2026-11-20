import '../models/lesson.dart';

/// נושאים ראשיים לנקודות
const pointCategories = ['סיפורים', 'הלכות', 'מנהגים', 'חידושים', 'אזהרות'];

/// גישה אחידה ובטוחה לנקודות ציון של שיעור.
/// הנתונים נשמרים ברשימות מקבילות (לתאימות לאחור עם קבצי JSON קיימים),
/// וכל הקוד באפליקציה עובר דרך הפונקציות האלה כדי שהרשימות לא יצאו מסנכרון.
extension LessonPoints on Lesson {
  static const defaultLengthMs = 5 * 60 * 1000;

  int get pointCount => points.length;

  void _pad(int i) {
    while (pointNotes.length <= i) pointNotes.add('');
    while (pointTimes.length <= i) pointTimes.add(Seg(0, ''));
    while (pointEnds.length <= i) pointEnds.add(0);
    while (pointCats.length <= i) pointCats.add('');
    while (pointSubs.length <= i) pointSubs.add('');
  }

  String pointCat(int i) => i < pointCats.length ? pointCats[i] : '';
  String pointSub(int i) => i < pointSubs.length ? pointSubs[i] : '';

  String pointTitle(int i) => i < points.length ? points[i] : '';
  String pointNote(int i) => i < pointNotes.length ? pointNotes[i] : '';
  int pointStart(int i) => i < pointTimes.length ? pointTimes[i].ms : 0;

  /// סוף הטווח – אם לא נקבע: תחילת הנקודה הבאה או 5 דקות.
  int pointEnd(int i) {
    final s = pointStart(i);
    if (i < pointEnds.length && pointEnds[i] > s) return pointEnds[i];
    if (i + 1 < pointTimes.length && pointTimes[i + 1].ms > s) return pointTimes[i + 1].ms;
    return s + defaultLengthMs;
  }

  bool pointHasEnd(int i) => i < pointEnds.length && pointEnds[i] > pointStart(i);

  int addPoint({required String title, String note = '', required int startMs, int endMs = 0, String cat = '', String sub = ''}) {
    points.add(title);
    final i = points.length - 1;
    _pad(i);
    pointNotes[i] = note;
    pointTimes[i] = Seg(startMs, '');
    pointEnds[i] = endMs;
    pointCats[i] = cat;
    pointSubs[i] = sub;
    return i;
  }

  void updatePoint(int i, {String? title, String? note, int? startMs, int? endMs, String? cat, String? sub}) {
    if (i < 0 || i >= points.length) return;
    _pad(i);
    if (title != null) points[i] = title;
    if (note != null) pointNotes[i] = note;
    if (startMs != null) pointTimes[i].ms = startMs;
    if (endMs != null) pointEnds[i] = endMs;
    if (cat != null) pointCats[i] = cat;
    if (sub != null) pointSubs[i] = sub;
  }

  void removePoint(int i) {
    if (i < 0 || i >= points.length) return;
    points.removeAt(i);
    if (i < pointNotes.length) pointNotes.removeAt(i);
    if (i < pointTimes.length) pointTimes.removeAt(i);
    if (i < pointEnds.length) pointEnds.removeAt(i);
    if (i < pointCats.length) pointCats.removeAt(i);
    if (i < pointSubs.length) pointSubs.removeAt(i);
  }

  void movePoint(int a, int b) {
    if (a < 0 || a >= points.length) return;
    _pad(points.length - 1);
    points.insert(b, points.removeAt(a));
    pointNotes.insert(b, pointNotes.removeAt(a));
    pointTimes.insert(b, pointTimes.removeAt(a));
    pointEnds.insert(b, pointEnds.removeAt(a));
    pointCats.insert(b, pointCats.removeAt(a));
    pointSubs.insert(b, pointSubs.removeAt(a));
  }

  /// טקסט התמלול שנופל בתוך טווח הנקודה
  String pointTranscript(int i) {
    final s = pointStart(i), e = pointEnd(i);
    final rows = <String>[];
    for (var k = 0; k < transcript.length; k++) {
      final segStart = transcript[k].ms;
      final segEnd = k + 1 < transcript.length ? transcript[k + 1].ms : segStart + 1;
      if (segEnd > s && segStart < e) rows.add(transcript[k].text);
    }
    return rows.join('\n');
  }
}

/// פענוח זמן בפורמט 00:00 / 0:00:00 / דקות בלבד → מילישניות
int? parseClock(String value) {
  final parts = value.trim().split(':').map((e) => e.trim()).toList();
  if (parts.isEmpty || parts.first.isEmpty) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null || n < 0)) return null;
  if (nums.length == 1) return nums[0]! * 60000;
  if (nums.length == 2) {
    if (nums[1]! > 59) return null;
    return (nums[0]! * 60 + nums[1]!) * 1000;
  }
  if (nums.length == 3) {
    if (nums[1]! > 59 || nums[2]! > 59) return null;
    return (nums[0]! * 3600 + nums[1]! * 60 + nums[2]!) * 1000;
  }
  return null;
}
