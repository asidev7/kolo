import 'package:flutter/material.dart';

import '../../app/theme/kolo_tokens.dart';
import '../utils/date_format.dart';
import '../utils/local_date.dart';

/// Sélecteur de mois : mois courant par défaut, navigation vers les mois
/// précédents ; jamais au-delà du mois courant.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    required this.value,
    required this.current,
    required this.onChanged,
    super.key,
  });

  final YearMonth value;
  final YearMonth current;
  final ValueChanged<YearMonth> onChanged;

  @override
  Widget build(BuildContext context) {
    final canGoForward = value.compareTo(current) < 0;
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Mois précédent',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => onChanged(value.addMonths(-1)),
        ),
        Flexible(
          child: Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: KoloSpacing.xs),
              child: Text(
                value == current ? 'Ce mois-ci' : KoloDates.monthLabel(value),
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Mois suivant',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: canGoForward ? () => onChanged(value.addMonths(1)) : null,
        ),
      ],
    );
  }
}
