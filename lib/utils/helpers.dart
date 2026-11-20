import '../models/lesson.dart';
import '../models/singer.dart';
import 'package:flutter/material.dart';
import 'hebrew_calendar.dart';
import 'image_provider.dart';

Future<T?> go<T>(BuildContext c, Widget w) =>
    Navigator.push<T>(c, MaterialPageRoute(builder: (_) => w));

Widget avatar(Singer? s, {double r = 22}) {
  final img = imageProviderFor(s?.image);
  return CircleAvatar(
    radius: r,
    backgroundColor: Color(s?.color ?? 0xFF9E9E9E),
    backgroundImage: img,
    child: img == null
        ? Text(
            s?.name.isNotEmpty == true ? s!.name[0] : '?',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: r * .8),
          )
        : null,
  );
}

Future<bool> confirm(BuildContext c, String msg, {String ok = 'מחיקה'}) async =>
    await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              minimumSize: const Size(0, 40),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ok),
          ),
        ],
      ),
    ) ??
    false;

void snack(BuildContext c, String msg) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// תאריך עברי מלא, לדוגמה: כ״ה חשוון תשפ״ז
String hebrewDate(DateTime date) => HebrewDate.fromGregorian(date).format();

String fmt(Duration d) {
  String t(int x) => x.toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}'
      : '${t(d.inMinutes % 60)}:${t(d.inSeconds % 60)}';
}

String fmtDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

String fmtBytes(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024)
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

Future<String?> askText(BuildContext c, String title,
    {String init = '', int lines = 1}) async {
  final ctl = TextEditingController(text: init);
  final res = await showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
            controller: ctl, autofocus: true, maxLines: lines, minLines: 1),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(
              ctx, ctl.text.trim().isEmpty ? null : ctl.text.trim()),
          child: const Text('אישור'),
        ),
      ],
    ),
  );
  ctl.dispose();
  return res;
}

/// חלון התקדמות לפעולה ארוכה (העלאה / הורדה). לא ניתן לסגור באמצע.
Future<T> runWithProgress<T>(
  BuildContext context,
  String title,
  Future<T> Function(void Function(int done, int total) report) task,
) async {
  final progress = ValueNotifier<(int, int)?>(null);
  var lastPct = -1;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<(int, int)?>(
          valueListenable: progress,
          builder: (_, v, __) {
            final ratio = v == null || v.$2 == 0 ? null : v.$1 / v.$2;
            return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: ratio, minHeight: 8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    v == null || ratio == null
                        ? 'מתחיל...'
                        : '${(ratio * 100).toStringAsFixed(0)}%  ·  ${fmtBytes(v.$1)} מתוך ${fmtBytes(v.$2)}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text('אפשר להמשיך להשתמש בטלפון, אך אין לסגור את האפליקציה',
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.bodySmall),
                ]);
          },
        ),
      ),
    ),
  );
  try {
    return await task((done, total) {
      final pct = total == 0 ? 0 : done * 200 ~/ total;
      if (pct != lastPct) {
        lastPct = pct;
        progress.value = (done, total);
      }
    });
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
  }
}

/// תווית תאריך לשיעור לפי הבחירה בטופס העריכה (לועזי או עברי)
String lessonDateLabel(Lesson l) =>
    l.dateKind == 'h' ? hebrewDate(l.date) : fmtDate(l.date);

/// כותרת משנה לשיעור: מספר · פרשה · תאריך
String lessonMeta(Lesson l) => [
      if (l.number != null) '#${l.number}',
      if (l.parasha.isNotEmpty)
        '${l.parashaKind == 'event' ? 'אירוע' : 'פרשת'} ${l.parasha}',
      lessonDateLabel(l),
    ].join(' · ');
