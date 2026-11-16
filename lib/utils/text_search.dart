/// Comparación de texto para los buscadores de la app.
///
/// Los tres buscadores (destinos del mapa, lista de paraderos y paraderos del
/// administrador) comparaban con `toLowerCase().contains(...)`. En un teléfono
/// casi nadie escribe tildes, así que "lider", "estacion" o "quilpue" no
/// encontraban "Líder", "Estación" ni "Quilpué", y "belloto lider" no
/// encontraba "Líder Belloto" por el orden de las palabras.
library;

const Map<String, String> _sinTilde = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
};

final RegExp _espacios = RegExp(r'\s+');

/// Minúsculas y sin tildes, con los espacios colapsados.
String normalizeForSearch(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_sinTilde[char] ?? char);
  }
  return buffer.toString().trim().replaceAll(_espacios, ' ');
}

/// Si **cada** palabra de [query] aparece en alguno de los [fields].
///
/// Por palabras y no como subcadena entera: así el orden en que se escriben no
/// importa ("belloto lider" encuentra "Supermercado Líder Belloto"). Una
/// consulta vacía coincide con todo.
bool matchesAllTokens(String query, Iterable<String> fields) =>
    containsAllTokens(
      fields.map(normalizeForSearch).join(' '),
      searchTokens(query),
    );

/// Las palabras de [query], ya normalizadas.
///
/// Junto con [containsAllTokens] sirve para buscar en listas largas, como las
/// 25 mil calles del índice offline: se normaliza cada texto una sola vez al
/// cargar, en vez de en cada tecla.
List<String> searchTokens(String query) => normalizeForSearch(
  query,
).split(' ').where((t) => t.isNotEmpty).toList(growable: false);

/// Si cada una de [tokens] aparece en [normalizedHaystack], que tiene que
/// venir ya pasado por [normalizeForSearch].
bool containsAllTokens(String normalizedHaystack, List<String> tokens) =>
    tokens.every(normalizedHaystack.contains);
