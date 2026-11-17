import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/formats.dart';
import '../widgets/plan_summary.dart';

/// Öffnet das rein lesende Sheet „Planung ansehen“.
///
/// Nur für zukünftige (oder noch nicht erfasste) Sitzungen gedacht: es gibt
/// bewusst **keine** Eingabefelder, keinen Status und kein Speichern – nur
/// Tagesdatum, Plan-Inhalt und die vollständige Beschreibung.
Future<void> showPlanDetailSheet(
  BuildContext context, {
  required Plan plan,
  required Session session,
  required DateTime date,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PlanDetailSheet(plan: plan, session: session, date: date),
  );
}

/// Rein lesendes Sheet „Planung ansehen“ (kein Speichern, kein Status).
class PlanDetailSheet extends StatelessWidget {
  const PlanDetailSheet({
    super.key,
    required this.plan,
    required this.session,
    required this.date,
  });

  final Plan plan;
  final Session session;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      key: const Key('planDetailSheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Planung ansehen',
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        formatDateGerman(date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: PlanSummary(
                plan: plan,
                session: session,
                heading: 'Planung',
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: <Widget>[
                const Spacer(),
                TextButton(
                  key: const Key('planDetailCloseButton'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Schließen'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
