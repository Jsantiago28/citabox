import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/utils/horario_cita.dart';

// 2026-11-01 es domingo; 2026-11-02, lunes.
final _lunes = DateTime(2026, 11, 2);
const _negocio = {
  1: (desde: 9 * 60, hasta: 18 * 60),
  2: (desde: 9 * 60, hasta: 18 * 60),
  3: (desde: 9 * 60, hasta: 18 * 60),
};

String? _aviso(
  DateTime fecha,
  int inicio,
  int fin, {
  Map<int, Rango> empleado = const {},
  List<Bloqueo> bloqueos = const [],
}) => avisoFueraDeHorario(
  fecha: fecha,
  inicio: inicio,
  fin: fin,
  negocio: _negocio,
  empleado: empleado,
  bloqueos: bloqueos,
  persona: 'Luis',
);

void main() {
  test('dentro del horario no avisa', () {
    expect(_aviso(_lunes, 10 * 60, 10 * 60 + 30), isNull);
    // Termina justo al cierre.
    expect(_aviso(_lunes, 17 * 60 + 30, 18 * 60), isNull);
  });

  test('día cerrado y fuera del horario del negocio', () {
    expect(
      _aviso(DateTime(2026, 11, 1), 10 * 60, 10 * 60 + 30),
      'El negocio está cerrado los domingos.',
    );
    expect(
      _aviso(_lunes, 17 * 60 + 45, 18 * 60 + 15),
      'Fuera del horario del negocio (9:00 AM – 6:00 PM).',
    );
    expect(
      _aviso(_lunes, 8 * 60, 8 * 60 + 30),
      'Fuera del horario del negocio (9:00 AM – 6:00 PM).',
    );
  });

  test('horario propio de la persona, recortado al del negocio', () {
    const soloLunes = {1: (desde: 8 * 60, hasta: 14 * 60)};
    expect(
      _aviso(DateTime(2026, 11, 3), 10 * 60, 10 * 60 + 30, empleado: soloLunes),
      'Luis no trabaja los martes.',
    );
    expect(
      _aviso(_lunes, 14 * 60, 14 * 60 + 30, empleado: soloLunes),
      'Fuera del horario de Luis (9:00 AM – 2:00 PM).',
    );
    expect(_aviso(_lunes, 13 * 60, 13 * 60 + 30, empleado: soloLunes), isNull);
  });

  test('día libre', () {
    final vacaciones = [
      (desde: DateTime(2026, 11, 1), hasta: DateTime(2026, 11, 3), motivo: ''),
    ];
    expect(
      _aviso(_lunes, 10 * 60, 10 * 60 + 30, bloqueos: vacaciones),
      'Luis tiene ese día libre.',
    );
    expect(
      _aviso(
        _lunes,
        10 * 60,
        10 * 60 + 30,
        bloqueos: [(desde: _lunes, hasta: _lunes, motivo: 'Médico')],
      ),
      'Luis tiene ese día libre (Médico).',
    );
    expect(
      _aviso(
        DateTime(2026, 11, 4),
        10 * 60,
        10 * 60 + 30,
        bloqueos: vacaciones,
      ),
      isNull,
    );
  });

  test('sin horario del negocio configurado no avisa', () {
    expect(
      avisoFueraDeHorario(
        fecha: _lunes,
        inicio: 2 * 60,
        fin: 3 * 60,
        negocio: const {},
      ),
      isNull,
    );
  });
}
