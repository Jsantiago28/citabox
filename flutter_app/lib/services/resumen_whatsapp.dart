// Resumen del reporte en texto para compartir por WhatsApp (wa.me), con
// las mismas cifras de la pantalla. Los *asteriscos* son negritas en
// WhatsApp.

import '../utils/formato.dart';
import 'reportes.dart';

String mensajeResumenReporte(
  Reporte reporte, {
  required String negocio,
  String moneda = 'DOP',
  bool incluirEquipo = true,
  String profesionales = 'Barberos',
}) {
  String dinero(num monto) => formatoMoneda(monto, moneda);
  final p = reporte.periodo;
  final lineas = <String>[
    if (negocio.trim().isNotEmpty)
      '*${negocio.trim()}* · Resumen'
    else
      '*Resumen*',
    formatoRangoFechas(p.desde, p.hasta),
    '',
    '*Ingresos: ${dinero(reporte.ingresos)}*',
    'Citas atendidas: ${reporte.atendidas} de ${reporte.totalCitas}',
    if (reporte.noShows > 0 || reporte.cancelaciones > 0)
      'No vinieron: ${reporte.noShows} · Canceladas: ${reporte.cancelaciones}',
    if (reporte.ticketPromedio case final ticket?)
      'Ticket promedio: ${dinero(ticket)}',
    if (reporte.propinas > 0) 'Propinas: ${dinero(reporte.propinas)}',
    if (reporte.apartadosCobrados > 0)
      'Apartados cobrados: ${dinero(reporte.apartadosCobrados)}',
  ];

  final metodos = reporte.porMetodoPago.where((f) => f.ingresos > 0);
  if (metodos.isNotEmpty) {
    lineas
      ..add('')
      ..add('*Por método de pago*');
    for (final fila in metodos) {
      lineas.add('• ${fila.etiqueta}: ${dinero(fila.ingresos)}');
    }
  }

  final equipo = reporte.porBarbero.where((f) => f.atendidas > 0);
  if (incluirEquipo && equipo.isNotEmpty) {
    lineas
      ..add('')
      ..add('*Por ${profesionales.toLowerCase()}*');
    for (final fila in equipo) {
      final citas =
          '${fila.atendidas} ${fila.atendidas == 1 ? 'cita' : 'citas'}';
      final aPagar = fila.comision + fila.propinas;
      lineas.add(
        '• ${fila.nombre}: $citas · ${dinero(fila.ingresos)}'
        '${aPagar > 0 ? ' · a pagar ${dinero(aPagar)}' : ''}',
      );
    }
  }

  if (reporte.porServicio.isNotEmpty) {
    final top = reporte.porServicio.first;
    lineas
      ..add('')
      ..add('Servicio más pedido: ${top.nombre} (${top.cantidad})');
  }

  lineas
    ..add('')
    ..add('Enviado desde Citabox');
  return lineas.join('\n');
}
