import '../utils/hebrew_calendar.dart';
import '../utils/helpers.dart';
import 'package:flutter/material.dart';

/// בורר תאריך עברי: יום / חודש / שנה. מחזיר את התאריך הלועזי המתאים.
class HebrewDateFields extends StatelessWidget {
  final HebrewDate value;
  final ValueChanged<HebrewDate> onChanged;
  const HebrewDateFields({super.key, required this.value, required this.onChanged});

  /// מתקן יום/חודש שלא קיימים בשנה שנבחרה (למשל ל׳ חשוון או אדר ב׳ בשנה פשוטה)
  static HebrewDate normalize(int y, int m, int d) {
    var month = m;
    if (month == HebrewDate.adar2 && !HebrewDate.isLeapYear(y)) month = HebrewDate.adar;
    final max = HebrewDate.daysInMonth(month, y);
    return HebrewDate(y, month, d > max ? max : d);
  }

  @override
  Widget build(BuildContext context) {
    final y = value.year;
    final months = HebrewDate.monthsOrdered(y);
    final days = HebrewDate.daysInMonth(value.month, y);
    final years = [for (var i = y - 60; i <= y + 60; i++) i];

    InputDecoration deco(String l) =>
        InputDecoration(labelText: l, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12));

    final dayField = DropdownButtonFormField<int>(
      key: ValueKey('d$y-${value.month}-${value.day}'),
      initialValue: value.day,
      isExpanded: true,
      decoration: deco('יום'),
      menuMaxHeight: 360,
      items: [
        for (var d = 1; d <= days; d++) DropdownMenuItem(value: d, child: Text(HebrewDate.gematria(d))),
      ],
      onChanged: (d) => d == null ? null : onChanged(HebrewDate(y, value.month, d)),
    );
    final monthField = DropdownButtonFormField<int>(
      key: ValueKey('m$y-${value.month}'),
      initialValue: value.month,
      isExpanded: true,
      decoration: deco('חודש'),
      menuMaxHeight: 420,
      items: [
        for (final m in months) DropdownMenuItem(value: m, child: Text(HebrewDate.monthName(m, y))),
      ],
      onChanged: (m) => m == null ? null : onChanged(normalize(y, m, value.day)),
    );
    final yearField = DropdownButtonFormField<int>(
      key: ValueKey('y$y'),
      initialValue: y,
      isExpanded: true,
      decoration: deco('שנה'),
      menuMaxHeight: 420,
      items: [
        for (final yy in years) DropdownMenuItem(value: yy, child: Text(HebrewDate.yearLabel(yy))),
      ],
      onChanged: (yy) => yy == null ? null : onChanged(normalize(yy, value.month, value.day)),
    );

    return LayoutBuilder(builder: (context, box) {
      // במסך צר: יום וחודש בשורה אחת, השנה מתחת
      if (box.maxWidth < 380) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(flex: 2, child: dayField),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: monthField),
          ]),
          const SizedBox(height: 10),
          yearField,
        ]);
      }
      return Row(children: [
        Expanded(flex: 3, child: dayField),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: monthField),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: yearField),
      ]);
    });
  }
}

Future<DateTime?> showHebrewDatePicker(BuildContext context, {DateTime? initial}) {
  var value = HebrewDate.fromGregorian(initial ?? DateTime.now());
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final g = value.toGregorian();
        return AlertDialog(
          title: const Text('בחירת תאריך עברי'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HebrewDateFields(value: value, onChanged: (v) => setState(() => value = v)),
              const SizedBox(height: 14),
              Text('יום ${value.dayName} · ${fmtDate(g)}',
                  textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.titleMedium),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, g),
              child: const Text('אישור'),
            ),
          ],
        );
      },
    ),
  );
}

/// בחירת תאריך: לועזי או עברי, לפי בחירת המשתמש.
Future<DateTime?> pickAnyDate(BuildContext context, DateTime initial) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.calendar_month_rounded),
          title: const Text('לפי תאריך לועזי'),
          subtitle: Text(fmtDate(initial)),
          onTap: () => Navigator.pop(ctx, 'g'),
        ),
        ListTile(
          leading: const Icon(Icons.auto_stories_rounded),
          title: const Text('לפי תאריך עברי'),
          subtitle: Text(hebrewDate(initial)),
          onTap: () => Navigator.pop(ctx, 'h'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (kind == null || !context.mounted) return null;
  if (kind == 'h') return showHebrewDatePicker(context, initial: initial);
  return showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: DateTime(2150));
}
