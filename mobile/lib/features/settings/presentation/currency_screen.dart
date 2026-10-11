import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/providers/core_providers.dart';
import '../data/settings_keys.dart';

/// Choix de la devise d'affichage et de saisie (§5.1).
///
/// La devise est une préférence globale : montants affichés, saisie et
/// nouvelles opérations utilisent le même code. Changer de devise ne convertit
/// pas les montants existants, il les relit dans la nouvelle devise.
class CurrencyScreen extends ConsumerWidget {
  const CurrencyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;

    Future<void> select(String code) async {
      if (code == selected.code) return;
      await ref
          .read(databaseProvider)
          .settingsDao
          .write(SettingsKeys.currencyCode, code);
      if (context.mounted) context.pop();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Devise')),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: KoloSpacing.sm),
          itemCount: Currencies.all.length,
          itemBuilder: (context, index) {
            final currency = Currencies.all[index];
            final isSelected = currency.code == selected.code;
            return ListTile(
              title: Text(currency.name),
              subtitle: Text('${currency.symbol} · ${currency.code}'),
              trailing: Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected ? KoloColors.primary : null,
              ),
              onTap: () => select(currency.code),
            );
          },
        ),
      ),
    );
  }
}
