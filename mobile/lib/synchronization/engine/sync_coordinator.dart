import 'dart:async';

import 'package:flutter/widgets.dart';

import 'sync_engine.dart';

/// Décide **quand** synchroniser, jamais comment (§4.6).
///
/// Les déclencheurs sont nombreux et se chevauchent — l'utilisateur enchaîne
/// les saisies, l'application revient au premier plan, le réseau revient :
/// sans regroupement, on enverrait dix fois de suite le même lot. Un délai de
/// 2 s absorbe la rafale, et le moteur n'accepte qu'un cycle à la fois.
class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator({
    required this.engine,
    this.debounce = const Duration(seconds: 2),
    this.onStart,
    this.onFinish,
  });

  /// Le moteur : ce fichier ne décide que du **moment**.
  final SyncEngine engine;

  /// Temps laissé à l'utilisateur pour enchaîner une saisie avant l'envoi.
  final Duration debounce;

  final VoidCallback? onStart;
  final void Function(SyncReport report)? onFinish;

  Timer? _timer;
  Future<SyncReport>? _current;
  bool _again = false;
  bool _observing = false;

  /// S'abonne au cycle de vie de l'application (retour au premier plan).
  void start() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  /// Après chaque écriture locale validée (§4.2).
  ///
  /// L'écriture, elle, n'attend **jamais** le réseau : elle est déjà en base,
  /// le départ vers le serveur peut prendre deux secondes de plus.
  void onLocalWrite() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(syncNow()));
  }

  /// Le réseau vient de revenir : c'est le moment de vider l'outbox.
  void onConnectivityRestored() {
    _timer?.cancel();
    unawaited(syncNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncNow());
  }

  /// Demande un cycle. Si un cycle tourne déjà, il en repartira un à la fin :
  /// une modification faite pendant l'envoi ne doit pas attendre le prochain
  /// déclencheur.
  Future<SyncReport> syncNow() {
    final current = _current;
    if (current != null) {
      _again = true;
      return current;
    }
    final future = _cycle();
    _current = future;
    return future;
  }

  Future<SyncReport> _cycle() async {
    onStart?.call();
    try {
      SyncReport report;
      do {
        _again = false;
        report = await engine.syncNow();
      } while (_again);
      onFinish?.call(report);
      return report;
    } finally {
      _current = null;
    }
  }
}
