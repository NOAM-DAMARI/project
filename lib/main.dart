import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_state.dart';
import 'services/audio_init.dart';
import 'services/storage.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initAudioBackend(); // חייב לפני שנוצר הנגן (Windows/Linux)
  runApp(const StartupGate());
}

/// מסך פתיחה: טוען הגדרות ואת הרשימה השמורה, ואז פותח את האפליקציה.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _error = null);
    try {
      await initStorage();
      await app.load();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const MyApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.headphones_rounded, size: 52),
                const SizedBox(height: 16),
                Text(_error == null ? 'נגן שיעורים' : 'לא הצלחנו לפתוח את האפליקציה',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (_error == null)
                  const CircularProgressIndicator()
                else ...[
                  SelectableText(_error.toString(), textDirection: TextDirection.ltr),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _init, child: const Text('נסה שוב')),
                ],
              ]),
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
  Widget build(BuildContext context) => MaterialApp(
        title: 'נגן שיעורים',
        debugShowCheckedModeBanner: false,
        locale: const Locale('he'),
        supportedLocales: const [Locale('he'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: ThemeMode.system,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: ListenableBuilder(
          listenable: app,
          builder: (_, __) =>
              app.connected ? const HomeScreen() : const ConnectScreen(),
        ),
      );
}
