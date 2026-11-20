import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// רכיבי עיצוב משותפים

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: c.primaryContainer.withValues(alpha: .6), shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: c.onPrimaryContainer),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: c.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionTitle(this.text, {super.key, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ]),
      );
}

/// כרטיס כותרת צבעוני בראש מסכי הבית
class HeroHeader extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget? bottom;
  const HeroHeader({super.key, required this.title, required this.subtitle, required this.icon, this.bottom});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(c),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: c.primary.withValues(alpha: .18), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.headlineSmall?.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(subtitle, style: t.bodyMedium?.copyWith(color: c.onPrimary.withValues(alpha: .85))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.onPrimary.withValues(alpha: .15), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: c.onPrimary, size: 28),
          ),
        ]),
        if (bottom != null) ...[const SizedBox(height: 16), bottom!],
      ]),
    );
  }
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final VoidCallback? onTap;
  const StatCard({super.key, required this.icon, required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: c.primary, size: 22),
              const SizedBox(height: 10),
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: c.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// שדה חיפוש עם ניקוי, מסנן בזמן אמת
class SearchField extends StatefulWidget {
  final String hint;
  final String initial;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool onHero;
  const SearchField({super.key, required this.hint, this.initial = '', this.onChanged, this.onSubmitted, this.onHero = false});

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctl,
        textInputAction: TextInputAction.search,
        onChanged: (v) {
          setState(() {});
          widget.onChanged?.call(v);
        },
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: ctl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    ctl.clear();
                    setState(() {});
                    widget.onChanged?.call('');
                  },
                ),
          border: widget.onHero ? OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none) : null,
          enabledBorder:
              widget.onHero ? OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none) : null,
        ),
      );
}

/// תגית קטנה (למשל "בענן", "תומלל")
class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  const Pill(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// כרטיס הגדרות עם כותרת
class SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const SettingsCard({super.key, required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, color: c.primary),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      ),
    );
  }
}
