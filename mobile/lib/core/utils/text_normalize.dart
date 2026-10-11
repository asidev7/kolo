/// Normalisation pour la recherche insensible à la casse et aux accents
/// (§3.F) : SQLite ne sait pas comparer « Zémidjan » et « zemidjan ».
String normalizeForSearch(String input) {
  final lower = input.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Échappe `%`, `_` et `\` pour une clause `LIKE ... ESCAPE '\'`.
String escapeLike(String input) =>
    input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

const Map<String, String> _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ẹ': 'e', 'ɛ': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ọ': 'o', 'ɔ': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
};
