import 'package:flutter/material.dart';

import '../../app/theme/kolo_colors.dart';
import '../../app/theme/kolo_tokens.dart';
import '../../synchronization/engine/sync_badge_state.dart';

// L'état du badge est un modèle pur, défini dans le moteur : le badge se
// contente de le dessiner. Réexporté pour que les écrans n'aient qu'un import.
export '../../synchronization/engine/sync_badge_state.dart';

class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({required this.state, super.key, this.onTap});

  final SyncBadgeState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label, Color fg, Color bg) = switch (state) {
      SyncBadgeLocal() => (
        Icons.phone_android_rounded,
        'Mode local',
        KoloColors.textSecondary,
        KoloColors.border,
      ),
      SyncBadgeSynced() => (
        Icons.cloud_done_rounded,
        'Synchronisé',
        KoloColors.positive,
        KoloColors.positiveSoft,
      ),
      SyncBadgePending(:final count) => (
        Icons.cloud_upload_rounded,
        '$count en attente',
        KoloColors.primary,
        KoloColors.primarySoft,
      ),
      SyncBadgeOffline() => (
        Icons.cloud_off_rounded,
        'Hors ligne',
        KoloColors.warning,
        KoloColors.warningSoft,
      ),
      SyncBadgeError() => (
        Icons.sync_problem_rounded,
        'Erreur',
        KoloColors.negative,
        KoloColors.negativeSoft,
      ),
      SyncBadgeInProgress() => (
        Icons.sync_rounded,
        'Synchronisation…',
        KoloColors.primary,
        KoloColors.primarySoft,
      ),
      SyncBadgeWaiting() => (
        Icons.cloud_queue_rounded,
        'En attente',
        KoloColors.textSecondary,
        KoloColors.border,
      ),
    };

    return Semantics(
      button: onTap != null,
      label: 'État de synchronisation : $label',
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KoloSpacing.md,
                vertical: KoloSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: KoloSpacing.xs),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
