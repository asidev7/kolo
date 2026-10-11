/// Variante de build (§1.1, flavors).
enum Flavor { dev, prod }

/// Configuration figée au lancement.
///
/// L'URL de l'API vient **uniquement** de
/// `--dart-define=API_BASE_URL=...` : jamais codée en dur pour la prod (§13).
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.version,
    required this.buildNumber,
  });

  factory AppConfig.fromEnvironment(Flavor flavor) => AppConfig(
    flavor: flavor,
    apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
    version: const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0'),
    buildNumber: const String.fromEnvironment(
      'APP_BUILD_NUMBER',
      defaultValue: '1',
    ),
  );

  final Flavor flavor;

  /// Vide si non fourni : la création de compte est alors indisponible et
  /// l'application fonctionne en mode local uniquement.
  final String apiBaseUrl;

  final String version;
  final String buildNumber;

  bool get hasBackend => apiBaseUrl.isNotEmpty;

  String get versionLabel => '$version (build $buildNumber)';
}
