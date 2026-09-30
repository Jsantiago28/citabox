import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/pages/agenda_page.dart';
import 'package:barberiapro/pages/dashboard_page.dart';
import 'package:barberiapro/services/citas_repository.dart';
import 'package:barberiapro/utils/formato.dart';

void main() {
  test('formats money, dates and times in Spanish', () {
    expect(formatoMoneda(8450), r'RD$8,450');
    expect(formatoMoneda(1234567.5), r'RD$1,234,567.50');
    expect(formatoMoneda(0), r'RD$0');
    expect(formatoMoneda(700, 'USD'), r'US$700');
    expect(
      formatoFechaLarga(DateTime(2026, 9, 18)),
      'Viernes 18 de septiembre',
    );
    expect(formatoFechaIso(DateTime(2026, 9, 8)), '2026-09-08');
    expect(formatoHora('15:00:00'), '3:00 PM');
    expect(formatoHora('00:30'), '12:30 AM');
    expect(formatoHora('12:00:00'), '12:00 PM');
    expect(iniciales('Juan Pérez'), 'JP');
    expect(iniciales('  '), '?');
  });

  testWidgets('dashboard summarizes today and skips cancelled visits', (
    tester,
  ) async {
    final repository = _FakeCitasRepository(_citasDeEjemplo());
    _pantallaAncha(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardPage(
            negocioId: 'n1',
            negocioNombre: 'Barbería El Jefe',
            nombre: 'Juan Rodríguez',
            repository: repository,
            onVerAgenda: () {},
            hoy: DateTime(2026, 9, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hola, Juan 👋'), findsOneWidget);
    expect(find.text('Viernes 18 de septiembre'), findsOneWidget);
    expect(_valorIndicador('Citas hoy'), '4');
    expect(_valorIndicador('Llegaron'), '2');
    expect(_valorIndicador('No-show'), '1');
    expect(_valorIndicador('Ventas hoy'), r'RD$1,200');
    expect(find.text('Cliente cancelado'), findsNothing);
    expect(repository.ultimaFecha, DateTime(2026, 9, 18));
  });

  testWidgets('barber marks arrivals and no-shows from the agenda', (
    tester,
  ) async {
    final repository = _FakeCitasRepository(_citasDeEjemplo());
    _pantallaAncha(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaPage(
            negocioId: 'n1',
            titulo: 'Mi agenda',
            empleadoId: 'e1',
            repository: repository,
            fechaInicial: DateTime(2026, 9, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.ultimoEmpleado, 'e1');
    expect(find.text('Carlos Ruiz'), findsOneWidget);

    await tester.tap(find.text('Llegó').last);
    await tester.pumpAndSettle();
    expect(repository.cambios.last, ('c4', EstadoCita.llego));

    // Tocar de nuevo el mismo estado lo deshace.
    await tester.tap(find.text('Llegó').last);
    await tester.pumpAndSettle();
    expect(repository.cambios.last, ('c4', EstadoCita.pendiente));

    await tester.tap(find.byTooltip('Día siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Sábado 19 de septiembre'), findsOneWidget);
    expect(repository.ultimaFecha, DateTime(2026, 9, 19));
  });

  testWidgets('agenda restores the state when saving fails', (tester) async {
    final repository = _FakeCitasRepository(_citasDeEjemplo(), falla: true);
    _pantallaAncha(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaPage(
            negocioId: 'n1',
            repository: repository,
            fechaInicial: DateTime(2026, 9, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('No vino').last);
    await tester.pumpAndSettle();

    expect(find.text('No se pudo actualizar la cita.'), findsOneWidget);
  });
}

void _pantallaAncha(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

String _valorIndicador(String titulo) {
  final tarjeta = find.ancestor(
    of: find.text(titulo),
    matching: find.byType(Card),
  );
  final textos = find.descendant(of: tarjeta, matching: find.byType(Text));
  return (textos.evaluate().last.widget as Text).data ?? '';
}

List<Cita> _citasDeEjemplo() => const [
  Cita(
    id: 'c1',
    fecha: '2026-09-18',
    horaInicio: '10:00:00',
    precio: 700,
    estado: EstadoCita.llego,
    clienteNombre: 'Juan Pérez',
    servicioNombre: 'Corte + Barba',
    empleadoNombre: 'Luis',
  ),
  Cita(
    id: 'c2',
    fecha: '2026-09-18',
    horaInicio: '10:30:00',
    precio: 500,
    estado: EstadoCita.completada,
    clienteNombre: 'Pedro Gómez',
    servicioNombre: 'Corte',
    empleadoNombre: 'Carlos',
  ),
  Cita(
    id: 'c3',
    fecha: '2026-09-18',
    horaInicio: '11:30:00',
    precio: 250,
    estado: EstadoCita.noVino,
    clienteNombre: 'José Díaz',
    servicioNombre: 'Barba',
    empleadoNombre: 'Pedro',
  ),
  Cita(
    id: 'c4',
    fecha: '2026-09-18',
    horaInicio: '12:00:00',
    precio: 500,
    estado: EstadoCita.pendiente,
    clienteNombre: 'Carlos Ruiz',
    servicioNombre: 'Corte',
    empleadoNombre: 'Luis',
  ),
  Cita(
    id: 'c5',
    fecha: '2026-09-18',
    horaInicio: '12:30:00',
    precio: 900,
    estado: EstadoCita.cancelada,
    clienteNombre: 'Cliente cancelado',
    servicioNombre: 'Tinte',
    empleadoNombre: 'Miguel',
  ),
];

class _FakeCitasRepository implements CitasRepository {
  _FakeCitasRepository(this.citas, {this.falla = false});

  final List<Cita> citas;
  final bool falla;
  final cambios = <(String, EstadoCita)>[];
  DateTime? ultimaFecha;
  String? ultimoEmpleado;

  @override
  Future<List<Cita>> listarDelDia({
    required String negocioId,
    required DateTime fecha,
    String? empleadoId,
  }) async {
    ultimaFecha = fecha;
    ultimoEmpleado = empleadoId;
    return fecha.day == 18 ? citas : const [];
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String citaId,
    required EstadoCita estado,
  }) async {
    if (falla) throw Exception('sin conexión');
    cambios.add((citaId, estado));
  }

  @override
  Future<String?> empleadoDelPerfil({
    required String negocioId,
    required String perfilId,
  }) async => 'e1';
}
