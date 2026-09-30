import 'package:flutter/material.dart';

import '../models/cita.dart';
import '../services/citas_repository.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../widgets/estado_cita_badge.dart';

class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.titulo = 'Agenda',
    this.moneda = 'DOP',
    this.empleadoId,
    this.fechaInicial,
  });

  final String negocioId;
  final CitasRepository repository;
  final String titulo;
  final String moneda;

  /// Con empleado, es la vista "Mi agenda" y no repite el barbero.
  final String? empleadoId;
  final DateTime? fechaInicial;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  late DateTime _fecha;
  List<Cita> _citas = [];
  bool _cargando = true;
  String? _error;
  String? _actualizandoId;

  @override
  void initState() {
    super.initState();
    final inicial = widget.fechaInicial ?? DateTime.now();
    _fecha = DateTime(inicial.year, inicial.month, inicial.day);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final citas = await widget.repository.listarDelDia(
        negocioId: widget.negocioId,
        fecha: _fecha,
        empleadoId: widget.empleadoId,
      );
      if (mounted) setState(() => _citas = citas);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la agenda.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _moverDia(int dias) {
    setState(() => _fecha = _fecha.add(Duration(days: dias)));
    _cargar();
  }

  void _irAHoy() {
    final ahora = DateTime.now();
    setState(() => _fecha = DateTime(ahora.year, ahora.month, ahora.day));
    _cargar();
  }

  Future<void> _marcar(Cita cita, EstadoCita estado) async {
    // Tocar de nuevo el estado marcado lo devuelve a pendiente.
    final nuevo = cita.estado == estado ? EstadoCita.pendiente : estado;
    final indice = _citas.indexWhere((item) => item.id == cita.id);
    if (indice < 0) return;

    setState(() {
      _actualizandoId = cita.id;
      _citas = [..._citas]..[indice] = cita.conEstado(nuevo);
    });

    try {
      await widget.repository.cambiarEstado(
        negocioId: widget.negocioId,
        citaId: cita.id,
        estado: nuevo,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _citas = [..._citas]..[indice] = cita);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar la cita.')),
      );
    } finally {
      if (mounted) setState(() => _actualizandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth >= 860;
        return Padding(
          padding: EdgeInsets.all(ancho ? 28 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.titulo,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _SelectorDia(
                fecha: _fecha,
                onAnterior: () => _moverDia(-1),
                onSiguiente: () => _moverDia(1),
                onHoy: _irAHoy,
              ),
              const SizedBox(height: 16),
              Expanded(child: _contenido()),
            ],
          ),
        );
      },
    );
  }

  Widget _contenido() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_citas.isEmpty) {
      return const Center(child: Text('No hay citas para este día.'));
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: _citas.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) => _FilaCita(
          cita: _citas[index],
          moneda: widget.moneda,
          mostrarBarbero: widget.empleadoId == null,
          ocupada: _actualizandoId == _citas[index].id,
          onMarcar: (estado) => _marcar(_citas[index], estado),
        ),
      ),
    );
  }
}

class _SelectorDia extends StatelessWidget {
  const _SelectorDia({
    required this.fecha,
    required this.onAnterior,
    required this.onSiguiente,
    required this.onHoy,
  });

  final DateTime fecha;
  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;
  final VoidCallback onHoy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Día anterior',
              onPressed: onAnterior,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                formatoFechaLarga(fecha),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Día siguiente',
              onPressed: onSiguiente,
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: onHoy,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              child: const Text('Hoy'),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _FilaCita extends StatelessWidget {
  const _FilaCita({
    required this.cita,
    required this.moneda,
    required this.mostrarBarbero,
    required this.ocupada,
    required this.onMarcar,
  });

  final Cita cita;
  final String moneda;
  final bool mostrarBarbero;
  final bool ocupada;
  final ValueChanged<EstadoCita> onMarcar;

  @override
  Widget build(BuildContext context) {
    final detalle = [
      cita.servicioNombre,
      formatoMoneda(cita.precio, moneda),
      if (mostrarBarbero && cita.empleadoNombre.isNotEmpty) cita.empleadoNombre,
    ].where((texto) => texto.isNotEmpty).join(' · ');
    final cerrada =
        cita.estado == EstadoCita.cancelada ||
        cita.estado == EstadoCita.completada;

    final info = Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            formatoHora(cita.horaInicio),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cita.clienteNombre,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                detalle,
                style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );

    final acciones = cerrada
        ? [EstadoCitaBadge(estado: cita.estado)]
        : [
            _BotonEstado(
              etiqueta: 'Llegó',
              color: Marca.verde,
              activo: cita.estado == EstadoCita.llego,
              onPressed: ocupada ? null : () => onMarcar(EstadoCita.llego),
            ),
            const SizedBox(width: 8),
            _BotonEstado(
              etiqueta: 'No vino',
              color: Marca.rojo,
              activo: cita.estado == EstadoCita.noVino,
              onPressed: ocupada ? null : () => onMarcar(EstadoCita.noVino),
            ),
          ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // En teléfono los botones van debajo para no apretar el nombre.
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Row(children: acciones),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 8),
              ...acciones,
            ],
          );
        },
      ),
    );
  }
}

class _BotonEstado extends StatelessWidget {
  const _BotonEstado({
    required this.etiqueta,
    required this.color,
    required this.activo,
    required this.onPressed,
  });

  final String etiqueta;
  final Color color;
  final bool activo;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(74, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: activo ? Colors.white : color,
        backgroundColor: activo ? color : color.withValues(alpha: 0.06),
        side: BorderSide(color: color.withValues(alpha: activo ? 1 : 0.5)),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      child: Text(etiqueta),
    );
  }
}
