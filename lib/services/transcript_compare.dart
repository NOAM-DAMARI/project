import '../models/lesson.dart';
import 'text_aligner.dart';

class DiffWord {
  final String text;
  final bool same;
  const DiffWord(this.text, this.same);
}

class CompareRow {
  final int startMs;
  final List<DiffWord> a, b;
  const CompareRow(this.startMs, this.a, this.b);
  int get diffCount => a.where((w) => !w.same).length + b.where((w) => !w.same).length;
}

class CompareResult {
  final List<CompareRow> rows;
  final int wordsA, wordsB, matched;
  const CompareResult(this.rows, this.wordsA, this.wordsB, this.matched);

  /// אחוז דמיון (0–100) לפי מילים משותפות בסדר זהה
  double get similarity => wordsA + wordsB == 0 ? 100 : 200 * matched / (wordsA + wordsB);
}

List<(int, String)> _timedWords(List<Seg> segs) {
  final out = <(int, String)>[];
  for (var k = 0; k < segs.length; k++) {
    final start = segs[k].ms;
    final end = k + 1 < segs.length ? segs[k + 1].ms : start + 4000;
    final words = segs[k].text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    for (var w = 0; w < words.length; w++) {
      out.add((start + ((end - start) * w / words.length).round(), words[w]));
    }
  }
  return out;
}

/// השוואת שני תמלולים לפי חלונות זמן. בכל חלון מסומנות המילים ששונות בין התמלולים
/// (השוואה סלחנית: בלי ניקוד, פיסוק והבדלי אותיות סופיות).
CompareResult compareTranscripts(List<Seg> a, List<Seg> b, {int windowMs = 30000}) {
  final wa = _timedWords(a), wb = _timedWords(b);
  final buckets = <int, (List<String>, List<String>)>{};
  for (final w in wa) {
    buckets.putIfAbsent(w.$1 ~/ windowMs, () => (<String>[], <String>[])).$1.add(w.$2);
  }
  for (final w in wb) {
    buckets.putIfAbsent(w.$1 ~/ windowMs, () => (<String>[], <String>[])).$2.add(w.$2);
  }
  final keys = buckets.keys.toList()..sort();
  final rows = <CompareRow>[];
  var matched = 0;
  for (final k in keys) {
    final (xa, xb) = buckets[k]!;
    final na = xa.map(TextAligner.norm).toList(), nb = xb.map(TextAligner.norm).toList();
    // LCS על מילים בחלון (קטן – מהיר)
    final dp = List.generate(na.length + 1, (_) => List<int>.filled(nb.length + 1, 0));
    for (var i = na.length - 1; i >= 0; i--) {
      for (var j = nb.length - 1; j >= 0; j--) {
        dp[i][j] = na[i] == nb[j] ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }
    final sameA = List<bool>.filled(na.length, false), sameB = List<bool>.filled(nb.length, false);
    var i = 0, j = 0;
    while (i < na.length && j < nb.length) {
      if (na[i] == nb[j]) {
        sameA[i] = true;
        sameB[j] = true;
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    matched += dp[0][0];
    rows.add(CompareRow(
      k * windowMs,
      [for (var x = 0; x < xa.length; x++) DiffWord(xa[x], sameA[x])],
      [for (var x = 0; x < xb.length; x++) DiffWord(xb[x], sameB[x])],
    ));
  }
  return CompareResult(rows, wa.length, wb.length, matched);
}
