import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cita.dart';
import '../services/apartados_repository.dart';
import '../services/citas_repository.dart';
import '../services/primer_uso_repository.dart';
import '../theme.dart';
import '../utils/enlace_publico.dart';
import '../utils/formato.dart';
import '../widgets/estado_cita_badge.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.negocioId,
    required this.negocioNombre,
    required this.nombre,
    required this.repository,
    required this.onVerAgenda,
    this.moneda = 'DOP',
    this.empleadoId,
    this.hoy,
    this.apartadosRepository,
    this.onVerApartados,
    this.mostrarPorBarbero = true,
    this.primerUsoRepository,
    this.onIr,
    this.baseEnlace,
  });

  final String negocioId;
  final String negocioNombre;
  final String nombre;
  final String moneda;
  final CitasRepository repository;
  final VoidCallback onVerAgenda;

  /// Si se indica, el resumen se limita a las citas de ese empleado.
  final String? empleadoId;

  /// Inyectable en pruebas; por defecto la fecha del dispositivo.
  final DateTime? hoy;

  /// Si se indican, el panel avisa cuántos apartados faltan por validar.
  final ApartadosRepository? apartadosRepository;
  final VoidCallback? onVerApartados;

  /// Muestra la tarjeta "Hoy por barbero" (solo para el dueño).
  final bool mostrarPorBarbero;

  /// Si se indica (solo dueño), muestra la tarjeta "Configura tu negocio".
  final PrimerUsoRepository? primerUsoRepository;

  /// Lleva a una sección: 'horario', 'servicios', 'barberos' o 'logo'.
  final void Function(String seccion)? onIr;

  /// Base del enlace público; por defecto `Uri.base` en web.
  final Uri? baseEnlace;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<Cita>> _citas;
  late Future<int> _porValidar;
  Future<PrimerUso?>? _primerUso;
  bool _enlaceCompartido = false;

  Future<PrimerUso?> _cargarPrimerUso() async {
    final repository = widget.primerUsoRepository;
    if (repository == null) return null;
    try {
      return await repository.cargar(widget.negocioId);
    } catch (_) {
      return null; // la tarjeta es complementaria
    }
  }

  Future<void> _copiarEnlace(String slug) async {
    final base = widget.baseEnlace ?? (kIsWeb ? Uri.base : null);
    await Clipboard.setData(
      ClipboardData(text: enlaceReserva(slug, base: base)),
    );
    if (!mounted) return;
    setState(() => _enlaceCompartido = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Enlace copiado')));
  }

  DateTime get _hoy => widget.hoy ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _citas = _cargar();
    _porValidar = _contarApartados();
    _primerUso = _cargarPrimerUso();
  }

  // El aviso es complementario: si falla, el panel sigue igual.
  Future<int> _contarApartados() async {
    final repository = widget.apartadosRepository;
    if (repository == null) return 0;
    try {
      return await repository.contarPorValidar(
        negocioId: widget.negocioId,
        empleadoId: widget.empleadoId,
      );
    } catch (_) {
      return 0;
    }
  }

  Future<List<Cita>> _cargar() => widget.repository.listarDelDia(
    negocioId: widget.negocioId,
    fecha: _hoy,
    empleadoId: widget.empleadoId,
  );

  @override
  Widget build(BuildContext context) {
    final primerNombre = widget.nombre.trim().split(' ').first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth >= 860;
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _citas = _cargar();
              _porValidar = _contarApartados();
              _primerUso = _cargarPrimerUso();
            });
            await _citas;
          },
          child: ListView(
            padding: EdgeInsets.all(ancho ? 28 : 16),
            children: [
              _Encabezado(
                saludo: 'Hola, $primerNombre 👋',
                fecha: formatoFechaLarga(_hoy),
                negocioNombre: widget.negocioNombre,
                mostrarNegocio: ancho,
              ),
              const SizedBox(height: 20),
              if (widget.primerUsoRepository != null)
                FutureBuilder<PrimerUso?>(
                  future: _primerUso,
                  builder: (context, snapshot) {
                    final estado = snapshot.data;
                    if (estado == null) return const SizedBox.shrink();
                    final pasos = [
                      _Paso('horario', 'Define tu horario', estado.horario),
                      _Paso(
                        'servicios',
                        'Agrega al menos un servicio',
                        estado.servicio,
                      ),
                      _Paso(
                        'barberos',
                        'Agrega al menos un barbero',
                        estado.barbero,
                      ),
                      _Paso('logo', 'Sube tu logo', estado.logo),
                    ];
                    if (pasos.every((p) => p.hecho) && _enlaceCompartido) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ConfiguraNegocio(
                        pasos: pasos,
                        enlaceCompartido: _enlaceCompartido,
                        onIr: widget.onIr,
                        onCopiar: () => _copiarEnlace(estado.slug),
                      ),
                    );
                  },
                ),
              FutureBuilder<int>(
                future: _porValidar,
                builder: (context, snapshot) {
                  final cantidad = snapshot.data ?? 0;
                  final onVer = widget.onVerApartados;
                  if (cantidad == 0 || onVer == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _AvisoApartados(cantidad: cantidad, onVer: onVer),
                  );
                },
              ),
              FutureBuilder<List<Cita>>(
                future: _citas,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _Mensaje(
                      texto: 'No se pudo cargar la agenda de hoy.',
                      onReintentar: () => setState(() => _citas = _cargar()),
                    );
                  }

                  final citas = snapshot.data!
                      .where((cita) => cita.estado != EstadoCita.cancelada)
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Indicadores(citas: citas, moneda: widget.moneda),
                      if (widget.mostrarPorBarbero) ...[
                        const SizedBox(height: 24),
                        _HoyPorBarbero(
                          resumen: resumenPorBarbero(citas),
                          moneda: widget.moneda,
                        ),
                      ],
                      const SizedBox(height: 24),
                      _AgendaDeHoy(
                        citas: citas,
                        ancho: ancho,
                        onVerTodas: widget.onVerAgenda,
                      ),
                    ],
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

class _Paso {
  const _Paso(this.seccion, this.titulo, this.hecho);

  final String seccion;
  final String titulo;
  final bool hecho;
}

/// Checklist de primer uso para el dueño.
class _ConfiguraNegocio extends StatelessWidget {
  const _ConfiguraNegocio({
    required this.pasos,
    required this.enlaceCompartido,
    required this.onIr,
    required this.onCopiar,
  });

  final List<_Paso> pasos;
  final bool enlaceCompartido;
  final void Function(String seccion)? onIr;
  final VoidCallback onCopiar;

  Widget _fila(
    BuildContext context,
    String clave,
    String titulo,
    bool hecho, {
    required String accion,
    required VoidCallback? onTap,
  }) {
    return Padding(
      key: Key('paso-$clave'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            hecho ? Icons.check_circle : Icons.radio_button_unchecked,
            color: hecho ? Colors.green : Theme.of(context).disabledColor,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                decoration: hecho ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (!hecho && onTap != null)
            TextButton(onPressed: onTap, child: Text(accion)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('configura-tu-negocio'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Configura tu negocio',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final paso in pasos)
              _fila(
                context,
                paso.seccion,
                paso.titulo,
                paso.hecho,
                accion: 'Ir',
                onTap: onIr == null ? null : () => onIr!(paso.seccion),
              ),
            _fila(
              context,
              'enlace',
              'Comparte tu enlace de reservas',
              enlaceCompartido,
              accion: 'Copiar enlace',
              onTap: onCopiar,
            ),
          ],
        ),
      ),
    );
  }
}

/// Una fila del cierre de caja por barbero.
class FilaBarbero {
  const FilaBarbero({
    required this.nombre,
    required this.atendidas,
    required this.cobrado,
    required this.propinas,
  });

  final String nombre;
  final int atendidas;
  final num cobrado;
  final num propinas;
}

/// Agrupa las citas atendidas por barbero, ordenado por cobrado (desc).
List<FilaBarbero> resumenPorBarbero(Iterable<Cita> citas) {
  final grupos = <String, List<Cita>>{};
  for (final cita in citas.where((c) => c.estado.atendida)) {
    final nombre = cita.empleadoNombre.trim();
    final clave = nombre.isNotEmpty
        ? nombre
        : (cita.empleadoId.isNotEmpty ? cita.empleadoId : 'Sin asignar');
    grupos.putIfAbsent(clave, () => []).add(cita);
  }
  final filas = [
    for (final e in grupos.entries)
      FilaBarbero(
        nombre: e.key,
        atendidas: e.value.length,
        cobrado: e.value.fold<num>(0, (t, c) => t + c.precio),
        propinas: e.value.fold<num>(0, (t, c) => t + c.propina),
      ),
  ];
  filas.sort((a, b) => b.cobrado.compareTo(a.cobrado));
  return filas;
}

class _HoyPorBarbero extends StatelessWidget {
  const _HoyPorBarbero({required this.resumen, required this.moneda});

  final List<FilaBarbero> resumen;
  final String moneda;

  Widget _fila(String a, String b, String c, String d, {bool fuerte = false}) {
    final estilo = TextStyle(
      fontWeight: fuerte ? FontWeight.w700 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(a, style: estilo)),
          Expanded(
            child: Text(b, style: estilo, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text(c, style: estilo, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text(d, style: estilo, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('hoy-por-barbero'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hoy por barbero',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: resumen.isEmpty
                ? const Text('Aún no hay cobros hoy')
                : Column(
                    children: [
                      _fila(
                        'Barbero',
                        'Citas',
                        'Cobrado',
                        'Propinas',
                        fuerte: true,
                      ),
                      const Divider(),
                      for (final f in resumen)
                        _fila(
                          f.nombre,
                          '${f.atendidas}',
                          formatoMoneda(f.cobrado, moneda),
                          formatoMoneda(f.propinas, moneda),
                        ),
                      const Divider(),
                      _fila(
                        'Total',
                        '${resumen.fold<int>(0, (t, f) => t + f.atendidas)}',
                        formatoMoneda(
                          resumen.fold<num>(0, (t, f) => t + f.cobrado),
                          moneda,
                        ),
                        formatoMoneda(
                          resumen.fold<num>(0, (t, f) => t + f.propinas),
                          moneda,
                        ),
                        fuerte: true,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.saludo,
    required this.fecha,
    required this.negocioNombre,
    required this.mostrarNegocio,
  });

  final String saludo;
  final String fecha;
  final String negocioNombre;
  final bool mostrarNegocio;

  @override
  Widget build(BuildContext context) {
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          saludo,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(fecha, style: const TextStyle(color: Marca.textoSuave)),
      ],
    );

    if (!mostrarNegocio) return textos;

    return Row(
      children: [
        Expanded(child: textos),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Marca.borde),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarIniciales(texto: iniciales(negocioNombre), radio: 15),
              const SizedBox(width: 8),
              Text(
                negocioNombre,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvisoApartados extends StatelessWidget {
  const _AvisoApartados({required this.cantidad, required this.onVer});

  final int cantidad;
  final VoidCallback onVer;

  @override
  Widget build(BuildContext context) {
    final texto = cantidad == 1
        ? '1 apartado por validar'
        : '$cantidad apartados por validar';
    return Card(
      key: const Key('aviso-apartados'),
      color: Marca.naranja.withValues(alpha: 0.08),
      child: ListTile(
        onTap: onVer,
        leading: const Icon(Icons.payments_outlined, color: Marca.naranja),
        title: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Revisa las transferencias reportadas.'),
        trailing: TextButton(onPressed: onVer, child: const Text('Revisar')),
      ),
    );
  }
}

class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.citas, required this.moneda});

  final List<Cita> citas;
  final String moneda;

  @override
  Widget build(BuildContext context) {
    final atendidas = citas.where((cita) => cita.estado.atendida);
    final ventas = atendidas.fold<num>(0, (total, cita) => total + cita.precio);
    final noShow = citas.where((cita) => cita.estado == EstadoCita.noVino);

    final tarjetas = [
      _Indicador(titulo: 'Citas hoy', valor: '${citas.length}'),
      _Indicador(titulo: 'Llegaron', valor: '${atendidas.length}'),
      _Indicador(
        titulo: 'No-show',
        valor: '${noShow.length}',
        color: Marca.rojo,
      ),
      _Indicador(
        titulo: 'Ventas hoy',
        valor: formatoMoneda(ventas, moneda),
        color: Marca.verde,
      ),
    ];

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

class _AgendaDeHoy extends StatelessWidget {
  const _AgendaDeHoy({
    required this.citas,
    required this.ancho,
    required this.onVerTodas,
  });

  final List<Cita> citas;
  final bool ancho;
  final VoidCallback onVerTodas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Agenda de hoy',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onVerTodas, child: const Text('Ver todas')),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: citas.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No hay citas para hoy.')),
                )
              : Column(
                  children: [
                    for (var i = 0; i < citas.length; i++) ...[
                      if (i > 0) const Divider(),
                      ancho ? _filaAncha(citas[i]) : _filaCompacta(citas[i]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _filaAncha(Cita cita) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(formatoHora(cita.horaInicio))),
          Expanded(
            flex: 3,
            child: Text(
              cita.clienteNombre,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(flex: 3, child: Text(cita.servicioNombre)),
          Expanded(flex: 2, child: Text(cita.empleadoNombre)),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: EstadoCitaBadge(estado: cita.estado),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaCompacta(Cita cita) {
    return ListTile(
      leading: SizedBox(
        width: 64,
        child: Text(
          formatoHora(cita.horaInicio),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      title: Text(
        cita.clienteNombre,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          cita.servicioNombre,
          cita.empleadoNombre,
        ].where((texto) => texto.isNotEmpty).join(' · '),
      ),
      trailing: EstadoCitaBadge(estado: cita.estado),
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
