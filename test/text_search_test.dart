import 'package:flutter_test/flutter_test.dart';

import 'package:taxi1/utils/text_search.dart';

void main() {
  group('normalizeForSearch', () {
    test('quita tildes, eñes y mayúsculas', () {
      expect(normalizeForSearch('Estación Quilpué'), 'estacion quilpue');
      expect(normalizeForSearch('PEÑABLANCA'), 'penablanca');
      expect(normalizeForSearch('Güemes'), 'guemes');
    });

    test('colapsa los espacios', () {
      expect(normalizeForSearch('  Plaza   de  Armas '), 'plaza de armas');
    });
  });

  group('matchesAllTokens', () {
    test('encuentra sin tildes lo que se guardó con tildes', () {
      // El caso real: casi nadie escribe "Líder" con tilde en el teléfono.
      expect(matchesAllTokens('lider', ['Supermercado Líder Belloto']), isTrue);
      expect(matchesAllTokens('estacion', ['Estación Quilpué']), isTrue);
    });

    test('no le importa el orden de las palabras', () {
      expect(
        matchesAllTokens('belloto lider', ['Supermercado Líder Belloto']),
        isTrue,
      );
    });

    test('busca en todos los campos a la vez', () {
      expect(
        matchesAllTokens('hospital quilpue', [
          'Hospital de Quilpué',
          'San Martín 1270, Quilpué',
        ]),
        isTrue,
      );
      expect(
        matchesAllTokens('freire 2414', [
          'Portal Belloto',
          'Av. Ramón Freire 2414',
        ]),
        isTrue,
      );
    });

    test('exige todas las palabras', () {
      expect(matchesAllTokens('lider pompeya', ['Líder Belloto']), isFalse);
    });

    test('una consulta vacía coincide con todo', () {
      expect(matchesAllTokens('   ', ['Cualquier cosa']), isTrue);
    });
  });
}
