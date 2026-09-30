// Genera un slug compatible con el constraint de la base de datos:
// ^[a-z0-9]+(-[a-z0-9]+)*$
const _acentos = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
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
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

final _slugRegExp = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

String slugify(String texto) {
  final sinAcentos = texto
      .toLowerCase()
      .split('')
      .map((letra) => _acentos[letra] ?? letra)
      .join();

  return sinAcentos
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

bool slugValido(String slug) => _slugRegExp.hasMatch(slug);
