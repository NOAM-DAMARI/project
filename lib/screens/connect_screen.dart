import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../utils/helpers.dart';

/// מסך "חבר מאגר": בעלים, מאגר, ענף ו-Token.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final _owner = TextEditingController(text: app.githubOwner);
  late final _repo = TextEditingController(text: app.githubRepo);
  late final _branch = TextEditingController(text: app.githubBranch);
  late final _token = TextEditingController(text: app.githubToken);
  bool _busy = false;
  bool _hideToken = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_owner, _repo, _branch, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lib = await app.connect(
          owner: _owner.text,
          repo: _repo.text,
          branch: _branch.text,
          token: _token.text);
      if (!mounted) return;
      snack(context,
          'המאגר חובר: ${lib.lessons.length} שיעורים, ${lib.songs.length} שירים');
      if (Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label,
          {String? hint, bool ltr = true, Widget? suffix, bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration:
              InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix),
          onSubmitted: (_) => _busy ? null : _connect(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('חיבור ל-GitHub')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Icon(Icons.cloud_sync_rounded, size: 48, color: c.primary),
              const SizedBox(height: 12),
              Text(
                'מתחברים לאותו מאגר של האפליקציה המלאה, ורואים את רשימת השיעורים והשירים להשמעה.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _field(_owner, 'בעלים (owner)', hint: 'NOAM-DAMARI'),
              _field(_repo, 'מאגר (repo)', hint: 'LessonSong'),
              _field(_branch, 'ענף (branch)', hint: 'main'),
              _field(
                _token,
                'Token (חובה במאגר פרטי)',
                obscure: _hideToken,
                suffix: IconButton(
                  tooltip: _hideToken ? 'הצג' : 'הסתר',
                  icon: Icon(_hideToken
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _hideToken = !_hideToken),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.error_outline_rounded, color: c.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(color: c.error))),
                  ]),
                ),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.link_rounded),
                label: const Text('חבר מאגר'),
              ),
              if (app.connected) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await app.disconnect();
                          if (context.mounted && Navigator.canPop(context)) {
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('התנתק מהמאגר'),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
