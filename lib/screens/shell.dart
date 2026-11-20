import 'package:flutter/material.dart';

import '../widgets/mini_player.dart';
import 'dashboard_screen.dart';
import 'dj_screen.dart';
import 'files_screen.dart';
import 'lessons_dashboard_screen.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  static const lessonsOnly = true;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationDestination>[
      if (!Shell.lessonsOnly)
        const NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'שירים'),
      const NavigationDestination(
          icon: Icon(Icons.school_outlined),
          selectedIcon: Icon(Icons.school_rounded),
          label: 'שיעורים'),
      if (!Shell.lessonsOnly)
        const NavigationDestination(
            icon: Icon(Icons.graphic_eq_rounded),
            selectedIcon: Icon(Icons.equalizer_rounded),
            label: 'DJ'),
      const NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: 'קבצים'),
      const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'הגדרות'),
    ];
    final pages = <Widget>[
      if (!Shell.lessonsOnly) const Dashboard(),
      const LessonsDashboard(),
      if (!Shell.lessonsOnly) const DjScreen(),
      const FilesScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: i, children: pages),
      bottomNavigationBar: WithMiniPlayer(
        bottom: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (value) => setState(() => i = value),
          destinations: destinations,
        ),
      ),
    );
  }
}
