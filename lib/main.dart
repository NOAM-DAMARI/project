import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/shell.dart';
import 'services/app_state.dart';
import 'services/storage.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupGate());
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _loading = true;
  bool _ready = false;
  Object? _startupError;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted && !_loading) {
      setState(() {
        _loading = true;
        _startupError = null;
      });
    }
    try {
      await initStorage();
      await app.load();
      // שמירה מיידית כשהאפליקציה עוברת לרקע/נסגרת
      _lifecycleListener ??= AppLifecycleListener(onStateChange: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.detached) {
          unawaited(app.flushNow());
        }
      });
      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
        _startupError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('[startup] $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _startupError = error;
      });
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const MyApp();
    return MaterialApp(
      title: 'מערכת לשיעורים',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _startupError == null
                          ? Icons.library_music_rounded
                          : Icons.error_outline_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _startupError == null
                          ? 'מערכת לשיעורים'
                          : 'לא הצלחנו לפתוח את האפליקציה',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_startupError == null) ...[
                      const SizedBox(height: 4),
                      const Text('Manages lessons and songs',
                          textDirection: TextDirection.ltr),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _startupError == null
                          ? 'נטענים השיעורים, השירים והנתונים…'
                          : 'אפשר לנסות שוב. פרטי השגיאה מוצגים כאן במקום מסך ריק.',
                      textAlign: TextAlign.center,
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(),
                    ],
                    if (_startupError != null) ...[
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            _startupError.toString(),
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _loading ? null : _initialize,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('נסה שוב'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  // מאזינים רק למצב כהה – לא לכל שמירה. האזנה ל-app כולו בנתה את כל האפליקציה מחדש בכל הקשה.
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: app.darkMode,
        builder: (_, dark, __) => MaterialApp(
          title: 'מערכת לשיעורים',
          debugShowCheckedModeBanner: false,
          locale: const Locale('he'),
          supportedLocales: const [Locale('he'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scrollBehavior:
              const MaterialScrollBehavior().copyWith(scrollbars: true),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: const Shell(),
        ),
      );
}
