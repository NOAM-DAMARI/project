import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media.dart';
import '../models/singer.dart';
import '../services/app_state.dart';
import '../services/folder_tools.dart';
import '../utils/helpers.dart';
import '../widgets/hebrew_date_picker.dart';

/// לאן נשמר כל קובץ שמיובא מה-ZIP
enum ZipImportTarget {
  /// נשמר כשיעור חדש (עם כל פרטי השיעור)
  lesson,

  /// נשמר כשיר חדש (עם כל פרטי השיר)
  song,

  /// נשמר רק כקובץ ב״לא משויך״, לבחירה מאוחרת בטופס
  unassigned,
}

enum ZipDuplicateAction { replace, skipDuplicates, keepBoth }

/// כל הפרטים שהוזנו בטבלה לקובץ אחד – זהים לשדות בטופס עריכת שיעור / שיר.
class ZipImportSelection {
  final String path;
  final ZipImportTarget target;

  /// שם השיעור / השיר
  final String title;

  // --- שיעור ---
  final int? number;
  final String parasha;
  final String parashaKind;

  /// סוג התאריך שמוצג לשיעור: 'g' לועזי, 'h' עברי
  final String dateKind;

  /// תאריך השיעור / תאריך האירוע של השיר
  final DateTime? date;

  // --- שיר ---
  final String? singerId;
  final int? year;
  final String location;
  final String lyrics;

  /// הערות (שיעור ושיר)
  final String notes;
  final bool duplicate;
  final ZipDuplicateAction duplicateAction;

  const ZipImportSelection({
    this.duplicate = false,
    this.duplicateAction = ZipDuplicateAction.keepBoth,
    required this.path,
    required this.title,
    required this.number,
    required this.parasha,
    required this.parashaKind,
    this.target = ZipImportTarget.lesson,
    this.dateKind = 'g',
    this.date,
    this.singerId,
    this.year,
    this.location = '',
    this.lyrics = '',
    this.notes = '',
  });
}

const _newSingerValue = '__new_singer__';

class ZipImportDialog extends StatefulWidget {
  final List<ZipEntry> entries;

  /// הסוג ההתחלתי לכל הקבצים (אפשר לשנות לכל קובץ בנפרד)
  final ZipImportTarget defaultTarget;

  const ZipImportDialog({
    super.key,
    required this.entries,
    this.defaultTarget = ZipImportTarget.lesson,
  });

  @override
  State<ZipImportDialog> createState() => _ZipImportDialogState();
}

class _ZipImportDialogState extends State<ZipImportDialog> {
  late final List<_ZipImportRow> rows = [
    for (final entry in widget.entries)
      _ZipImportRow(entry, widget.defaultTarget)
  ];

  List<_ZipImportRow> get _included => rows.where((row) => !row.skip).toList();
  int get _includedCount => _included.length;

  Set<String> get _existingFileNames {
    final mediaFiles = <MediaFields>[
      ...app.lessons,
      ...app.songs,
      ...app.unassignedMedia,
    ];
    return {
      for (final media in mediaFiles)
        if (media.fileName?.trim().isNotEmpty == true)
          media.fileName!.trim().toLowerCase(),
    };
  }

  bool _isDuplicate(_ZipImportRow row) =>
      _existingFileNames.contains(row.entry.path.split('/').last.trim().toLowerCase());

  int get _duplicateCount => rows.where(_isDuplicate).length;

  int _countOf(ZipImportTarget target) =>
      _included.where((row) => row.target == target).length;

  @override
  void initState() {
    super.initState();
    // יש רק זמר אחד – נבחר אוטומטית
    if (app.singers.length == 1) {
      for (final row in rows) {
        row.singerId = app.singers.first.id;
      }
    }
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _setTarget(_ZipImportRow row, ZipImportTarget target) {
    row.target = target;
    if (target == ZipImportTarget.song &&
        row.singerId == null &&
        app.singers.length == 1) {
      row.singerId = app.singers.first.id;
    }
  }

  bool _has(ZipImportTarget t) => rows.any((r) => r.target == t);

  /// אילו עמודות מוצגות. העמודות מתאימות לסוגים שנבחרו:
  /// שיעור (או לא משויך – הצעה לשיעור) = מספר שיעור / פרשה / סוג פרשה;
  /// שיר = זמר / שנה / מקום האירוע / מילים. התאריך משותף לשניהם.
  /// 0 סוג, 1 קובץ, 2 שם, 3 מספר, 4 פרשה, 5 סוג פרשה, 6 תאריך,
  /// 7 זמר, 8 שנה, 9 מקום, 10 מילים, 11 הערות, 12 דלג
  Set<int> get _visibleCols {
    final lessonLike = _has(ZipImportTarget.lesson) || _has(ZipImportTarget.unassigned);
    final song = _has(ZipImportTarget.song);
    final dated = _has(ZipImportTarget.lesson) || song;
    return {
      0, 1, 2,
      if (lessonLike) ...[3, 4, 5],
      if (dated) 6,
      if (song) ...[7, 8, 9, 10],
      11, 12,
    };
  }

  Future<void> _addSinger(_ZipImportRow row) async {
    final name = await askText(context, 'שם הזמר החדש');
    if (name == null || !mounted) return;
    final singer = Singer(id: app.newId(), name: name);
    app.singers.add(singer);
    app.save();
    setState(() => row.singerId = singer.id);
  }

  Future<void> _editLyrics(_ZipImportRow row) async {
    final text = await askText(context, 'מילים – ${row.title.text.trim()}',
        init: row.lyrics, lines: 12);
    if (text != null && mounted) setState(() => row.lyrics = text);
  }

  Future<void> _pickDate(_ZipImportRow row) async {
    final picked = row.dateKind == 'h'
        ? await showHebrewDatePicker(context, initial: row.date)
        : await showDatePicker(
            context: context,
            initialDate: row.date,
            firstDate: DateTime(1900),
            lastDate: DateTime(2150));
    if (picked != null && mounted) setState(() => row.date = picked);
  }

  /// קביעת תאריך לכל הקבצים שלא דולגו
  Future<void> _pickDateForAll(String kind) async {
    final initial = _included.isEmpty ? DateTime.now() : _included.first.date;
    final picked = kind == 'h'
        ? await showHebrewDatePicker(context, initial: initial)
        : await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(1900),
            lastDate: DateTime(2150));
    if (picked == null || !mounted) return;
    setState(() {
      for (final row in _included) {
        row.date = picked;
        row.dateKind = kind;
      }
    });
  }

  Future<void> _finish() async {
    var duplicateAction = ZipDuplicateAction.keepBoth;
    final duplicateRows = _included.where(_isDuplicate).length;
    if (duplicateRows > 0) {
      final choice = await showDialog<ZipDuplicateAction>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('נמצאו $duplicateRows קבצים כפולים'),
          content: const Text('ההתאמה נעשית לפי שם הקובץ בלבד. מה לעשות בקבצים המסומנים?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ZipDuplicateAction.skipDuplicates),
              child: const Text('דלג על הכפולים'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ZipDuplicateAction.keepBoth),
              child: const Text('שמור את שניהם'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ZipDuplicateAction.replace),
              child: const Text('החלף קובץ קיים'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      duplicateAction = choice;
    }
    final output = <ZipImportSelection>[];
    for (final row in _included) {
      final duplicate = _isDuplicate(row);
      if (duplicate && duplicateAction == ZipDuplicateAction.skipDuplicates) continue;
      final title = row.title.text.trim();
      final isSong = row.target == ZipImportTarget.song;
      final numberText = row.number.text.trim();
      final number = isSong || numberText.isEmpty ? null : int.tryParse(numberText);
      if (title.isEmpty) {
        snack(context, 'יש למלא שם לכל קובץ (${row.entry.path.split('/').last})');
        return;
      }
      if (!isSong &&
          numberText.isNotEmpty &&
          (number == null || number < 1 || number > 9999)) {
        snack(context, 'מספר השיעור חייב להיות בין 1 ל-9999 ($title)');
        return;
      }
      if (isSong && row.singerId == null) {
        snack(context, 'יש לבחור זמר לשיר "$title"');
        return;
      }
      final yearText = row.year.text.trim();
      final year = isSong && yearText.isNotEmpty ? int.tryParse(yearText) : null;
      if (isSong && yearText.isNotEmpty && year == null) {
        snack(context, 'השנה של "$title" אינה תקינה');
        return;
      }
      output.add(ZipImportSelection(
        path: row.entry.path,
        duplicate: duplicate,
        duplicateAction: duplicateAction,
        target: row.target,
        title: title,
        number: number,
        parasha: isSong ? '' : row.parasha.text.trim(),
        parashaKind: row.parashaKind,
        dateKind: row.dateKind,
        date: row.date,
        singerId: isSong ? row.singerId : null,
        year: year,
        location: isSong ? row.location.text.trim() : '',
        lyrics: isSong ? row.lyrics : '',
        notes: row.target == ZipImportTarget.unassigned ? '' : row.notes.text,
      ));
    }
    Navigator.pop(context, output);
  }

  static String _targetLabel(ZipImportTarget target) => switch (target) {
        ZipImportTarget.lesson => 'שיעור',
        ZipImportTarget.song => 'שיר',
        ZipImportTarget.unassigned => 'לא משויך',
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 24).clamp(280.0, 1280.0).toDouble();
    final height = (size.height - 24).clamp(320.0, 820.0).toDouble();
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ייבוא מתוך ZIP',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
                'בחר לכל קובץ אם הוא שיעור או שיר, ומלא את הפרטים – הוא יישמר ישירות '
                'כשיעור / כשיר עם כל השדות שבטופס העריכה. ״לא משויך״ שומר רק את הקובץ. '
                'סמן ״דלג״ כדי לא לייבא קובץ.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
            if (_duplicateCount > 0)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'נמצאו ${_duplicateCount} קבצים כפולים לפי שם הקובץ. השורות הכפולות מסומנות; בעת הייבוא תוכל להחליף, לדלג או לשמור את שניהם.',
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('קבע לכולם:'),
                  PopupMenuButton<ZipImportTarget>(
                    tooltip: 'סוג לכל הקבצים',
                    onSelected: (target) => setState(() {
                      for (final row in rows) {
                        _setTarget(row, target);
                      }
                    }),
                    itemBuilder: (_) => [
                      for (final target in ZipImportTarget.values)
                        PopupMenuItem(
                            value: target, child: Text(_targetLabel(target))),
                    ],
                    child: const Chip(
                        avatar: Icon(Icons.arrow_drop_down_rounded),
                        label: Text('סוג')),
                  ),
                  if (_has(ZipImportTarget.song))
                  PopupMenuButton<String>(
                    tooltip: 'זמר לכל השירים',
                    onSelected: (id) => setState(() {
                      for (final row in rows) {
                        row.singerId = id;
                      }
                    }),
                    itemBuilder: (_) => [
                      for (final singer in app.singers)
                        PopupMenuItem(value: singer.id, child: Text(singer.name)),
                      if (app.singers.isEmpty)
                        const PopupMenuItem(
                            enabled: false,
                            value: '',
                            child: Text('אין זמרים – הוסף זמר בשורה של שיר')),
                    ],
                    child: const Chip(
                        avatar: Icon(Icons.arrow_drop_down_rounded),
                        label: Text('זמר')),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('תאריך לועזי'),
                    onPressed: () => _pickDateForAll('g'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.auto_stories_rounded, size: 18),
                    label: const Text('תאריך עברי'),
                    onPressed: () => _pickDateForAll('h'),
                  ),
                ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                    '${_countOf(ZipImportTarget.lesson)} שיעורים · '
                    '${_countOf(ZipImportTarget.song)} שירים · '
                    '${_countOf(ZipImportTarget.unassigned)} לא משויכים · '
                    '${rows.length - _includedCount} ידולגו'),
              ),
              TextButton(
                  onPressed: () =>
                      setState(() => rows.forEach((row) => row.skip = false)),
                  child: const Text('בחר הכל')),
              TextButton(
                  onPressed: () =>
                      setState(() => rows.forEach((row) => row.skip = true)),
                  child: const Text('דלג על הכל')),
            ]),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    horizontalMargin: 10,
                    columnSpacing: 10,
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 88,
                    columns: [
                      for (final entry in const [
                      DataColumn(label: Text('סוג')),
                      DataColumn(label: Text('שם הקובץ')),
                      DataColumn(label: Text('שם השיעור / השיר')),
                      DataColumn(label: Text('מספר שיעור')),
                      DataColumn(label: Text('פרשה / אירוע')),
                      DataColumn(label: Text('סוג פרשה')),
                      DataColumn(label: Text('תאריך')),
                      DataColumn(label: Text('זמר')),
                      DataColumn(label: Text('שנה')),
                      DataColumn(label: Text('מקום האירוע')),
                      DataColumn(label: Text('מילים')),
                      DataColumn(label: Text('הערות')),
                      DataColumn(label: Text('דלג')),
                      ].asMap().entries)
                        if (_visibleCols.contains(entry.key)) entry.value,
                    ],
                    rows: [
                      for (var index = 0; index < rows.length; index++)
                        _buildRow(rows[index], index),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ביטול')),
              FilledButton.icon(
                onPressed: _includedCount == 0 ? null : _finish,
                icon: const Icon(Icons.file_download_outlined),
                label: Text('ייבא $_includedCount קבצים'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  DataRow _buildRow(_ZipImportRow row, int index) {
    final path = row.entry.path;
    final active = !row.skip;
    final isSong = row.target == ZipImportTarget.song;
    final isUnassigned = row.target == ZipImportTarget.unassigned;
    // מספר ופרשה: לשיעור, ולקובץ לא משויך (נשמרים כהצעה לשיעור עתידי)
    final lessonFields = active && !isSong;
    final songFields = active && isSong;
    final dateFields = active && !isUnassigned;

    final singerValid = app.singers.any((s) => s.id == row.singerId);

    final all = <DataCell>[
        // סוג: שיעור / שיר / לא משויך
        DataCell(SizedBox(
          width: 120,
          child: DropdownButtonFormField<ZipImportTarget>(
            key: ValueKey('zip-target-$path-${row.target.name}'),
            initialValue: row.target,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final target in ZipImportTarget.values)
                DropdownMenuItem(value: target, child: Text(_targetLabel(target))),
            ],
            onChanged: active
                ? (value) =>
                    setState(() => _setTarget(row, value ?? row.target))
                : null,
          ),
        )),
        DataCell(SizedBox(
          width: 230,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(path.split('/').last,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (_isDuplicate(row))
                    const Tooltip(
                      message: 'קובץ בשם זה כבר קיים במערכת',
                      child: Icon(Icons.warning_amber_rounded,
                          color: Colors.deepOrange, size: 18),
                    ),
                ]),
                Text('$path · ${fmtBytes(row.entry.size)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
        )),
        DataCell(SizedBox(
          width: 210,
          child: TextField(
            key: ValueKey('zip-title-$path'),
            controller: row.title,
            enabled: active,
            decoration: InputDecoration(
                isDense: true, hintText: isSong ? 'שם השיר' : 'שם השיעור'),
          ),
        )),
        DataCell(SizedBox(
          width: 100,
          child: TextField(
            key: ValueKey('zip-number-$path'),
            controller: row.number,
            enabled: lessonFields,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4)
            ],
            decoration: const InputDecoration(isDense: true, hintText: 'מספר'),
          ),
        )),
        DataCell(SizedBox(
          width: 190,
          child: TextField(
            key: ValueKey('zip-parasha-$path'),
            controller: row.parasha,
            enabled: lessonFields,
            decoration:
                const InputDecoration(isDense: true, hintText: 'ללא פרשה'),
          ),
        )),
        DataCell(SizedBox(
          width: 110,
          child: DropdownButtonFormField<String>(
            key: ValueKey('zip-kind-$path'),
            initialValue: row.parashaKind,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: const [
              DropdownMenuItem(value: 'weekly', child: Text('פרשה')),
              DropdownMenuItem(value: 'event', child: Text('אירוע')),
            ],
            onChanged: lessonFields
                ? (value) => setState(() => row.parashaKind = value ?? 'weekly')
                : null,
          ),
        )),
        // תאריך: לועזי / עברי + בחירה
        DataCell(SizedBox(
          width: 190,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('zip-datekind-$path'),
                  initialValue: row.dateKind,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('תאריך לועזי')),
                    DropdownMenuItem(value: 'h', child: Text('תאריך עברי')),
                  ],
                  onChanged: dateFields
                      ? (value) => setState(() => row.dateKind = value ?? 'g')
                      : null,
                ),
                TextButton.icon(
                  key: ValueKey('zip-date-$path'),
                  onPressed: dateFields ? () => _pickDate(row) : null,
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                      row.dateKind == 'h'
                          ? hebrewDate(row.date)
                          : fmtDate(row.date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
        )),
        // זמר (לשיר בלבד)
        DataCell(SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            key: ValueKey(
                'zip-singer-$path-${row.singerId}-${app.singers.length}'),
            initialValue: singerValid ? row.singerId : null,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, hintText: 'בחר זמר'),
            items: [
              for (final singer in app.singers)
                DropdownMenuItem(
                    value: singer.id,
                    child: Text(singer.name, overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(
                  value: _newSingerValue, child: Text('+ זמר חדש…')),
            ],
            onChanged: songFields
                ? (value) {
                    if (value == _newSingerValue) {
                      _addSinger(row);
                    } else {
                      setState(() => row.singerId = value);
                    }
                  }
                : null,
          ),
        )),
        DataCell(SizedBox(
          width: 80,
          child: TextField(
            key: ValueKey('zip-year-$path'),
            controller: row.year,
            enabled: songFields,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4)
            ],
            decoration: const InputDecoration(isDense: true, hintText: 'שנה'),
          ),
        )),
        DataCell(SizedBox(
          width: 150,
          child: TextField(
            key: ValueKey('zip-location-$path'),
            controller: row.location,
            enabled: songFields,
            decoration: const InputDecoration(isDense: true, hintText: 'מקום'),
          ),
        )),
        DataCell(SizedBox(
          width: 110,
          child: TextButton.icon(
            key: ValueKey('zip-lyrics-$path'),
            onPressed: songFields ? () => _editLyrics(row) : null,
            icon: Icon(
                row.lyrics.trim().isEmpty
                    ? Icons.edit_note_rounded
                    : Icons.check_circle_outline_rounded,
                size: 18),
            label: Text(row.lyrics.trim().isEmpty ? 'הוסף' : 'ערוך'),
          ),
        )),
        DataCell(SizedBox(
          width: 190,
          child: TextField(
            key: ValueKey('zip-notes-$path'),
            controller: row.notes,
            enabled: dateFields,
            decoration: const InputDecoration(isDense: true, hintText: 'הערות'),
          ),
        )),
        DataCell(Checkbox(
          key: ValueKey('zip-skip-$path'),
          value: row.skip,
          onChanged: (value) => setState(() => row.skip = value ?? false),
        )),
    ];
    final visible = _visibleCols;
    return DataRow.byIndex(
      index: index,
      color: WidgetStateProperty.resolveWith((states) {
        if (row.skip) return Theme.of(context).colorScheme.surfaceContainerHighest;
        if (_isDuplicate(row)) {
          return Theme.of(context).colorScheme.errorContainer.withValues(alpha: .35);
        }
        return null;
      }),
      cells: [
        for (var i = 0; i < all.length; i++)
          if (visible.contains(i)) all[i],
      ],
    );
  }
}

class _ZipImportRow {
  final ZipEntry entry;
  final TextEditingController title;
  final TextEditingController number = TextEditingController();
  final TextEditingController parasha = TextEditingController();
  final TextEditingController year = TextEditingController();
  final TextEditingController location = TextEditingController();
  final TextEditingController notes = TextEditingController();
  String parashaKind = 'weekly';
  String dateKind = 'g';
  DateTime date = DateTime.now();
  String lyrics = '';
  String? singerId;
  ZipImportTarget target;
  bool skip = false;

  _ZipImportRow(this.entry, this.target)
      : title = TextEditingController(text: _titleFromPath(entry.path));

  void dispose() {
    title.dispose();
    number.dispose();
    parasha.dispose();
    year.dispose();
    location.dispose();
    notes.dispose();
  }
}

String _titleFromPath(String path) {
  final name = path.split('/').last;
  return name.replaceFirst(RegExp(r'\.[^.]+$'), '');
}
