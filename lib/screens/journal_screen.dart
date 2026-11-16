import 'package:flutter/material.dart';

/// Platzhalter – die echte Tagebuch-Oberfläche folgt in einer späteren Phase.
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.book_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('Tagebuch folgt.', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
