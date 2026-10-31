import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/pages/reportes_page.dart';
import 'package:barberiapro/services/reportes.dart';
import 'package:barberiapro/services/reportes_repository.dart';
import 'package:barberiapro/services/resumen_whatsapp.dart';

final _hoy = DateTime(2026, 10, 27);

CitaReporte _cita(
  String id,
  num precio,
  EstadoCita estado, {
  String empleado = 'Luis',
  String servicio = 'Corte',
  MetodoPago? metodo,
  num propina = 0,
  num comisionPct = 0,
}) => CitaReporte(
  id: id,
  fecha: _hoy,
  precio: precio,
  estado: estado,
  empleadoId: empleado,
  empleadoNombre: empleado,
  servicioId: servicio,
  servicioNombre: servicio,
  metodoPago: metodo,
  propina: propina,
  comisionPct: comisionPct,
);

final _citas = [
  _cita(
    'c1',
    500,
    EstadoCita.completada,
    metodo: MetodoPago.efectivo,
    propina: 100,
    comisionPct: 40,
  ),
  _cita(
    'c2',
    800,
    EstadoCita.completada,
    empleado: 'Ana',
    servicio: 'Tinte',
    metodo: MetodoPago.transferencia,
  ),
  _cita(
    'c3',
    500,
    EstadoCita.completada,
    metodo: MetodoPago.efectivo,
    comisionPct: 40,
  ),
  _cita('c4', 500, EstadoCita.noVino),
];

void main() {
  test('el resumen trae las cifras del reporte', () {
    final reporte = Reporte.calcular(_citas, Periodo(_hoy, _hoy));
    final texto = mensajeResumenReporte(
      reporte,
      negocio: 'STIKING',
      profesionales: 'Estilistas',
    );

    expect(texto, startsWith('*STIKING* · Resumen\n27 de octubre de 2026'));
    expect(texto, contains(r'*Ingresos: RD$1,800*'));
    expect(texto, contains('Citas atendidas: 3 de 4'));
    expect(texto, contains('No vinieron: 1 · Canceladas: 0'));
    expect(texto, contains(r'Propinas: RD$100'));
    expect(texto, contains(r'• Efectivo: RD$1,000'));
    expect(texto, contains(r'• Transferencia: RD$800'));
    expect(texto, contains('*Por estilistas*'));
    // Luis: 2 citas, RD$1,000, 40 % = RD$400 + RD$100 de propina.
    expect(texto, contains(r'• Luis: 2 citas · RD$1,000 · a pagar RD$500'));
    expect(texto, contains(r'• Ana: 1 cita · RD$800'));
    expect(texto, contains('Servicio más pedido: Corte (2)'));
    expect(texto, endsWith('Enviado desde Citabox'));
  });

  test('sin equipo (barbero viendo su reporte) no muestra el desglose', () {
    final reporte = Reporte.calcular(_citas, Periodo(_hoy, _hoy));
    final texto = mensajeResumenReporte(
      reporte,
      negocio: '',
      incluirEquipo: false,
    );
    expect(texto, startsWith('*Resumen*'));
    expect(texto, isNot(contains('Por barberos')));
  });

  testWidgets('el botón abre WhatsApp con el resumen', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Uri? abierto;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportesPage(
            negocioId: 'n1',
            repository: _Repo(),
            hoy: _hoy,
            negocioNombre: 'STIKING',
            abrirEnlace: (enlace) async {
              abierto = enlace;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('compartir-whatsapp')));
    await tester.pumpAndSettle();

    expect(abierto?.host, 'wa.me');
    final texto = abierto!.queryParameters['text']!;
    expect(texto, contains('*STIKING* · Resumen'));
    expect(texto, contains('*Por barberos*'));
  });
}

class _Repo implements ReportesRepository {
  @override
  Future<List<CitaReporte>> listarCitas({
    required String negocioId,
    required Periodo periodo,
    String? empleadoId,
  }) async => _citas;
}
