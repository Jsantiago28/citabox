import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/services/ficha_cliente.dart';

Cita _cita(
  String id,
  String fecha,
  EstadoCita estado, {
  String hora = '10:00:00',
  num precio = 500,
  String servicioId = 's1',
  String servicio = 'Corte',
  String empleadoId = 'e1',
  String barbero = 'Carlos',
}) => Cita(
  id: id,
  fecha: fecha,
  horaInicio: hora,
  precio: precio,
  estado: estado,
  servicioId: servicioId,
  servicioNombre: servicio,
  empleadoId: empleadoId,
  empleadoNombre: barbero,
);

void main() {
  final ahora = DateTime(2026, 10, 27, 12, 30);

  test('sin citas todo queda en cero', () {
    final ficha = calcularFichaCliente(const [], ahora: ahora);

    expect(ficha.visitas, 0);
    expect(ficha.gastoTotal, 0);
    expect(ficha.ticketPromedio, 0);
    expect(ficha.ultimaVisita, isNull);
    expect(ficha.proximaCita, isNull);
    expect(ficha.servicioFavorito, isNull);
    expect(ficha.barberoFavorito, isNull);
    expect(ficha.conFaltas, isFalse);
    expect(ficha.frecuente, isFalse);
  });

  test('visitas, gasto y ticket solo cuentan LLEGO y COMPLETADA', () {
    final ficha = calcularFichaCliente([
      _cita('a', '2026-09-01', EstadoCita.completada, precio: 500),
      _cita('b', '2026-09-15', EstadoCita.llego, precio: 750.5),
      _cita('c', '2026-09-20', EstadoCita.noVino, precio: 900),
      _cita('d', '2026-09-25', EstadoCita.cancelada, precio: 900),
      _cita('e', '2026-08-25', EstadoCita.pendiente, precio: 900),
    ], ahora: ahora);

    expect(ficha.visitas, 2);
    expect(ficha.gastoTotal, 1250.5);
    expect(ficha.ticketPromedio, 625.25);
    expect(ficha.faltas, 1);
    expect(ficha.cancelaciones, 1);
    expect(ficha.ultimaVisita?.id, 'b');
  });

  test('con 2 faltas o más se avisa', () {
    final una = calcularFichaCliente([
      _cita('a', '2026-09-01', EstadoCita.noVino),
    ], ahora: ahora);
    final dos = calcularFichaCliente([
      _cita('a', '2026-09-01', EstadoCita.noVino),
      _cita('b', '2026-09-02', EstadoCita.noVino),
    ], ahora: ahora);

    expect(una.conFaltas, isFalse);
    expect(dos.conFaltas, isTrue);
  });

  test('próxima cita: la pendiente o confirmada más cercana desde ahora', () {
    final ficha = calcularFichaCliente([
      _cita('pasada', '2026-10-27', EstadoCita.pendiente, hora: '09:00:00'),
      _cita('lejana', '2026-12-01', EstadoCita.confirmada),
      _cita('cancelada', '2026-10-28', EstadoCita.cancelada),
      _cita('hoy', '2026-10-27', EstadoCita.confirmada, hora: '15:00:00'),
    ], ahora: ahora);

    expect(ficha.proximaCita?.id, 'hoy');
  });

  test('favoritos: el más repetido; si empatan, el más reciente', () {
    final ficha = calcularFichaCliente([
      _cita('a', '2026-01-01', EstadoCita.completada),
      _cita('b', '2026-02-01', EstadoCita.completada),
      _cita(
        'c',
        '2026-03-01',
        EstadoCita.completada,
        servicioId: 's2',
        servicio: 'Barba',
        empleadoId: 'e2',
        barbero: 'Pedro',
      ),
      _cita(
        'd',
        '2026-04-01',
        EstadoCita.llego,
        servicioId: 's2',
        servicio: 'Barba',
      ),
      // Las faltas no cuentan para favoritos.
      for (var i = 0; i < 5; i++)
        _cita(
          'n$i',
          '2026-05-0${i + 1}',
          EstadoCita.noVino,
          servicioId: 's3',
          servicio: 'Tinte',
          empleadoId: 'e3',
          barbero: 'Luis',
        ),
    ], ahora: ahora);

    expect(ficha.servicioFavorito, 'Barba');
    expect(ficha.barberoFavorito, 'Carlos');
  });

  test('frecuente desde 10 visitas', () {
    final ficha = calcularFichaCliente([
      for (var i = 1; i <= 10; i++)
        _cita(
          'v$i',
          '2026-01-${i.toString().padLeft(2, '0')}',
          EstadoCita.completada,
        ),
    ], ahora: ahora);

    expect(ficha.visitas, 10);
    expect(ficha.frecuente, isTrue);
  });

  test('el historial queda de más reciente a más antiguo', () {
    final historial = ordenarHistorial([
      _cita('a', '2026-01-01', EstadoCita.completada),
      _cita('c', '2026-03-01', EstadoCita.completada, hora: '09:00:00'),
      _cita('d', '2026-03-01', EstadoCita.completada, hora: '16:00:00'),
      _cita('b', '2026-02-01', EstadoCita.completada),
    ]);

    expect(historial.map((cita) => cita.id), ['d', 'c', 'b', 'a']);
  });
}
