import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_repository.dart';
import 'activity_sheet.dart';
import 'data_screen.dart';
import 'journal_screen.dart';
import 'today_screen.dart';

/// Rahmen mit NavigationBar: Heute · Tagebuch · Daten.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final warning = repository.storageWarning;

    return Scaffold(
      appBar: AppBar(title: const Text('Tri-Log')),
      body: Column(
        children: <Widget>[
          if (warning != null)
            MaterialBanner(
              leading: const Icon(Icons.warning_amber_rounded),
              content: Text(warning),
              actions: <Widget>[
                TextButton(
                  onPressed: repository.dismissStorageWarning,
                  child: const Text('OK'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const <Widget>[
                TodayScreen(),
                JournalScreen(),
                DataScreen(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              tooltip: 'Ungeplante Einheit erfassen',
              onPressed: () =>
                  showActivityEntrySheet(context, day: repository.now),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Heute',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'Tagebuch',
          ),
          NavigationDestination(
            icon: Icon(Icons.storage_outlined),
            selectedIcon: Icon(Icons.storage),
            label: 'Daten',
          ),
        ],
      ),
    );
  }
}
