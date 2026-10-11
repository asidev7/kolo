import 'app/app_config.dart';
import 'app/bootstrap.dart';

/// `flutter run -t lib/main_dev.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000`
Future<void> main() => bootstrap(Flavor.dev);
