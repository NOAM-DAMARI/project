import '../models/lesson.dart';
import '../utils/helpers.dart';
import 'app_state.dart';
import 'dart:convert';
import '../screens/pdf_preview_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' show PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'download_bytes.dart';
import 'pdf_fonts.dart';
import 'points.dart';
import 'subtitle_formats.dart';
import '../models/song.dart';

List<String> _lessonHeaderLines(Lesson l) => [
      l.title,
      if (l.number != null) 'שיעור מס׳ ${l.number}',
      if (l.parasha.isNotEmpty)
        '${l.parashaKind == 'event' ? 'אירוע' : 'פרשת'} ${l.parasha}',
      'תאריך: ${lessonDateLabel(l)}',
    ];

List<String> _lessonBodyLines(Lesson l, {bool withTranscript = false}) => [
      if (l.summary.isNotEmpty) ...['סיכום:', l.summary, ''],
      if (l.points.isNotEmpty) ...[
        'נקודות עיקריות:',
        ...l.points.map((e) => '• $e'),
        ''
      ],
      if (l.marks.isNotEmpty) ...[
        'סימניות:',
        ...l.marks
            .map((m) => '${fmt(Duration(milliseconds: m.ms))} - ${m.text}'),
        '',
      ],
      if (withTranscript && l.transcript.isNotEmpty) ...[
        'תמלול:',
        ...l.transcript
            .map((m) => '[${fmt(Duration(milliseconds: m.ms))}] ${m.text}'),
      ],
    ];

String lessonText(Lesson l, {bool withTranscript = false}) => [
      ..._lessonHeaderLines(l),
      '',
      ..._lessonBodyLines(l, withTranscript: withTranscript),
    ].join('\n');

String _safeName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

/// שיתוף קובץ מהזיכרון – עובד בטלפון, במחשב ובדפדפן (בדפדפן הקובץ יורד)
Future<void> shareBytes(List<int> bytes, String name, String mime,
    {String? text}) async {
  if (kIsWeb) {
    await downloadBytes(Uint8List.fromList(bytes), name, mime);
    return;
  }
  final file =
      XFile.fromData(Uint8List.fromList(bytes), name: name, mimeType: mime);
  await SharePlus.instance.share(
    ShareParams(files: [file], text: text, fileNameOverrides: [name]),
  );
}

/// בחירת פורמט ייצוא לשיעור
Future<void> exportLessonMenu(BuildContext context, Lesson l) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_rounded),
          title: const Text('קובץ PDF'),
          subtitle: const Text('סיכום, נקודות, סימניות ותמלול'),
          onTap: () => Navigator.pop(ctx, 'pdf'),
        ),
        ListTile(
          leading: const Icon(Icons.description_rounded),
          title: const Text('קובץ טקסט'),
          subtitle: const Text('סיכום ונקודות בלבד'),
          onTap: () => Navigator.pop(ctx, 'txt'),
        ),
        if (l.transcript.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.closed_caption_rounded),
            title: const Text('ייצוא כתוביות'),
            subtitle: const Text('TXT · SRT · VTT · LRC'),
            onTap: () => Navigator.pop(ctx, 'subs'),
          ),
        ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('העתקה כטקסט'),
          onTap: () => Navigator.pop(ctx, 'copy'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (kind == null) return;
  try {
    switch (kind) {
      case 'pdf':
        await exportLesson(context, l);
      case 'txt':
        await shareBytes(utf8.encode(lessonText(l)),
            '${_safeName(l.title)}.txt', 'text/plain',
            text: l.title);
      case 'subs':
        if (context.mounted)
          await exportSubtitlesMenu(context, l.transcript, l.title,
              totalMs: null);
      case 'copy':
        await Clipboard.setData(
            ClipboardData(text: lessonText(l, withTranscript: true)));
        if (context.mounted) snack(context, 'הועתק');
    }
  } catch (e) {
    if (context.mounted) snack(context, 'הייצוא נכשל: $e');
  }
}

/// שורה בטבלת PDF: מספר · שם · תאריך עברי
typedef PdfTableRow = ({String number, String name, String hebrewDate});

/// טבלה בעברית: מספר – שם – תאריך עברי.
/// הטבלה נבנית משמאל לימין, ולכן העמודות בסדר הפוך כדי שהמספר יופיע בצד ימין.
pw.Widget _numberNameDateTable(PdfFonts fonts, List<PdfTableRow> rows,
        {String nameHeader = 'שם'}) =>
    pw.TableHelper.fromTextArray(
      headerStyle: fonts.style(size: 11, isBold: true),
      cellStyle: fonts.style(size: 11),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerRight,
      headerAlignment: pw.Alignment.centerRight,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(6),
        2: const pw.FlexColumnWidth(1.6),
      },
      headers: ['תאריך עברי', nameHeader, 'מספר'],
      data: [
        for (final r in rows) [r.hebrewDate, r.name, r.number],
      ],
    );

/// יצירת PDF בעברית (הפונטים מצורפים לאפליקציה).
Future<Uint8List> buildLessonPdf(Lesson l) async {
  final fonts = await PdfFonts.load();
  final doc = pw.Document();
  final body = _lessonBodyLines(l, withTranscript: true);
  doc.addPage(pw.MultiPage(
    textDirection: pw.TextDirection.rtl,
    theme: fonts.theme,
    build: (_) => [
      pw.Text(l.title, style: fonts.style(size: 22, isBold: true)),
      pw.SizedBox(height: 8),
      _numberNameDateTable(fonts, [
        (
          number: l.number?.toString() ?? '-',
          name: l.title,
          hebrewDate: hebrewDate(l.date),
        ),
      ], nameHeader: 'שם השיעור'),
      if (l.parasha.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text(
            '${l.parashaKind == 'event' ? 'אירוע' : 'פרשת'} ${l.parasha}',
            style: fonts.style(size: 11)),
      ],
      pw.SizedBox(height: 10),
      ...body.map((e) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(
              e.isEmpty ? ' ' : e,
              style: e.endsWith(':')
                  ? fonts.style(size: 14, isBold: true)
                  : fonts.style(size: 11),
            ),
          )),
    ],
  ));
  return doc.save();
}

/// PDF של רשימת קבצים/שיעורים: מספר הקובץ – שם הקובץ – תאריך עברי.
Future<Uint8List> buildNumberNameDatePdf(List<PdfTableRow> rows,
    {String title = 'רשימת שיעורים', String nameHeader = 'שם'}) async {
  final fonts = await PdfFonts.load();
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    textDirection: pw.TextDirection.rtl,
    theme: fonts.theme,
    build: (_) => [
      pw.Text(title, style: fonts.style(size: 20, isBold: true)),
      pw.SizedBox(height: 4),
      pw.Text('${rows.length} פריטים · הודפס ${hebrewDate(DateTime.now())}',
          style: fonts.style(size: 10)),
      pw.SizedBox(height: 10),
      _numberNameDateTable(fonts, rows, nameHeader: nameHeader),
    ],
  ));
  return doc.save();
}

/// שורות לטבלת שיעורים: מספר השיעור, שם השיעור, התאריך העברי.
List<PdfTableRow> lessonTableRows(Iterable<Lesson> lessons) => [
      for (final l in lessons)
        (
          number: l.number?.toString() ?? '-',
          name: l.title,
          hebrewDate: hebrewDate(l.date),
        ),
    ];

Future<void> printNumberNameDate(
    BuildContext context, List<PdfTableRow> rows,
    {String title = 'רשימת שיעורים', String nameHeader = 'שם'}) async {
  if (rows.isEmpty) {
    snack(context, 'אין מה לייצא');
    return;
  }
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => PdfPreviewScreen(
      title: title,
      fileName: '${_safeName(title)}.pdf',
      buildPdf: () => buildNumberNameDatePdf(rows,
          title: title, nameHeader: nameHeader),
    ),
  ));
}

Future<void> exportLesson(BuildContext context, Lesson l) async {
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => PdfPreviewScreen(
      title: l.title,
      fileName: '${_safeName(l.title)}.pdf',
      buildPdf: () => buildLessonPdf(l),
    ),
  ));
}

List<Widget> backupTiles(BuildContext c) => [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.save_alt_rounded),
        title: const Text('גיבוי נתונים'),
        subtitle: const Text(
            'נתוני האתר לקובץ JSON, עם אפשרות לכלול גם הגדרות ומפתחות API'),
        onTap: () async {
          final includeSettings = await showDialog<bool>(
            context: c,
            builder: (context) => AlertDialog(
              title: const Text('לכלול הגדרות API בגיבוי?'),
              content: const Text(
                'הגיבוי עשוי להכיל מפתחות API ופרטי GitHub. אל תשתף את הקובץ אם בחרת לכלול הגדרות.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('ביטול'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('ללא הגדרות'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('כולל הגדרות API'),
                ),
              ],
            ),
          );
          if (includeSettings == null) return;
          try {
            final d = DateTime.now();
            await shareBytes(
                utf8.encode(app.export(includeSettings: includeSettings)),
                'backup_${d.year}-${d.month}-${d.day}.json',
                'application/json');
          } catch (e) {
            if (c.mounted) snack(c, 'הגיבוי נכשל: $e');
          }
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.settings_outlined),
        title: const Text('ייצוא הגדרות'),
        subtitle: const Text('כולל פרטי GitHub ומפתחות התמלול'),
        onTap: () async {
          try {
            final bytes = utf8.encode(jsonEncode(app.exportSettings()));
            await shareBytes(bytes, 'lesson_manager_settings.json', 'application/json');
          } catch (e) {
            if (c.mounted) snack(c, 'ייצוא ההגדרות נכשל: $e');
          }
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.settings_backup_restore_rounded),
        title: const Text('ייבוא הגדרות'),
        subtitle: const Text('שדות ריקים יישארו ללא שינוי'),
        onTap: () async {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['json'],
            withData: true,
          );
          final bytes = result == null || result.files.isEmpty
              ? null
              : result.files.first.bytes;
          if (bytes == null) return;
          try {
            final decoded = jsonDecode(utf8.decode(bytes));
            if (decoded is! Map<String, dynamic>) throw const FormatException();
            await app.importSettings(decoded);
            if (c.mounted) snack(c, 'ההגדרות שיובאו נשמרו');
          } catch (_) {
            if (c.mounted) snack(c, 'קובץ הגדרות לא תקין');
          }
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.restore_rounded),
        title: const Text('שחזור מגיבוי'),
        subtitle: const Text('מחליף את כל הנתונים הנוכחיים'),
        onTap: () async {
          final r = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['json'],
              withData: true);
          final bytes =
              r == null || r.files.isEmpty ? null : r.files.first.bytes;
          if (bytes == null) return;
          if (c.mounted &&
              !await confirm(c, 'השחזור יחליף את כל הנתונים הנוכחיים. להמשיך?',
                  ok: 'שחזור')) return;
          String msg;
          try {
            final decoded = jsonDecode(utf8.decode(bytes));
            if (decoded is! Map<String, dynamic>) throw const FormatException();
            app.restore(utf8.decode(bytes));
            final settings = decoded['settings'];
            if (settings is Map<String, dynamic>) {
              await app.importSettings(settings);
            }
            app.save();
            msg = settings is Map<String, dynamic>
                ? 'הנתונים וההגדרות שוחזרו'
                : 'הנתונים שוחזרו';
          } catch (_) {
            msg = 'קובץ גיבוי לא תקין';
          }
          if (c.mounted) snack(c, msg);
        },
      ),
      if (!app.githubReady)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_forever_outlined),
          title: const Text('מחק את כל נתוני האתר'),
          subtitle: const Text('מוצג כשאין חיבור פעיל ל-GitHub'),
          onTap: () async {
            if (!c.mounted ||
                !await confirm(c, 'למחוק את הנתונים השמורים באתר ואת מטמון המדיה?', ok: 'המשך')) return;
            if (!c.mounted ||
                !await confirm(c, 'המחיקה לא ניתנת לביטול. למחוק עכשיו?', ok: 'מחק נתונים')) return;
            await app.clearLocalSiteData();
            if (c.mounted) snack(c, 'הנתונים המקומיים ומטמון המדיה נמחקו');
          },
        ),
    ];

/// ייצוא כתוביות לקובץ: TXT (עם/בלי זמנים), SRT, VTT, LRC
Future<void> exportSubtitlesMenu(
    BuildContext context, List<Seg> segs, String title,
    {int? totalMs}) async {
  if (segs.isEmpty) {
    snack(context, 'אין כתוביות לייצוא');
    return;
  }
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final e in {
          'txt': 'טקסט (TXT) עם זמנים',
          'plain': 'טקסט נקי (TXT) בלי זמנים',
          'srt': 'SRT – לנגנים ו-YouTube',
          'vtt': 'WebVTT – לאתרים',
          'lrc': 'LRC – לשירים / קריוקי',
        }.entries)
          ListTile(
              leading: const Icon(Icons.subtitles_rounded),
              title: Text(e.value),
              onTap: () => Navigator.pop(ctx, e.key)),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (kind == null) return;
  final name = _safeName(title);
  final (String body, String ext, String mime) = switch (kind) {
    'plain' => (toTxt(segs, withTimes: false), 'txt', 'text/plain'),
    'srt' => (toSrt(segs, totalMs: totalMs), 'srt', 'application/x-subrip'),
    'vtt' => (toVtt(segs, totalMs: totalMs), 'vtt', 'text/vtt'),
    'lrc' => (toLrc(segs, title: title), 'lrc', 'text/plain'),
    _ => (toTxt(segs), 'txt', 'text/plain'),
  };
  try {
    // BOM כדי שפנקס רשימות ב-Windows יציג עברית נכון
    await shareBytes(
        [0xEF, 0xBB, 0xBF, ...utf8.encode(body)], '$name.$ext', mime,
        text: title);
  } catch (e) {
    if (context.mounted) snack(context, 'הייצוא נכשל: $e');
  }
}

/// כתוביות של שיר (שורות עם זמן בלבד)
List<Seg> songSegs(Song s) {
  final lines = s.lyrics.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (i < s.stamps.length && s.stamps[i] >= 0 && lines[i].trim().isNotEmpty)
        Seg(s.stamps[i], lines[i])
  ]..sort((a, b) => a.ms.compareTo(b.ms));
}

/// בניית PDF של נקודות מפתח בעברית.
Future<Uint8List> buildPointsPdf(List<({Lesson lesson, int index})> items,
    {String title = 'רשימת נקודות'}) async {
  final fonts = await PdfFonts.load();
  final doc = pw.Document();
  final multiLesson = items.map((e) => e.lesson.id).toSet().length > 1;
  doc.addPage(pw.MultiPage(
    textDirection: pw.TextDirection.rtl,
    theme: fonts.theme,
    build: (_) => [
      pw.Text(title, style: fonts.style(size: 20, isBold: true)),
      pw.SizedBox(height: 4),
      pw.Text('${items.length} נקודות · הודפס ${fmtDate(DateTime.now())}',
          style: fonts.style(size: 10)),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headerStyle: fonts.style(size: 11, isBold: true),
        cellStyle: fonts.style(size: 10),
        cellAlignment: pw.Alignment.topRight,
        headerAlignment: pw.Alignment.centerRight,
        columnWidths: {
          0: const pw.FlexColumnWidth(5),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FixedColumnWidth(156), // דקות: טווח זמן מלא בשורה אחת
          if (multiLesson) 4: const pw.FlexColumnWidth(2.2),
        },
        headers: ['פירוט', 'כותרת', 'נושא', 'דקה', if (multiLesson) 'שיעור'],
        data: [
          for (final r in items)
            [
              r.lesson.pointNote(r.index),
              r.lesson.pointTitle(r.index),
              [r.lesson.pointCat(r.index), r.lesson.pointSub(r.index)]
                  .where((e) => e.isNotEmpty)
                  .join(' › '),
              '${fmt(Duration(milliseconds: r.lesson.pointStart(r.index)))}–${fmt(Duration(milliseconds: r.lesson.pointEnd(r.index)))}',
              if (multiLesson) r.lesson.title,
            ]
        ],
      ),
    ],
  ));
  return doc.save();
}

Future<void> printPoints(
    BuildContext context, List<({Lesson lesson, int index})> items,
    {String title = 'רשימת נקודות'}) async {
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => PdfPreviewScreen(
      title: title,
      fileName: '${_safeName(title)}.pdf',
      buildPdf: () => buildPointsPdf(items, title: title),
    ),
  ));
}
