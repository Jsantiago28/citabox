import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cita.dart';
// Diferido: el paquete de Excel pesa y solo se usa al descargar.
import '../services/exportar_excel.dart' deferred as excel;
import '../services/reportes.dart';
import '../services/reportes_repository.dart';
import '../services/resumen_whatsapp.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../utils/navegador.dart';
import '../utils/whatsapp.dart';
import '../widgets/estado_cita_badge.dart';
import '../utils/vocabulario.dart';

class ReportesPage extends StatefulWidget {
  const ReportesPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.moneda = 'DOP',
    this.empleadoId,
    this.mostrarBarberos = true,
    this.hoy,
    this.negocioNombre = '',
    this.descargar = descargarBytes,
    this.abrirEnlace = _abrirEnlaceExterno,
  });

  final String negocioId;
  final ReportesRepository repository;
  final String moneda;

  /// Si se indica, el reporte se limita a las citas de ese empleado.
  final String? empleadoId;

  /// Desglose por barbero (solo para el dueño).
  final bool mostrarBarberos;

  /// Inyectable en pruebas; por defecto la fecha del dispositivo.
  final DateTime? hoy;

  /// Va en la hoja "Resumen" del Excel.
  final String negocioNombre;

  /// Inyectable en pruebas; en web descarga el archivo.
  final bool Function(String nombre, Uint8List bytes, String tipo) descargar;

  /// Inyectable en pruebas; por defecto abre WhatsApp.
  final Future<bool> Function(Uri enlace) abrirEnlace;

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  TipoPeriodo _tipo = TipoPeriodo.hoy;
  late Periodo _periodo;
  late Future<Reporte> _reporte;
  List<CitaReporte> _citas = const [];

  DateTime get _hoy => widget.hoy ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _periodo = Periodo.de(_tipo, _hoy);
    _reporte = _cargar();
  }

  Future<Reporte> _cargar() async {
    final periodo = _periodo;
    final citas = await widget.repository.listarCitas(
      negocioId: widget.negocioId,
      periodo: periodo,
      empleadoId: widget.empleadoId,
    );
    _citas = citas;
    return Reporte.calcular(citas, periodo);
  }

  Future<void> _descargarExcel() async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final reporte = await _reporte;
      await excel.loadLibrary();
      final bytes = excel.generarExcelReporte(
        reporte: reporte,
        citas: _citas,
        negocio: widget.negocioNombre,
        incluirBarberos: widget.mostrarBarberos,
      );
      final ok = widget.descargar(
        excel.nombreArchivoReporte(reporte.periodo),
        bytes,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      mensajero.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Reporte descargado en Excel.'
                : 'La descarga solo funciona en la versión web.',
          ),
        ),
      );
    } catch (_) {
      mensajero.showSnackBar(
        const SnackBar(content: Text('No se pudo generar el Excel.')),
      );
    }
  }

  Future<void> _compartirWhatsApp() async {
    final mensajero = ScaffoldMessenger.of(context);
    final profesionales = Vocabulario.of(context).profesionales;
    try {
      final reporte = await _reporte;
      final mensaje = mensajeResumenReporte(
        reporte,
        negocio: widget.negocioNombre,
        moneda: widget.moneda,
        incluirEquipo: widget.mostrarBarberos,
        profesionales: profesionales,
      );
      final abierto = await widget.abrirEnlace(
        Uri.parse(enlaceWhatsApp('', mensaje)),
      );
      if (!abierto) {
        mensajero.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
        );
      }
    } catch (_) {
      mensajero.showSnackBar(
        const SnackBar(content: Text('No se pudo preparar el resumen.')),
      );
    }
  }

  void _recargar() {
    setState(() {
      _reporte = _cargar();
    });
  }

  Future<void> _elegir(TipoPeriodo tipo) async {
    var periodo = Periodo.de(tipo, _hoy);
    if (tipo == TipoPeriodo.personalizado) {
      final rango = await showDateRangePicker(
        context: context,
        firstDate: DateTime(_hoy.year - 5),
        lastDate: DateTime(_hoy.year + 1, 12, 31),
        initialDateRange: DateTimeRange(
          start: _periodo.desde,
          end: _periodo.hasta,
        ),
        helpText: 'Elige el período',
        saveText: 'Aplicar',
        cancelText: 'Cancelar',
        confirmText: 'Aplicar',
        fieldStartLabelText: 'Desde',
        fieldEndLabelText: 'Hasta',
      );
      if (rango == null || !mounted) return;
      periodo = Periodo(rango.start, rango.end);
    }
    setState(() {
      _tipo = tipo;
      _periodo = periodo;
      _reporte = _cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth >= 860;
        return RefreshIndicator(
          onRefresh: () async {
            _recargar();
            await _reporte;
          },
          child: ListView(
            padding: EdgeInsets.all(ancho ? 28 : 16),
            children: [
              Text(
                widget.mostrarBarberos ? 'Reportes' : 'Mis reportes',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                formatoRangoFechas(_periodo.desde, _periodo.hasta),
                style: const TextStyle(color: Marca.textoSuave),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tipo in TipoPeriodo.values)
                    ChoiceChip(
                      label: Text(tipo.etiqueta),
                      avatar: tipo == TipoPeriodo.personalizado
                          ? const Icon(Icons.date_range, size: 18)
                          : null,
                      selected: tipo == _tipo,
                      showCheckmark: false,
                      selectedColor: Marca.doradoClaro,
                      onSelected: (_) => _elegir(tipo),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('descargar-excel'),
                    onPressed: _descargarExcel,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Descargar Excel'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('compartir-whatsapp'),
                    onPressed: _compartirWhatsApp,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Compartir por WhatsApp'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FutureBuilder<Reporte>(
                future: _reporte,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _Mensaje(
                      texto: 'No se pudo cargar el reporte.',
                      onReintentar: _recargar,
                    );
                  }
                  return _Contenido(
                    reporte: snapshot.data!,
                    moneda: widget.moneda,
                    ancho: ancho,
                    mostrarBarberos: widget.mostrarBarberos,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.reporte,
    required this.moneda,
    required this.ancho,
    required this.mostrarBarberos,
  });

  final Reporte reporte;
  final String moneda;
  final bool ancho;
  final bool mostrarBarberos;

  String _dinero(num monto) => formatoMoneda(monto, moneda);

  @override
  Widget build(BuildContext context) {
    final tasa = reporte.tasaNoShow;
    final ticket = reporte.ticketPromedio;

    final barberos = mostrarBarberos
        ? _Tabla(
            titulo: 'Por ${Vocabulario.of(context).profesionalMin}',
            columnas: [
              Vocabulario.of(context).profesional,
              'Atendidas',
              'Ingresos',
              'Comisión',
              'Total a pagar',
            ],
            vacio: 'Sin citas atendidas.',
            filas: [
              for (final fila in reporte.porBarbero)
                [
                  _o(fila.nombre, 'Sin asignar'),
                  '${fila.atendidas}',
                  _dinero(fila.ingresos),
                  fila.comisionPct == 0
                      ? '—'
                      : '${_dinero(fila.comision)} (${textoPorcentaje(fila.comisionPct)})',
                  _dinero(fila.totalAPagar),
                ],
            ],
            total: reporte.porBarbero.isEmpty
                ? null
                : [
                    'Total',
                    '${reporte.porBarbero.fold(0, (s, f) => s + f.atendidas)}',
                    _dinero(reporte.ingresos),
                    _dinero(reporte.totalComisiones),
                    _dinero(reporte.totalAPagar),
                  ],
          )
        : null;
    final servicios = _Tabla(
      titulo: 'Por servicio',
      columnas: const ['Servicio', 'Cantidad', 'Ingresos'],
      vacio: 'Sin servicios realizados.',
      filas: [
        for (final fila in reporte.porServicio)
          [
            _o(fila.nombre, 'Sin servicio'),
            '${fila.cantidad}',
            _dinero(fila.ingresos),
          ],
      ],
    );
    final clientes = _Tabla(
      titulo: 'Clientes frecuentes',
      columnas: const ['Cliente', 'Visitas', 'Gastado'],
      vacio: 'Sin visitas en este período.',
      numerar: true,
      filas: [
        for (final fila in reporte.topClientes)
          [
            _o(fila.nombre, 'Sin nombre'),
            '${fila.visitas}',
            _dinero(fila.gastado),
          ],
      ],
    );
    final metodos = _Tabla(
      titulo: 'Ingresos por método de pago',
      columnas: const ['Método', 'Citas', 'Ingresos'],
      vacio: 'Sin ingresos en este período.',
      filas: [
        for (final fila in reporte.porMetodoPago)
          [fila.etiqueta, '${fila.cantidad}', _dinero(fila.ingresos)],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Indicadores(
          tarjetas: [
            _Indicador(
              titulo: 'Ingresos',
              valor: _dinero(reporte.ingresos),
              color: Marca.verde,
            ),
            _Indicador(
              titulo: 'Ticket promedio',
              valor: ticket == null ? '—' : _dinero(ticket),
            ),
            _Indicador(
              titulo: 'Apartados cobrados',
              valor: _dinero(reporte.apartadosCobrados),
            ),
            _Indicador(
              titulo: 'Propinas',
              // Van aparte: no se suman a los ingresos.
              valor: _dinero(reporte.propinas),
            ),
            _Indicador(
              titulo: 'Tasa de no-show',
              valor: tasa == null ? '—' : '${(tasa * 100).toStringAsFixed(1)}%',
              color: Marca.rojo,
            ),
            _Indicador(titulo: 'Citas', valor: '${reporte.totalCitas}'),
            _Indicador(titulo: 'Atendidas', valor: '${reporte.atendidas}'),
            _Indicador(
              titulo: 'No vinieron',
              valor: '${reporte.noShows}',
              color: Marca.rojo,
            ),
            _Indicador(
              titulo: 'Cancelaciones',
              valor: '${reporte.cancelaciones}',
              color: Marca.textoSuave,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _Seccion(
          titulo: 'Ingresos por día',
          child: _GraficoIngresos(dias: reporte.ingresosPorDia, moneda: moneda),
        ),
        const SizedBox(height: 24),
        metodos,
        const SizedBox(height: 24),
        _Seccion(
          titulo: 'Citas por estado',
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final estado in EstadoCita.values)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EstadoCitaBadge(estado: estado),
                      const SizedBox(width: 6),
                      Text(
                        '${reporte.porEstado[estado]}',
                        key: ValueKey('estado-${estado.valor}'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (ancho && barberos != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: barberos),
              const SizedBox(width: 16),
              Expanded(child: servicios),
            ],
          )
        else ...[
          ?barberos,
          if (barberos != null) const SizedBox(height: 24),
          servicios,
        ],
        const SizedBox(height: 24),
        clientes,
      ],
    );
  }
}

String _o(String texto, String alternativa) =>
    texto.trim().isEmpty ? alternativa : texto;

class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.tarjetas});

  final List<Widget> tarjetas;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth >= 640 ? 4 : 2;
        const espacio = 12.0;
        final anchoTarjeta =
            (constraints.maxWidth - espacio * (columnas - 1)) / columnas;
        return Wrap(
          spacing: espacio,
          runSpacing: espacio,
          children: [
            for (final tarjeta in tarjetas)
              SizedBox(width: anchoTarjeta, child: tarjeta),
          ],
        );
      },
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({
    required this.titulo,
    required this.valor,
    this.color = Marca.texto,
  });

  final String titulo;
  final String valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(color: Marca.textoSuave, fontSize: 13),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                valor,
                key: ValueKey('indicador-$titulo'),
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titulo,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(clipBehavior: Clip.antiAlias, child: child),
      ],
    );
  }
}

class _Tabla extends StatelessWidget {
  const _Tabla({
    required this.titulo,
    required this.columnas,
    required this.filas,
    required this.vacio,
    this.numerar = false,
    this.total,
  });

  /// Fila final opcional (mismo número de celdas que [columnas]).
  final List<String>? total;

  final String titulo;

  /// Tres columnas: nombre, cantidad y monto.
  final List<String> columnas;
  final List<List<String>> filas;
  final String vacio;
  final bool numerar;

  @override
  Widget build(BuildContext context) {
    const encabezado = TextStyle(
      color: Marca.textoSuave,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    Widget fila(List<String> celdas, {TextStyle? estilo, String? prefijo}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (numerar)
              SizedBox(
                width: 28,
                child: Text(prefijo ?? '', style: encabezado),
              ),
            Expanded(
              flex: 3,
              child: Text(
                celdas[0],
                style: estilo ?? const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(celdas[1], style: estilo, textAlign: TextAlign.end),
            ),
            Expanded(
              flex: 2,
              child: Text(celdas[2], style: estilo, textAlign: TextAlign.end),
            ),
            for (final extra in celdas.skip(3))
              Expanded(
                flex: 2,
                child: Text(extra, style: estilo, textAlign: TextAlign.end),
              ),
          ],
        ),
      );
    }

    return _Seccion(
      titulo: titulo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fila(columnas, estilo: encabezado),
          const Divider(),
          if (filas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(vacio)),
            )
          else
            for (var i = 0; i < filas.length; i++) ...[
              if (i > 0) const Divider(),
              fila(filas[i], prefijo: '${i + 1}'),
            ],
          if (total != null && filas.isNotEmpty) ...[
            const Divider(),
            fila(total!, estilo: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

/// Barras dibujadas con widgets: una por día del período.
class _GraficoIngresos extends StatelessWidget {
  const _GraficoIngresos({required this.dias, required this.moneda});

  final List<IngresoDia> dias;
  final String moneda;

  static const _alto = 160.0;
  static const _anchoMinimo = 14.0;

  @override
  Widget build(BuildContext context) {
    final maximo = dias.fold<num>(0, (m, d) => d.ingresos > m ? d.ingresos : m);
    if (maximo == 0) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Sin ingresos en este período.')),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Máximo: ${formatoMoneda(maximo, moneda)}',
            style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final cabe = dias.length * _anchoMinimo <= constraints.maxWidth;
              final anchoBarra = cabe
                  ? constraints.maxWidth / dias.length
                  : _anchoMinimo;
              // Etiquetas espaciadas para que no se encimen (~40 px cada una).
              final cada = (40 / anchoBarra).ceil().clamp(1, dias.length);

              final barras = Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < dias.length; i++)
                    SizedBox(
                      width: anchoBarra,
                      child: _Barra(
                        dia: dias[i],
                        fraccion: dias[i].ingresos / maximo,
                        alto: _alto,
                        etiqueta: i % cada == 0
                            ? formatoDiaMes(dias[i].dia)
                            : '',
                        moneda: moneda,
                      ),
                    ),
                ],
              );

              return cabe
                  ? barras
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: barras,
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({
    required this.dia,
    required this.fraccion,
    required this.alto,
    required this.etiqueta,
    required this.moneda,
  });

  final IngresoDia dia;
  final double fraccion;
  final double alto;
  final String etiqueta;
  final String moneda;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          '${formatoFechaLarga(dia.dia)}: '
          '${formatoMoneda(dia.ingresos, moneda)}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: alto,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                widthFactor: 0.7,
                heightFactor: fraccion == 0 ? null : fraccion,
                child: Container(
                  height: fraccion == 0 ? 2 : null,
                  decoration: BoxDecoration(
                    gradient: fraccion == 0 ? null : Marca.degradadoDorado,
                    color: fraccion == 0 ? Marca.borde : null,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            child: Text(
              etiqueta,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: const TextStyle(color: Marca.textoSuave, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, required this.onReintentar});

  final String texto;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text(texto, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

Future<bool> _abrirEnlaceExterno(Uri enlace) =>
    launchUrl(enlace, mode: LaunchMode.externalApplication);
