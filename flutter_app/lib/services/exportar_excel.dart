import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/cita.dart';
import '../utils/formato.dart';
import 'reportes.dart';

/// Reporte del período en un .xlsx con varias hojas. Usa el mismo [Reporte]
/// que la pantalla, así que los totales coinciden con lo que se ve en la app.
Uint8List generarExcelReporte({
  required Reporte reporte,
  required Iterable<CitaReporte> citas,
  required String negocio,
  bool incluirBarberos = true,
}) {
  final libro = Excel.createExcel();
  final inicial = libro.getDefaultSheet()!;

  final periodo = reporte.periodo;
  final delPeriodo = citas.where((c) => periodo.contiene(c.fecha)).toList()
    ..sort((a, b) {
      final dia = a.fecha.compareTo(b.fecha);
      return dia != 0 ? dia : a.horaInicio.compareTo(b.horaInicio);
    });
  final atendidas = delPeriodo.where((c) => c.estado.atendida);

  _hoja(
    libro,
    'Resumen',
    const ['Concepto', 'Valor'],
    [
      [_texto('Negocio'), _texto(negocio)],
      [
        _texto('Período'),
        _texto(
          '${formatoFechaIso(periodo.desde)} a ${formatoFechaIso(periodo.hasta)}',
        ),
      ],
      [_texto('Ingresos'), _monto(reporte.ingresos)],
      [_texto('Propinas'), _monto(reporte.propinas)],
      [_texto('Apartados cobrados'), _monto(reporte.apartadosCobrados)],
      [_texto('Citas'), IntCellValue(reporte.totalCitas)],
      [_texto('Atendidas'), IntCellValue(atendidas.length)],
      for (final estado in EstadoCita.values)
        [
          _texto('  ${estado.etiqueta}'),
          IntCellValue(reporte.porEstado[estado] ?? 0),
        ],
      [
        _texto('Ticket promedio'),
        atendidas.isEmpty
            ? _texto('—')
            : _monto(reporte.ingresos / atendidas.length),
      ],
    ],
  );

  if (incluirBarberos) {
    _hoja(
      libro,
      'Por barbero',
      const [
        'Barbero',
        'Atendidas',
        'Ingresos',
        'Propinas',
        'Comisión %',
        'Comisión',
        'Total a pagar',
      ],
      [
        for (final fila in reporte.porBarbero)
          [
            _texto(fila.nombre),
            IntCellValue(fila.atendidas),
            _monto(fila.ingresos),
            _monto(fila.propinas),
            _monto(fila.comisionPct),
            _monto(fila.comision),
            _monto(fila.totalAPagar),
          ],
        [
          _texto('Total'),
          IntCellValue(reporte.porBarbero.fold(0, (s, f) => s + f.atendidas)),
          _monto(reporte.ingresos),
          _monto(reporte.propinas),
          _texto(''),
          _monto(reporte.totalComisiones),
          _monto(reporte.totalAPagar),
        ],
      ],
    );
  }

  _hoja(
    libro,
    'Por servicio',
    const ['Servicio', 'Cantidad', 'Ingresos'],
    [
      for (final fila in reporte.porServicio)
        [
          _texto(fila.nombre),
          IntCellValue(fila.cantidad),
          _monto(fila.ingresos),
        ],
    ],
  );

  _hoja(
    libro,
    'Por método de pago',
    const ['Método', 'Citas', 'Ingresos'],
    [
      for (final fila in reporte.porMetodoPago)
        [
          _texto(fila.etiqueta),
          IntCellValue(fila.cantidad),
          _monto(fila.ingresos),
        ],
    ],
  );

  _hoja(
    libro,
    'Detalle de citas',
    const [
      'Fecha',
      'Hora',
      'Cliente',
      'Servicio',
      'Barbero',
      'Estado',
      'Precio',
      'Método de pago',
      'Propina',
    ],
    [
      for (final cita in delPeriodo)
        [
          _texto(formatoFechaIso(cita.fecha)),
          _texto(cita.horaInicio.isEmpty ? '' : formatoHora(cita.horaInicio)),
          _texto(cita.clienteNombre),
          _texto(cita.servicioNombre),
          _texto(cita.empleadoNombre),
          _texto(cita.estado.etiqueta),
          _monto(cita.precio),
          _texto(cita.metodoPago?.etiqueta ?? ''),
          _monto(cita.propina),
        ],
    ],
  );

  libro.setDefaultSheet('Resumen');
  libro.delete(inicial);
  return Uint8List.fromList(libro.encode()!);
}

/// 'reporte-2026-10-01-a-2026-10-31.xlsx'
String nombreArchivoReporte(Periodo periodo) =>
    'reporte-${formatoFechaIso(periodo.desde)}-a-${formatoFechaIso(periodo.hasta)}.xlsx';

TextCellValue _texto(String valor) => TextCellValue(valor);

DoubleCellValue _monto(num valor) => DoubleCellValue(valor.toDouble());

void _hoja(
  Excel libro,
  String nombre,
  List<String> encabezados,
  List<List<CellValue?>> filas,
) {
  final hoja = libro[nombre];
  hoja.appendRow([for (final titulo in encabezados) TextCellValue(titulo)]);
  for (var columna = 0; columna < encabezados.length; columna++) {
    hoja
        .cell(CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: 0))
        .cellStyle = CellStyle(
      bold: true,
    );
    hoja.setColumnWidth(columna, columna == 0 ? 28 : 16);
  }
  for (final fila in filas) {
    hoja.appendRow(fila);
  }
}
