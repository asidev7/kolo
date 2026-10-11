import 'app/app_config.dart';
import 'app/bootstrap.dart';

/// Point d'entrée par défaut : flavor `dev`.
/// Voir aussi `main_dev.dart` et `main_prod.dart`.
Future<void> main() => bootstrap(Flavor.dev);
