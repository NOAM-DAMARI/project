import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../utils/helpers.dart';
import '../utils/parashot.dart';

typedef ParashaSelection = ({String value, bool isEvent});

class ParashaPicker extends StatefulWidget {
  final String value;
  final bool isEvent;
  final ValueChanged<ParashaSelection> onChanged;

  const ParashaPicker(
      {super.key,
      required this.value,
      required this.isEvent,
      required this.onChanged});

  @override
  State<ParashaPicker> createState() => _ParashaPickerState();
}

class _ParashaPickerState extends State<ParashaPicker> {
  late String activeBook;

  @override
  void initState() {
    super.initState();
    activeBook = bookForParasha(widget.value) ?? 'בראשית';
  }

  @override
  void didUpdateWidget(covariant ParashaPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.isEvent != widget.isEvent) {
      activeBook = bookForParasha(widget.value) ??
          (widget.isEvent ? 'אירועים' : 'בראשית');
    }
  }

  Future<void> _addCustomEvent() async {
    final value = await askText(context, 'שם האירוע או הפרשייה החדשה');
    if (!mounted || value == null || value.trim().isEmpty) return;
    final name = value.trim();
    await app.addCustomParasha(name);
    if (!mounted) return;
    setState(() => activeBook = 'אירועים');
    widget.onChanged((value: name, isEvent: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = [...parashotByBook.keys, 'אירועים'];
    final values = activeBook == 'אירועים'
        ? [...holidayParashot, ...app.customParashot]
        : (parashotByBook[activeBook] ?? const <String>[]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('בחירת חומש', style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final book in books)
          ChoiceChip(
            label: Text(book == 'אירועים' ? 'אירועים / אישי' : book),
            selected: activeBook == book,
            onSelected: (_) => setState(() => activeBook = book),
          ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final value in values)
          ChoiceChip(
            label: Text(value),
            selected: widget.value == value,
            onSelected: (_) => widget
                .onChanged((value: value, isEvent: activeBook == 'אירועים')),
          ),
        if (activeBook == 'אירועים')
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: const Text('הוסף אירוע / פרשייה'),
            onPressed: _addCustomEvent,
          ),
      ]),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton.icon(
          onPressed: widget.value.isEmpty
              ? null
              : () => widget.onChanged((value: '', isEvent: false)),
          icon: const Icon(Icons.clear_rounded),
          label: const Text('ללא בחירה'),
        ),
      ),
    ]);
  }
}
