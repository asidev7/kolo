import 'app/app_config.dart';
import 'app/bootstrap.dart';

/// `flutter build apk -t lib/main_prod.dart --dart-define=API_BASE_URL=https://…`
Future<void> main() => bootstrap(Flavor.prod);
