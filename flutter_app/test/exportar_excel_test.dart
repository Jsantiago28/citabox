import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/pages/reportes_page.dart';
import 'package:barberiapro/services/exportar_excel.dart';
import 'package:barberiapro/services/reportes.dart';
import 'package:barberiapro/services/reportes_repository.dart';

final _dia = DateTime(2026, 10, 28);

final _citas = [
  CitaReporte(
    id: 'c1',
    fecha: _dia,
    horaInicio: '09:00:00',
    precio: 500,
    estado: EstadoCita.completada,
    clienteNombre: 'Ana',
    empleadoId: 'b1',
    empleadoNombre: 'Luis',
    servicioId: 's1',
    servicioNombre: 'Corte',
    metodoPago: MetodoPago.efectivo,
    propina: 100,
  ),
  CitaReporte(
    id: 'c2',
    fecha: _dia,
    horaInicio: '10:00:00',
    precio: 700,
    estado: EstadoCita.completada,
    clienteNombre: 'Pedro',
    empleadoId: 'b2',
    empleadoNombre: 'Miguel',
    servicioId: 's2',
    servicioNombre: 'Blower',
    metodoPago: MetodoPago.tarjeta,
  ),
  CitaReporte(
    id: 'c3',
    fecha: _dia,
    horaInicio: '11:00:00',
    precio: 400,
    estado: EstadoCita.noVino,
    clienteNombre: 'Rosa',
    empleadoId: 'b1',
    empleadoNombre: 'Luis',
    servicioId: 's1',
    servicioNombre: 'Corte',
  ),
];

/// Valor de la fila cuya primera columna es [concepto].
Object? _valor(Sheet hoja, String concepto, [int columna = 1]) {
  final fila = hoja.rows.firstWhere(
    (fila) => fila.first?.value.toString() == concepto,
  );
  final valor = fila[columna]?.value;
  return switch (valor) {
    DoubleCellValue(:final value) => value,
    IntCellValue(:final value) => value,
    _ => valor.toString(),
  };
}

void main() {
  test('el Excel trae las hojas y los totales del reporte', () {
    final reporte = Reporte.calcular(_citas, Periodo(_dia, _dia));
    final bytes = generarExcelReporte(
      reporte: reporte,
      citas: _citas,
      negocio: 'STIKING',
    );
    final libro = Excel.decodeBytes(bytes);

    expect(
      libro.tables.keys,
      containsAll([
        'Resumen',
        'Por barbero',
        'Por servicio',
        'Por método de pago',
        'Detalle de citas',
      ]),
    );
    expect(libro.tables.keys, isNot(contains('Sheet1')));

    final resumen = libro.tables['Resumen']!;
    expect(_valor(resumen, 'Negocio'), 'STIKING');
    expect(_valor(resumen, 'Ingresos'), 1200);
    expect(_valor(resumen, 'Propinas'), 100);
    expect(_valor(resumen, 'Citas'), 3);

    final barberos = libro.tables['Por barbero']!;
    expect(_valor(barberos, 'Luis', 2), 500);
    expect(_valor(barberos, 'Luis', 3), 100);
    expect(_valor(barberos, 'Miguel', 2), 700);
    expect(_valor(barberos, 'Total', 2), 1200);

    final detalle = libro.tables['Detalle de citas']!;
    expect(detalle.maxRows, 4); // encabezado + 3 citas
    expect(detalle.rows[1][1]?.value.toString(), contains('9:00'));
  });

  test('el barbero descarga su Excel sin la hoja por barbero', () {
    final reporte = Reporte.calcular(_citas, Periodo(_dia, _dia));
    final libro = Excel.decodeBytes(
      generarExcelReporte(
        reporte: reporte,
        citas: _citas,
        negocio: 'STIKING',
        incluirBarberos: false,
      ),
    );
    expect(libro.tables.keys, isNot(contains('Por barbero')));
  });

  testWidgets('el botón descarga el reporte del período', (tester) async {
    String? nombre;
    Uint8List? archivo;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportesPage(
            negocioId: 'n1',
            repository: _Repo(),
            hoy: _dia,
            negocioNombre: 'STIKING',
            descargar: (n, bytes, _) {
              nombre = n;
              archivo = bytes;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('descargar-excel')));
    await tester.pumpAndSettle();

    expect(nombre, 'reporte-2026-10-28-a-2026-10-28.xlsx');
    expect(Excel.decodeBytes(archivo!).tables['Resumen'], isNotNull);
    expect(find.text('Reporte descargado en Excel.'), findsOneWidget);
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
