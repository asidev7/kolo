import '../errors/failures.dart';

/// Lecture défensive du JSON de l'API.
///
/// Le JSON vient du réseau : une clé manquante ou d'un type inattendu ne doit
/// jamais provoquer une exception Dart brute (l'utilisateur verrait un écran
/// rouge au lieu d'un message). Toute forme inattendue devient un
/// [ApiFailure] que les couches supérieures savent présenter.
extension JsonMap on Map<String, Object?> {
  String requireString(String key) {
    final value = this[key];
    if (value is String) return value;
    throw _invalid(key);
  }

  String? optionalString(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  int requireInt(String key) {
    final value = this[key];
    if (value is int) return value;
    throw _invalid(key);
  }

  int? optionalInt(String key) {
    final value = this[key];
    return value is int ? value : null;
  }

  bool? optionalBool(String key) {
    final value = this[key];
    return value is bool ? value : null;
  }

  /// Objet imbriqué obligatoire (par exemple `user`).
  Map<String, Object?> requireMap(String key) {
    final value = this[key];
    if (value is Map<Object?, Object?>) {
      return {for (final entry in value.entries) '${entry.key}': entry.value};
    }
    throw _invalid(key);
  }

  Map<String, Object?>? optionalMap(String key) {
    final value = this[key];
    if (value == null) return null;
    return requireMap(key);
  }

  /// Liste de chaînes, vide si la clé est absente.
  List<String> optionalStringList(String key) {
    final value = this[key];
    if (value is! List<Object?>) return const [];
    return value.whereType<String>().toList(growable: false);
  }

  /// Liste d'objets, vide si la clé est absente.
  List<Map<String, Object?>> optionalMapList(String key) {
    final value = this[key];
    if (value is! List<Object?>) return const [];
    return [
      for (final item in value)
        if (item is Map<Object?, Object?>)
          {for (final entry in item.entries) '${entry.key}': entry.value},
    ];
  }

  ApiFailure _invalid(String key) => ApiFailure(
    code: 'invalid_response',
    message: 'Réponse inattendue du serveur.',
    fields: {key: 'champ manquant ou invalide'},
  );
}
