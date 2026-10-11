import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` quand l'appareil n'a **aucune** interface réseau active.
///
/// C'est un indice, jamais une preuve que le serveur est joignable (§4.6) :
/// il sert au bandeau hors ligne et à déclencher une tentative de
/// synchronisation, rien de plus.
final isOfflineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool offline(List<ConnectivityResult> r) =>
      r.isEmpty || r.every((c) => c == ConnectivityResult.none);
  try {
    yield offline(await connectivity.checkConnectivity());
  } on Object {
    // Plugin indisponible (tests, plateforme non gérée) : on ne bloque rien.
    yield false;
    return;
  }
  yield* connectivity.onConnectivityChanged.map(offline).distinct();
});
