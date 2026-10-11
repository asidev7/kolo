import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/widgets/tab_scaffold.dart';
import '../../auth/presentation/local_mode_screen.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/settings_keys.dart';

final budgetAlertsEnabledProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .settingsDao
      .watch(SettingsKeys.budgetAlertsEnabled)
      .map((v) => v != 'false'),
);

/// Profil et paramètres (§3.J).
///
/// Menu plat : les entrées sont des `ListTile` séparés par des `Divider`,
/// sans carte autour — plus léger et plus rapide à parcourir.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final config = ref.watch(appConfigProvider);
    final alertsEnabled = ref.watch(budgetAlertsEnabledProvider).value ?? true;
    final currency = ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;
    final theme = Theme.of(context);

    return KoloTabScaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: EdgeInsets.only(bottom: bottomBarInset(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KoloSpacing.lg,
              KoloSpacing.lg,
              KoloSpacing.lg,
              KoloSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: KoloColors.primarySoft,
                  child: Icon(
                    Icons.phone_android_rounded,
                    color: KoloColors.primary,
                  ),
                ),
                const SizedBox(width: KoloSpacing.md),
                Expanded(
                  child: session?.isAccount ?? false
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session?.displayName ?? '',
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              session?.email ?? '',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mode local',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: KoloSpacing.xs),
                            Text(
                              localModeWarning,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const _SectionTitle('Budget et catégories'),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Budget du mois'),
            subtitle: const Text('Plafond et seuils d’alerte'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.budget),
          ),
          const Divider(indent: 56),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Catégories'),
            subtitle: const Text('Ajouter ou archiver'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.categories),
          ),
          const _SectionTitle('Préférences'),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Devise'),
            subtitle: Text('${currency.name} (${currency.code})'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(currency.symbol, style: theme.textTheme.bodySmall),
                const SizedBox(width: KoloSpacing.xs),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () => context.push(Routes.currency),
          ),
          const Divider(indent: 56),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Alertes budget'),
            subtitle: const Text(
              'Une notification quand un seuil est atteint',
            ),
            value: alertsEnabled,
            onChanged: (on) async {
              await ref
                  .read(budgetAlertServiceProvider)
                  .setAlertsEnabled(enabled: on);
              if (on) {
                await ref.read(localNotifierProvider).requestPermission();
              }
            },
          ),
          const _SectionTitle('À propos'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Politique de confidentialité'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.privacy),
          ),
          const Divider(indent: 56),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Version'),
            subtitle: Text(config.versionLabel),
          ),
          const SizedBox(height: KoloSpacing.xl),
          Center(
            child: Text(
              'Développé par ASITECH SOLUTION',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: KoloSpacing.lg),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoloSpacing.xs,
        KoloSpacing.xl,
        KoloSpacing.xs,
        KoloSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}
