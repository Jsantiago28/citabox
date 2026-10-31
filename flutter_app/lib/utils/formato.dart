// Formatos en español sin depender de intl: moneda, fechas y horas.

const _dias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// Meses en minúscula, para frases ("25 de diciembre").
const nombresMeses = _meses;

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String simboloMoneda(String codigo) => switch (codigo.toUpperCase()) {
  'DOP' => r'RD$',
  'USD' => r'US$',
  'MXN' || 'COP' || 'ARS' || 'CLP' => r'$',
  'EUR' => '€',
  _ => '$codigo ',
};

/// 8450 → RD$8,450 · 99.5 → RD$99.50
String formatoMoneda(num monto, [String codigo = 'DOP']) {
  final negativo = monto < 0;
  final centavos = (monto.abs() * 100).round();
  final entero = centavos ~/ 100;
  final decimales = centavos % 100;

  final digitos = entero.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digitos[i]);
  }
  if (decimales != 0) {
    buffer.write('.${decimales.toString().padLeft(2, '0')}');
  }

  return '${negativo ? '-' : ''}${simboloMoneda(codigo)}$buffer';
}

/// Viernes 18 de septiembre
String formatoFechaLarga(DateTime fecha) =>
    '${_dias[fecha.weekday - 1]} ${fecha.day} de ${_meses[fecha.month - 1]}';

/// 2026-09-18 (formato de columna `date` en Postgres)
String formatoFechaIso(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

/// 18 de septiembre de 2026 · 1 – 31 de octubre de 2026 ·
/// 28 de septiembre – 4 de octubre de 2026
String formatoRangoFechas(DateTime desde, DateTime hasta) {
  String dia(DateTime f) => '${f.day} de ${_meses[f.month - 1]}';
  if (desde.year != hasta.year) {
    return '${dia(desde)} de ${desde.year} – ${dia(hasta)} de ${hasta.year}';
  }
  if (desde.month != hasta.month) {
    return '${dia(desde)} – ${dia(hasta)} de ${hasta.year}';
  }
  if (desde.day != hasta.day) {
    return '${desde.day} – ${dia(hasta)} de ${hasta.year}';
  }
  return '${dia(desde)} de ${desde.year}';
}

/// 18/9
String formatoDiaMes(DateTime fecha) => '${fecha.day}/${fecha.month}';

/// '15:00:00' → '3:00 PM'
String formatoHora(String hora) {
  final partes = hora.split(':');
  if (partes.length < 2) return hora;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null) return hora;

  final sufijo = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $sufijo';
}

/// 'Juan Pérez' → 'JP'
String iniciales(String nombre) {
  final partes = nombre
      .trim()
      .split(RegExp(r'\s+'))
      .where((parte) => parte.isNotEmpty)
      .toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes.first[0].toUpperCase();
  return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
}

/// 30 -> '30', 12.5 -> '12.5'.
String textoNumero(num valor) =>
    valor == valor.roundToDouble() ? valor.toInt().toString() : '$valor';

/// 30 -> '30%'; 0 -> 'Sin comisión'.
String textoPorcentaje(num pct) =>
    pct == 0 ? 'Sin comisión' : '${textoNumero(pct)}%';
