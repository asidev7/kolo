import 'dart:convert';

import '../../core/utils/time_source.dart';
import '../../database/app_database.dart';

/// Verrou de synchronisation partagé entre isolate.
///
/// Le mutex du moteur (un `Future` partagé) ne protège que le processus
/// courant : la tâche de fond de WorkManager tourne dans un **autre isolate**,
/// avec sa propre connexion à la même base. Sans ce verrou, les deux cycles
/// pourraient faire avancer le curseur dans le désordre.
///
/// Verrou **au mieux**, volontairement : la lecture puis l'écriture ne sont pas
/// atomiques, et une expiration est préférable à un blocage définitif (une
/// application tuée pendant un cycle ne doit pas empêcher toute
/// synchronisation future). Ce qui protège réellement les données, ce sont
/// l'idempotence du serveur (`op_id`) et le fait qu'un curseur qui recule ne
/// fait que relire des changements déjà appliqués.
class SyncLease {
  SyncLease(
    this._settings,
    this._time, {
    this.ttl = const Duration(minutes: 5),
  });

  /// Clé locale du verrou. Jamais renommée une fois publiée.
  static const String key = 'sync.lease';

  final SettingsDao _settings;
  final TimeSource _time;
  final Duration ttl;

  /// Prend le verrou pour [owner], ou renvoie `false` si un autre cycle est en
  /// cours.
  Future<bool> acquire(String owner) async {
    final now = _time.nowUtc();
    final current = await _read();
    if (current != null &&
        current.owner != owner &&
        current.expiresAt.isAfter(now)) {
      return false;
    }
    await _settings.write(
      key,
      jsonEncode({
        'owner': owner,
        'expires_at': now.add(ttl).toIso8601String(),
      }),
    );
    // Relecture : si deux isolate ont écrit en même temps, seul celui dont le
    // nom est encore là continue.
    final confirmed = await _read();
    return confirmed != null && confirmed.owner == owner;
  }

  /// Libère le verrou s'il est encore le nôtre (sinon on ne touche à rien : il
  /// appartient à un autre cycle).
  Future<void> release(String owner) async {
    final current = await _read();
    if (current == null || current.owner != owner) return;
    await _settings.remove(key);
  }

  Future<_Lease?> _read() async {
    final raw = await _settings.read(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) return null;
      final owner = decoded['owner'];
      final expiresAt = decoded['expires_at'];
      if (owner is! String || expiresAt is! String) return null;
      return _Lease(owner, DateTime.parse(expiresAt));
    } on FormatException {
      return null;
    }
  }
}

class _Lease {
  const _Lease(this.owner, this.expiresAt);

  final String owner;
  final DateTime expiresAt;
}
