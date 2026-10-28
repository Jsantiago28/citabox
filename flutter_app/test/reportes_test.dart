import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/pages/reportes_page.dart';
import 'package:barberiapro/services/reportes.dart';
import 'package:barberiapro/services/reportes_repository.dart';
import 'package:barberiapro/utils/formato.dart';

final _hoy = DateTime(2026, 10, 27); // martes
final _octubre = Periodo(DateTime(2026, 10, 1), DateTime(2026, 10, 31));

void main() {
  group('Periodo', () {
    test('predefined periods relative to today', () {
      expect(
        Periodo.de(TipoPeriodo.hoy, DateTime(2026, 10, 27, 18, 30)),
        Periodo(_hoy, _hoy),
      );
      expect(
        Periodo.de(TipoPeriodo.semana, _hoy),
        Periodo(DateTime(2026, 10, 26), DateTime(2026, 11, 1)),
      );
      expect(Periodo.de(TipoPeriodo.mes, _hoy), _octubre);
      expect(
        Periodo.de(TipoPeriodo.mesAnterior, _hoy),
        Periodo(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );
      expect(
        Periodo.de(TipoPeriodo.mesAnterior, DateTime(2026, 1, 15)),
        Periodo(DateTime(2025, 12, 1), DateTime(2025, 12, 31)),
      );
      expect(_octubre.dias, hasLength(31));
      expect(
        () => Periodo(DateTime(2026, 10, 2), DateTime(2026, 10, 1)),
        throwsArgumentError,
      );
    });

    test('formats date ranges in Spanish', () {
      expect(formatoRangoFechas(_hoy, _hoy), '27 de octubre de 2026');
      expect(
        formatoRangoFechas(_octubre.desde, _octubre.hasta),
        '1 – 31 de octubre de 2026',
      );
      expect(
        formatoRangoFechas(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
        '28 de septiembre – 4 de octubre de 2026',
      );
      expect(
        formatoRangoFechas(DateTime(2025, 12, 29), DateTime(2026, 1, 4)),
        '29 de diciembre de 2025 – 4 de enero de 2026',
      );
    });
  });

  group('Reporte.calcular', () {
    test('totals match the input appointments', () {
      final reporte = Reporte.calcular(_citasDeEjemplo(), _octubre);

      expect(reporte.totalCitas, 7); // la de septiembre queda fuera
      expect(reporte.porEstado, {
        EstadoCita.pendiente: 1,
        EstadoCita.confirmada: 0,
        EstadoCita.llego: 1,
        EstadoCita.completada: 3,
        EstadoCita.noVino: 1,
        EstadoCita.cancelada: 1,
      });
      expect(reporte.atendidas, 4);
      expect(reporte.ingresos, 2000.75);
      expect(reporte.noShows, 1);
      expect(reporte.tasaNoShow, closeTo(0.2, 1e-9));
      expect(reporte.cancelaciones, 1);
      expect(reporte.apartadosCobrados, 400);
      expect(reporte.ticketPromedio, 500.19);

      expect(
        [
          for (final f in reporte.porBarbero)
            (f.nombre, f.atendidas, f.ingresos),
        ],
        [('Luis', 2, 1200), ('Carlos', 2, 800.75)],
      );
      expect(
        [
          for (final f in reporte.porServicio)
            (f.nombre, f.cantidad, f.ingresos),
        ],
        [('Corte', 2, 1000.5), ('Corte + Barba', 1, 700), ('Barba', 1, 300.25)],
      );
      expect(
        [for (final f in reporte.topClientes) (f.nombre, f.visitas, f.gastado)],
        [('Juan Pérez', 3, 1500.25), ('Pedro Gómez', 1, 500.5)],
      );

      final porDia = {
        for (final d in reporte.ingresosPorDia)
          if (d.ingresos != 0) d.dia: d.ingresos,
      };
      expect(porDia, {
        DateTime(2026, 10, 5): 300.25,
        DateTime(2026, 10, 26): 1200.5,
        DateTime(2026, 10, 27): 500,
      });
      expect(reporte.ingresosPorDia, hasLength(31));
    });

    test('empty period has no rates nor averages', () {
      final reporte = Reporte.calcular(const [], Periodo(_hoy, _hoy));
      expect(reporte.totalCitas, 0);
      expect(reporte.ingresos, 0);
      expect(reporte.tasaNoShow, isNull);
      expect(reporte.ticketPromedio, isNull);
      expect(reporte.topClientes, isEmpty);
      expect(reporte.ingresosPorDia.single.ingresos, 0);
    });

    test('keeps only the 10 most frequent clients', () {
      final citas = [
        for (var c = 0; c < 12; c++)
          for (var v = 0; v <= c; v++)
            _cita(
              'c$c-$v',
              DateTime(2026, 10, 1 + v),
              100,
              EstadoCita.completada,
              cliente: ('k$c', 'Cliente $c'),
            ),
      ];
      final top = Reporte.calcular(citas, _octubre).topClientes;
      expect(top, hasLength(10));
      expect(top.first.nombre, 'Cliente 11');
      expect(top.first.visitas, 12);
      expect(top.last.nombre, 'Cliente 2');
    });

    test('breakdowns always add up to the totals (random data)', () {
      final azar = Random(42);
      const estados = EstadoCita.values;
      final citas = [
        for (var i = 0; i < 600; i++)
          _cita(
            'r$i',
            DateTime(2026, 9, 25 + azar.nextInt(45)),
            azar.nextInt(200000) / 100,
            estados[azar.nextInt(estados.length)],
            empleado: ('e${azar.nextInt(4)}', 'Barbero'),
            servicio: ('s${azar.nextInt(6)}', 'Servicio'),
            cliente: ('k${azar.nextInt(40)}', 'Cliente'),
            apartado: azar.nextBool() ? azar.nextInt(30000) / 100 : 0,
          ),
      ];

      final reporte = Reporte.calcular(citas, _octubre);

      // Totales esperados calculados aparte, en centavos.
      int c(num monto) => (monto * 100).round();
      final delMes = citas.where((x) => x.fecha.month == 10).toList();
      final atendidas = delMes.where((x) => x.estado.atendida).toList();
      final ingresos = atendidas.fold<int>(0, (t, x) => t + c(x.precio));
      final apartados = delMes.fold<int>(0, (t, x) => t + c(x.apartadoPagado));
      final noVino = delMes.where((x) => x.estado == EstadoCita.noVino).length;

      expect(reporte.totalCitas, delMes.length);
      expect(c(reporte.ingresos), ingresos);
      expect(c(reporte.apartadosCobrados), apartados);
      expect(reporte.atendidas, atendidas.length);
      expect(reporte.tasaNoShow, noVino / (atendidas.length + noVino));
      expect(
        reporte.porEstado.values.fold<int>(0, (t, n) => t + n),
        reporte.totalCitas,
      );
      for (final suma in [
        reporte.porBarbero.fold<int>(0, (t, f) => t + c(f.ingresos)),
        reporte.porServicio.fold<int>(0, (t, f) => t + c(f.ingresos)),
        reporte.ingresosPorDia.fold<int>(0, (t, d) => t + c(d.ingresos)),
      ]) {
        expect(suma, ingresos);
      }
      expect(
        reporte.porBarbero.fold<int>(0, (t, f) => t + f.atendidas),
        atendidas.length,
      );
      expect(
        reporte.porServicio.fold<int>(0, (t, f) => t + f.cantidad),
        atendidas.length,
      );
    });

    test('reads appointments and paid deposits from Supabase rows', () {
      final cita = CitaReporte.fromMap({
        'id': 'x1',
        'fecha': '2026-10-27',
        'precio': '650.50',
        'estado': 'COMPLETADA',
        'cliente_id': 'k1',
        'empleado_id': 'e1',
        'servicio_id': 's1',
        'clientes': {'nombre': 'Juan Pérez'},
        'empleados': {'nombre': 'Luis'},
        'servicios': {'nombre': 'Corte'},
        'apartados': [
          {'monto': '100.00', 'estado': 'CANCELADO'},
          {'monto': '150.00', 'estado': 'PAGADO'},
          {'monto': 50, 'estado': 'PENDIENTE'},
        ],
      });
      expect(cita.fecha, _hoy);
      expect(cita.precio, 650.5);
      expect(cita.estado, EstadoCita.completada);
      expect(cita.clienteNombre, 'Juan Pérez');
      expect(cita.empleadoNombre, 'Luis');
      expect(cita.servicioNombre, 'Corte');
      expect(cita.apartadoPagado, 150);
    });
  });

  group('ReportesPage', () {
    testWidgets('owner switches periods and sees the breakdowns', (
      tester,
    ) async {
      final repository = _FakeReportesRepository(_citasDeEjemplo());
      _pantalla(tester, const Size(1280, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportesPage(
              negocioId: 'n1',
              repository: repository,
              hoy: _hoy,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hoy: una completada, un no-show y una cancelada.
      expect(find.text('27 de octubre de 2026'), findsOneWidget);
      expect(_indicador('Ingresos'), r'RD$500');
      expect(_indicador('Citas'), '3');
      expect(_indicador('Tasa de no-show'), '50.0%');
      expect(_indicador('Cancelaciones'), '1');
      expect(_indicador('Apartados cobrados'), r'RD$100');

      await tester.tap(find.text('Este mes'));
      await tester.pumpAndSettle();

      expect(repository.ultimoPeriodo, _octubre);
      expect(repository.ultimoEmpleado, isNull);
      expect(find.text('1 – 31 de octubre de 2026'), findsOneWidget);
      expect(_indicador('Ingresos'), r'RD$2,000.75');
      expect(_indicador('Ticket promedio'), r'RD$500.19');
      expect(_indicador('Apartados cobrados'), r'RD$400');
      expect(_indicador('Tasa de no-show'), '20.0%');
      expect(_indicador('Atendidas'), '4');
      expect(find.text('Por barbero'), findsOneWidget);
      expect(find.text('Luis'), findsOneWidget);
      expect(find.text(r'RD$1,500.25'), findsOneWidget); // Juan, 3 visitas
      expect(find.byType(Tooltip), findsNWidgets(31)); // una barra por día

      await tester.tap(find.text('Mes anterior'));
      await tester.pumpAndSettle();
      expect(
        repository.ultimoPeriodo,
        Periodo(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      );
      expect(_indicador('Ingresos'), r'RD$999');
    });

    testWidgets('barber on a phone only sees his own appointments', (
      tester,
    ) async {
      final repository = _FakeReportesRepository(_citasDeEjemplo());
      _pantalla(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportesPage(
              negocioId: 'n1',
              repository: repository,
              empleadoId: 'e1',
              mostrarBarberos: false,
              hoy: _hoy,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esta semana'));
      await tester.pumpAndSettle();

      expect(repository.ultimoEmpleado, 'e1');
      expect(find.text('Mis reportes'), findsOneWidget);
      expect(_indicador('Ingresos'), r'RD$1,200');
      expect(_indicador('Citas'), '4');
      expect(find.text('Por barbero'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a retry message when loading fails', (tester) async {
      final repository = _FakeReportesRepository(const [], falla: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportesPage(
              negocioId: 'n1',
              repository: repository,
              hoy: _hoy,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pudo cargar el reporte.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}

void _pantalla(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

String _indicador(String titulo) =>
    (find.byKey(ValueKey('indicador-$titulo')).evaluate().single.widget as Text)
        .data ??
    '';

CitaReporte _cita(
  String id,
  DateTime fecha,
  num precio,
  EstadoCita estado, {
  (String, String) cliente = ('k0', 'Cliente'),
  (String, String) empleado = ('e1', 'Luis'),
  (String, String) servicio = ('s2', 'Corte'),
  num apartado = 0,
}) => CitaReporte(
  id: id,
  fecha: fecha,
  precio: precio,
  estado: estado,
  clienteId: cliente.$1,
  clienteNombre: cliente.$2,
  empleadoId: empleado.$1,
  empleadoNombre: empleado.$2,
  servicioId: servicio.$1,
  servicioNombre: servicio.$2,
  apartadoPagado: apartado,
);

List<CitaReporte> _citasDeEjemplo() {
  const juan = ('k1', 'Juan Pérez');
  const pedro = ('k2', 'Pedro Gómez');
  const luis = ('e1', 'Luis');
  const carlos = ('e2', 'Carlos');
  const corte = ('s2', 'Corte');
  const barba = ('s3', 'Barba');
  return [
    _cita(
      'c1',
      DateTime(2026, 10, 26),
      700,
      EstadoCita.llego,
      cliente: juan,
      empleado: luis,
      servicio: ('s1', 'Corte + Barba'),
      apartado: 100,
    ),
    _cita(
      'c2',
      DateTime(2026, 10, 26),
      500.50,
      EstadoCita.completada,
      cliente: pedro,
      empleado: carlos,
      servicio: corte,
      apartado: 100,
    ),
    _cita(
      'c3',
      DateTime(2026, 10, 27),
      500,
      EstadoCita.completada,
      cliente: juan,
      empleado: luis,
      servicio: corte,
    ),
    // El apartado de un no-show no se devuelve: cuenta como cobrado.
    _cita(
      'c4',
      DateTime(2026, 10, 27),
      250,
      EstadoCita.noVino,
      cliente: ('k3', 'José Díaz'),
      empleado: carlos,
      servicio: barba,
      apartado: 100,
    ),
    _cita(
      'c5',
      DateTime(2026, 10, 27),
      900,
      EstadoCita.cancelada,
      cliente: ('k4', 'Ana'),
      empleado: luis,
      servicio: ('s4', 'Tinte'),
    ),
    _cita(
      'c6',
      DateTime(2026, 10, 28),
      500,
      EstadoCita.pendiente,
      cliente: pedro,
      empleado: luis,
      servicio: corte,
      apartado: 100,
    ),
    _cita(
      'c7',
      DateTime(2026, 10, 5),
      300.25,
      EstadoCita.completada,
      cliente: juan,
      empleado: carlos,
      servicio: barba,
    ),
    _cita(
      'c8',
      DateTime(2026, 9, 30),
      999,
      EstadoCita.completada,
      cliente: juan,
      empleado: luis,
      servicio: corte,
    ),
  ];
}

class _FakeReportesRepository implements ReportesRepository {
  _FakeReportesRepository(this.citas, {this.falla = false});

  final List<CitaReporte> citas;
  final bool falla;
  Periodo? ultimoPeriodo;
  String? ultimoEmpleado;

  @override
  Future<List<CitaReporte>> listarCitas({
    required String negocioId,
    required Periodo periodo,
    String? empleadoId,
  }) async {
    if (falla) throw Exception('sin conexión');
    ultimoPeriodo = periodo;
    ultimoEmpleado = empleadoId;
    return [
      for (final cita in citas)
        if (periodo.contiene(cita.fecha) &&
            (empleadoId == null || cita.empleadoId == empleadoId))
          cita,
    ];
  }
}
