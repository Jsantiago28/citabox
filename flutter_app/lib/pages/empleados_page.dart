import 'package:flutter/material.dart';

import '../models/empleado.dart';
import '../models/servicio.dart';
import '../services/empleados_repository.dart';
import '../services/servicios_repository.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../widgets/estado_cita_badge.dart';
import '../widgets/etiqueta.dart';

class EmpleadosPage extends StatefulWidget {
  const EmpleadosPage({
    super.key,
    required this.negocioId,
    required this.repository,
    required this.serviciosRepository,
  });

  final String negocioId;
  final EmpleadosRepository repository;
  final ServiciosRepository serviciosRepository;

  @override
  State<EmpleadosPage> createState() => _EmpleadosPageState();
}

class _EmpleadosPageState extends State<EmpleadosPage> {
  final _searchController = TextEditingController();
  List<Empleado> _empleados = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _changingStatusId;
  String? _seleccionadoId;

  @override
  void initState() {
    super.initState();
    _cargarEmpleados();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarEmpleados() async {
    setState(() {
      _loading = _empleados.isEmpty;
      _error = null;
    });

    try {
      final empleados = await widget.repository.listar(widget.negocioId);
      if (mounted) setState(() => _empleados = empleados);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar los empleados.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _abrirFormulario([Empleado? empleado]) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _EmpleadoFormDialog(empleado: empleado),
    );
    if (datos == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repository.guardar(
        negocioId: widget.negocioId,
        empleadoId: empleado?.id,
        datos: datos,
      );
      await _cargarEmpleados();
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo guardar el empleado.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cambiarEstado(Empleado empleado) async {
    setState(() => _changingStatusId = empleado.id);
    try {
      await widget.repository.cambiarEstado(
        negocioId: widget.negocioId,
        empleadoId: empleado.id,
        activo: !empleado.activo,
      );
      await _cargarEmpleados();
    } catch (_) {
      if (mounted) {
        _mostrarMensaje('No se pudo actualizar el estado del empleado.');
      }
    } finally {
      if (mounted) setState(() => _changingStatusId = null);
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  List<Empleado> get _empleadosFiltrados {
    final consulta = _searchController.text.trim().toLowerCase();
    if (consulta.isEmpty) return _empleados;

    return _empleados
        .where((empleado) {
          return empleado.nombre.toLowerCase().contains(consulta) ||
              empleado.telefono.toLowerCase().contains(consulta);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final seleccionado = _empleados
        .where((empleado) => empleado.id == _seleccionadoId)
        .firstOrNull;
    if (seleccionado != null) {
      return _EmpleadoDetalle(
        key: ValueKey('empleado-${seleccionado.id}'),
        negocioId: widget.negocioId,
        empleado: seleccionado,
        repository: widget.repository,
        serviciosRepository: widget.serviciosRepository,
        onVolver: () => setState(() => _seleccionadoId = null),
        onEditar: () => _abrirFormulario(seleccionado),
        onCambio: _cargarEmpleados,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final empleados = _empleadosFiltrados;
        final isWide = constraints.maxWidth >= 860;
        final activos = _empleados.where((empleado) => empleado.activo).length;

        final buscador = SizedBox(
          width: isWide ? 280 : double.infinity,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar empleado…',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
          ),
        );

        final nuevo = FilledButton.icon(
          onPressed: _saving ? null : () => _abrirFormulario(),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nuevo empleado'),
        );

        return Padding(
          padding: EdgeInsets.all(isWide ? 28 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Empleados',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$activos activos de ${_empleados.length}',
                          style: const TextStyle(color: Marca.textoSuave),
                        ),
                      ],
                    ),
                  ),
                  if (isWide) ...[buscador, const SizedBox(width: 12)],
                  nuevo,
                ],
              ),
              if (!isWide) ...[const SizedBox(height: 16), buscador],
              const SizedBox(height: 16),
              Expanded(child: _buildContent(empleados, isWide)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(List<Empleado> empleados, bool isWide) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _cargarEmpleados,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (empleados.isEmpty) {
      return Center(
        child: Text(
          _empleados.isEmpty
              ? 'Todavía no hay empleados.\nAgrega a tu equipo con "Nuevo empleado".'
              : 'No hay coincidencias.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: empleados.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) => _fila(empleados[index], isWide),
      ),
    );
  }

  Widget _fila(Empleado empleado, bool isWide) {
    final cuenta = empleado.tieneCuenta
        ? const Etiqueta(texto: 'Tiene cuenta', color: Marca.verde)
        : const Etiqueta(texto: 'Sin cuenta', color: Marca.textoSuave);

    return InkWell(
      onTap: () => setState(() => _seleccionadoId = empleado.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            AvatarIniciales(texto: iniciales(empleado.nombre)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          empleado.nombre,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: empleado.activo
                                ? Marca.texto
                                : Marca.textoSuave,
                          ),
                        ),
                      ),
                      if (!empleado.activo) ...[
                        const SizedBox(width: 8),
                        const Etiqueta(
                          texto: 'Inactivo',
                          color: Marca.textoSuave,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    empleado.telefono.isEmpty
                        ? 'Sin teléfono'
                        : empleado.telefono,
                    style: const TextStyle(
                      color: Marca.textoSuave,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            cuenta,
            _acciones(empleado),
          ],
        ),
      ),
    );
  }

  Widget _acciones(Empleado empleado) {
    final busy = _changingStatusId == empleado.id;
    return PopupMenuButton<String>(
      tooltip: 'Acciones de ${empleado.nombre}',
      enabled: !busy,
      onSelected: (accion) {
        if (accion == 'ver') setState(() => _seleccionadoId = empleado.id);
        if (accion == 'editar') _abrirFormulario(empleado);
        if (accion == 'estado') _cambiarEstado(empleado);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'ver', child: Text('Servicios y horario')),
        const PopupMenuItem(value: 'editar', child: Text('Editar')),
        PopupMenuItem(
          value: 'estado',
          child: Text(empleado.activo ? 'Desactivar' : 'Activar'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.more_vert, color: Marca.textoSuave),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detalle de un empleado: cuenta, servicios, horario y días libres.
// ---------------------------------------------------------------------------

class _EmpleadoDetalle extends StatefulWidget {
  const _EmpleadoDetalle({
    super.key,
    required this.negocioId,
    required this.empleado,
    required this.repository,
    required this.serviciosRepository,
    required this.onVolver,
    required this.onEditar,
    required this.onCambio,
  });

  final String negocioId;
  final Empleado empleado;
  final EmpleadosRepository repository;
  final ServiciosRepository serviciosRepository;
  final VoidCallback onVolver;
  final VoidCallback onEditar;
  final Future<void> Function() onCambio;

  @override
  State<_EmpleadoDetalle> createState() => _EmpleadoDetalleState();
}

class _EmpleadoDetalleState extends State<_EmpleadoDetalle> {
  List<Servicio> _servicios = [];
  Set<String> _asignados = {};
  List<HorarioDia> _horario = [];
  List<BloqueoEmpleado> _bloqueos = [];
  bool _loading = true;
  bool _ocupado = false;
  String? _error;

  String get _empleadoId => widget.empleado.id;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = widget.repository;
      final negocioId = widget.negocioId;
      final resultados = await Future.wait<Object>([
        widget.serviciosRepository.listar(negocioId),
        repo.serviciosAsignados(negocioId: negocioId, empleadoId: _empleadoId),
        repo.horario(negocioId: negocioId, empleadoId: _empleadoId),
        repo.bloqueos(negocioId: negocioId, empleadoId: _empleadoId),
      ]);
      if (!mounted) return;
      setState(() {
        _servicios = resultados[0] as List<Servicio>;
        _asignados = resultados[1] as Set<String>;
        _horario = resultados[2] as List<HorarioDia>;
        _bloqueos = resultados[3] as List<BloqueoEmpleado>;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar la información.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ejecuta una acción con indicador de carga y mensaje de error.
  Future<bool> _ejecutar(
    Future<void> Function() accion,
    String mensajeError,
  ) async {
    setState(() => _ocupado = true);
    try {
      await accion();
      return true;
    } catch (_) {
      if (mounted) _mostrarMensaje(mensajeError);
      return false;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _elegirServicios() async {
    final elegidos = await showDialog<Set<String>>(
      context: context,
      builder: (context) =>
          _ServiciosDialog(servicios: _servicios, asignados: _asignados),
    );
    if (elegidos == null || !mounted) return;

    final ok = await _ejecutar(
      () => widget.repository.guardarServicios(
        negocioId: widget.negocioId,
        empleadoId: _empleadoId,
        servicioIds: elegidos,
      ),
      'No se pudieron guardar los servicios.',
    );
    if (ok && mounted) setState(() => _asignados = elegidos);
  }

  Future<void> _editarHorario() async {
    final dias = await showDialog<List<HorarioDia>>(
      context: context,
      builder: (context) => _HorarioDialog(horario: _horario),
    );
    if (dias == null || !mounted) return;

    final ok = await _ejecutar(
      () => widget.repository.guardarHorario(
        negocioId: widget.negocioId,
        empleadoId: _empleadoId,
        dias: dias,
      ),
      'No se pudo guardar el horario.',
    );
    if (ok && mounted) setState(() => _horario = dias);
  }

  Future<void> _agregarBloqueo() async {
    final bloqueo = await showDialog<_NuevoBloqueo>(
      context: context,
      builder: (context) => const _BloqueoDialog(),
    );
    if (bloqueo == null || !mounted) return;

    final ok = await _ejecutar(
      () => widget.repository.agregarBloqueo(
        negocioId: widget.negocioId,
        empleadoId: _empleadoId,
        fechaInicio: bloqueo.inicio,
        fechaFin: bloqueo.fin,
        motivo: bloqueo.motivo,
      ),
      'No se pudo guardar el día libre.',
    );
    if (ok) await _recargarBloqueos();
  }

  Future<void> _eliminarBloqueo(BloqueoEmpleado bloqueo) async {
    final ok = await _ejecutar(
      () => widget.repository.eliminarBloqueo(
        negocioId: widget.negocioId,
        bloqueoId: bloqueo.id,
      ),
      'No se pudo eliminar el día libre.',
    );
    if (ok) await _recargarBloqueos();
  }

  Future<void> _recargarBloqueos() async {
    try {
      final bloqueos = await widget.repository.bloqueos(
        negocioId: widget.negocioId,
        empleadoId: _empleadoId,
      );
      if (mounted) setState(() => _bloqueos = bloqueos);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudieron cargar los días libres.');
    }
  }

  Future<void> _invitar() async {
    final email = await showDialog<String>(
      context: context,
      builder: (context) => _InvitarDialog(nombre: widget.empleado.nombre),
    );
    if (email == null || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await widget.repository.invitar(empleadoId: _empleadoId, email: email);
      if (!mounted) return;
      _mostrarMensaje('Invitación enviada a $email.');
      await widget.onCambio();
    } on InvitacionException catch (error) {
      if (mounted) _mostrarMensaje(error.mensaje);
    } catch (_) {
      if (mounted) _mostrarMensaje('No se pudo enviar la invitación.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empleado = widget.empleado;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        final encabezado = Row(
          children: [
            IconButton(
              tooltip: 'Volver a empleados',
              onPressed: widget.onVolver,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            AvatarIniciales(texto: iniciales(empleado.nombre), radio: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          empleado.nombre,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!empleado.activo) ...[
                        const SizedBox(width: 8),
                        const Etiqueta(
                          texto: 'Inactivo',
                          color: Marca.textoSuave,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    empleado.telefono.isEmpty
                        ? 'Sin teléfono'
                        : empleado.telefono,
                    style: const TextStyle(color: Marca.textoSuave),
                  ),
                ],
              ),
            ),
            if (_ocupado)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            OutlinedButton.icon(
              onPressed: widget.onEditar,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar'),
            ),
          ],
        );

        return Padding(
          padding: EdgeInsets.all(isWide ? 28 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              encabezado,
              const SizedBox(height: 16),
              Expanded(child: _contenido(isWide)),
            ],
          ),
        );
      },
    );
  }

  Widget _contenido(bool isWide) {
    if (_loading) return const Center(child: CircularProgressIndicator());

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

    final tarjetas = [
      _tarjetaCuenta(),
      _tarjetaServicios(),
      _tarjetaHorario(),
      _tarjetaBloqueos(),
    ];

    if (!isWide) {
      return ListView.separated(
        itemCount: tarjetas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => tarjetas[index],
      );
    }

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [tarjetas[0], const SizedBox(height: 16), tarjetas[1]],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [tarjetas[2], const SizedBox(height: 16), tarjetas[3]],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCuenta() {
    final empleado = widget.empleado;
    if (empleado.tieneCuenta) {
      return const _Tarjeta(
        titulo: 'Cuenta en la app',
        icono: Icons.phone_iphone,
        child: Row(
          children: [
            Etiqueta(texto: 'Tiene cuenta', color: Marca.verde),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Puede entrar a la app y ver su agenda.',
                style: TextStyle(color: Marca.textoSuave),
              ),
            ),
          ],
        ),
      );
    }

    return _Tarjeta(
      titulo: 'Cuenta en la app',
      icono: Icons.phone_iphone,
      accion: FilledButton.icon(
        onPressed: _ocupado ? null : _invitar,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
        icon: const Icon(Icons.send_outlined, size: 16),
        label: const Text('Invitar a la app'),
      ),
      child: const Text(
        'Aún no tiene cuenta. Invítalo por correo para que vea su agenda.',
        style: TextStyle(color: Marca.textoSuave),
      ),
    );
  }

  Widget _tarjetaServicios() {
    final nombres = {
      for (final servicio in _servicios) servicio.id: servicio.nombre,
    };
    final asignados =
        _asignados
            .map((id) => nombres[id])
            .whereType<String>()
            .toList(growable: false)
          ..sort();

    return _Tarjeta(
      titulo: 'Servicios que hace',
      icono: Icons.content_cut,
      accion: TextButton(
        onPressed: _ocupado ? null : _elegirServicios,
        child: const Text('Elegir servicios'),
      ),
      child: _asignados.isEmpty
          ? const _TextoConDetalle(
              texto: 'Todos los servicios',
              detalle: 'Incluye los servicios que agregues después.',
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final nombre in asignados)
                  Chip(
                    label: Text(nombre),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
    );
  }

  Widget _tarjetaHorario() {
    final porDia = {for (final dia in _horario) dia.diaSemana: dia};

    return _Tarjeta(
      titulo: 'Horario semanal',
      icono: Icons.schedule,
      accion: TextButton(
        onPressed: _ocupado ? null : _editarHorario,
        child: const Text('Editar horario'),
      ),
      child: _horario.isEmpty
          ? const _TextoConDetalle(
              texto: 'Usa el horario del negocio',
              detalle: 'Trabaja los mismos días y horas que abre el negocio.',
            )
          : Column(
              children: [
                for (final dia in ordenDias)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(width: 100, child: Text(nombresDias[dia])),
                        Expanded(
                          child: Text(
                            porDia[dia] == null
                                ? 'Libre'
                                : '${formatoHora(porDia[dia]!.horaInicio)} – '
                                      '${formatoHora(porDia[dia]!.horaFin)}',
                            style: TextStyle(
                              color: porDia[dia] == null
                                  ? Marca.textoSuave
                                  : Marca.texto,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _tarjetaBloqueos() {
    return _Tarjeta(
      titulo: 'Días libres y vacaciones',
      icono: Icons.beach_access_outlined,
      accion: TextButton(
        onPressed: _ocupado ? null : _agregarBloqueo,
        child: const Text('Agregar día libre'),
      ),
      child: _bloqueos.isEmpty
          ? const Text(
              'Sin días libres programados.',
              style: TextStyle(color: Marca.textoSuave),
            )
          : Column(
              children: [
                for (final bloqueo in _bloqueos)
                  Row(
                    children: [
                      Expanded(
                        child: _TextoConDetalle(
                          texto: _rangoFechas(bloqueo),
                          detalle: bloqueo.motivo.isEmpty
                              ? null
                              : bloqueo.motivo,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Eliminar día libre',
                        onPressed: _ocupado
                            ? null
                            : () => _eliminarBloqueo(bloqueo),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Marca.textoSuave,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }

  static String _rangoFechas(BloqueoEmpleado bloqueo) {
    final inicio = formatoFechaLarga(bloqueo.fechaInicio);
    if (formatoFechaIso(bloqueo.fechaInicio) ==
        formatoFechaIso(bloqueo.fechaFin)) {
      return inicio;
    }
    return '$inicio – ${formatoFechaLarga(bloqueo.fechaFin)}';
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.titulo,
    required this.icono,
    required this.child,
    this.accion,
  });

  final String titulo;
  final IconData icono;
  final Widget child;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // En pantallas angostas la acción baja debajo del contenido.
            final angosta = constraints.maxWidth < 380;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icono, size: 18, color: Marca.dorado),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titulo,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!angosta) ?accion,
                  ],
                ),
                const SizedBox(height: 10),
                child,
                if (angosta && accion != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: accion),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TextoConDetalle extends StatelessWidget {
  const _TextoConDetalle({required this.texto, this.detalle});

  final String texto;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (detalle != null)
          Text(
            detalle!,
            style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogos
// ---------------------------------------------------------------------------

class _EmpleadoFormDialog extends StatefulWidget {
  const _EmpleadoFormDialog({this.empleado});

  final Empleado? empleado;

  @override
  State<_EmpleadoFormDialog> createState() => _EmpleadoFormDialogState();
}

class _EmpleadoFormDialogState extends State<_EmpleadoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _telefonoController;
  late bool _activo;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(
      text: widget.empleado?.nombre ?? '',
    );
    _telefonoController = TextEditingController(
      text: widget.empleado?.telefono ?? '',
    );
    _activo = widget.empleado?.activo ?? true;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final telefono = _telefonoController.text.trim();
    Navigator.of(context).pop(<String, Object?>{
      'nombre': _nombreController.text.trim(),
      'telefono': telefono.isEmpty ? null : telefono,
      'activo': _activo,
    });
  }

  @override
  Widget build(BuildContext context) {
    final esNuevo = widget.empleado == null;
    return AlertDialog(
      title: Text(esNuevo ? 'Nuevo empleado' : 'Editar empleado'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('empleado-nombre'),
                  controller: _nombreController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'El nombre es obligatorio.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('empleado-telefono'),
                  controller: _telefonoController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('empleado-activo'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  subtitle: const Text('Puede recibir citas.'),
                  value: _activo,
                  onChanged: (value) => setState(() => _activo = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardar,
          child: Text(esNuevo ? 'Crear empleado' : 'Guardar cambios'),
        ),
      ],
    );
  }
}

class _InvitarDialog extends StatefulWidget {
  const _InvitarDialog({required this.nombre});

  final String nombre;

  @override
  State<_InvitarDialog> createState() => _InvitarDialogState();
}

class _InvitarDialogState extends State<_InvitarDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _enviar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_emailController.text.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invitar a la app'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.nombre} recibirá un correo para crear su contraseña '
                'y entrar a ver su agenda.',
                style: const TextStyle(color: Marca.textoSuave),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('invitar-email'),
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo'),
                onFieldSubmitted: (_) => _enviar(),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
                    return 'Ingresa un correo válido.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviar,
          child: const Text('Enviar invitación'),
        ),
      ],
    );
  }
}

class _ServiciosDialog extends StatefulWidget {
  const _ServiciosDialog({required this.servicios, required this.asignados});

  final List<Servicio> servicios;
  final Set<String> asignados;

  @override
  State<_ServiciosDialog> createState() => _ServiciosDialogState();
}

class _ServiciosDialogState extends State<_ServiciosDialog> {
  late bool _todos = widget.asignados.isEmpty;
  late final Set<String> _elegidos = {...widget.asignados};
  String? _error;

  /// Activos, más los inactivos que ya tenía asignados.
  List<Servicio> get _opciones => widget.servicios
      .where(
        (servicio) => servicio.activo || widget.asignados.contains(servicio.id),
      )
      .toList(growable: false);

  void _guardar() {
    if (_todos) {
      Navigator.of(context).pop(<String>{});
      return;
    }
    if (_elegidos.isEmpty) {
      setState(
        () => _error =
            'Elige al menos un servicio o marca "Todos los servicios".',
      );
      return;
    }
    Navigator.of(context).pop({..._elegidos});
  }

  @override
  Widget build(BuildContext context) {
    final opciones = _opciones;
    return AlertDialog(
      title: const Text('Servicios que hace'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const Key('servicios-todos'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Todos los servicios'),
                subtitle: const Text(
                  'Incluye los servicios que agregues después.',
                ),
                value: _todos,
                onChanged: (value) => setState(() {
                  _todos = value;
                  _error = null;
                }),
              ),
              if (!_todos) ...[
                const Divider(),
                if (opciones.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Todavía no hay servicios activos.'),
                  ),
                for (final servicio in opciones)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(servicio.nombre),
                    subtitle: servicio.activo
                        ? Text(formatoDuracion(servicio.duracionMinutos))
                        : const Text('Inactivo'),
                    value: _elegidos.contains(servicio.id),
                    onChanged: (marcado) => setState(() {
                      _error = null;
                      if (marcado == true) {
                        _elegidos.add(servicio.id);
                      } else {
                        _elegidos.remove(servicio.id);
                      }
                    }),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Marca.rojo)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Horas cada 15 minutos, de 05:00 a 23:45.
final List<String> _horasDisponibles = [
  for (var minutos = 5 * 60; minutos < 24 * 60; minutos += 15)
    '${(minutos ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutos % 60).toString().padLeft(2, '0')}',
];

class _HorarioDialog extends StatefulWidget {
  const _HorarioDialog({required this.horario});

  final List<HorarioDia> horario;

  @override
  State<_HorarioDialog> createState() => _HorarioDialogState();
}

class _HorarioDialogState extends State<_HorarioDialog> {
  late bool _usaNegocio = widget.horario.isEmpty;
  final Map<int, ({String inicio, String fin})> _dias = {};
  final Set<int> _trabaja = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    for (var dia = 0; dia < 7; dia++) {
      _dias[dia] = (inicio: '09:00', fin: '18:00');
    }
    for (final dia in widget.horario) {
      _dias[dia.diaSemana] = (inicio: dia.horaInicio, fin: dia.horaFin);
      _trabaja.add(dia.diaSemana);
    }
    if (widget.horario.isEmpty) {
      // Propuesta inicial al personalizar: lunes a sábado.
      _trabaja.addAll([1, 2, 3, 4, 5, 6]);
    }
  }

  void _guardar() {
    if (_usaNegocio) {
      Navigator.of(context).pop(const <HorarioDia>[]);
      return;
    }
    if (_trabaja.isEmpty) {
      setState(
        () => _error = 'Elige al menos un día o usa el horario del negocio.',
      );
      return;
    }
    for (final dia in ordenDias.where(_trabaja.contains)) {
      final rango = _dias[dia]!;
      if (rango.fin.compareTo(rango.inicio) <= 0) {
        setState(
          () => _error =
              '${nombresDias[dia]}: la hora de salida debe ser después '
              'de la de entrada.',
        );
        return;
      }
    }

    Navigator.of(context).pop([
      for (final dia in ordenDias.where(_trabaja.contains))
        HorarioDia(
          diaSemana: dia,
          horaInicio: _dias[dia]!.inicio,
          horaFin: _dias[dia]!.fin,
        ),
    ]);
  }

  Widget _selectorHora({
    required String etiqueta,
    required String valor,
    required ValueChanged<String> onChanged,
  }) {
    final opciones = _horasDisponibles.contains(valor)
        ? _horasDisponibles
        : ([..._horasDisponibles, valor]..sort());
    return DropdownButtonFormField<String>(
      initialValue: valor,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(labelText: etiqueta),
      items: [
        for (final hora in opciones)
          DropdownMenuItem(value: hora, child: Text(formatoHora(hora))),
      ],
      onChanged: (hora) {
        if (hora != null) onChanged(hora);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Horario semanal'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const Key('horario-negocio'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Usar el horario del negocio'),
                subtitle: const Text(
                  'Trabaja los mismos días y horas que abre el negocio.',
                ),
                value: _usaNegocio,
                onChanged: (value) => setState(() {
                  _usaNegocio = value;
                  _error = null;
                }),
              ),
              if (!_usaNegocio) ...[
                const Divider(),
                for (final dia in ordenDias) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(nombresDias[dia]),
                    subtitle: _trabaja.contains(dia)
                        ? null
                        : const Text('Libre'),
                    value: _trabaja.contains(dia),
                    onChanged: (marcado) => setState(() {
                      _error = null;
                      if (marcado == true) {
                        _trabaja.add(dia);
                      } else {
                        _trabaja.remove(dia);
                      }
                    }),
                  ),
                  if (_trabaja.contains(dia))
                    Padding(
                      padding: const EdgeInsets.only(left: 48, bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _selectorHora(
                              etiqueta: 'Entra',
                              valor: _dias[dia]!.inicio,
                              onChanged: (hora) => setState(() {
                                _error = null;
                                _dias[dia] = (
                                  inicio: hora,
                                  fin: _dias[dia]!.fin,
                                );
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _selectorHora(
                              etiqueta: 'Sale',
                              valor: _dias[dia]!.fin,
                              onChanged: (hora) => setState(() {
                                _error = null;
                                _dias[dia] = (
                                  inicio: _dias[dia]!.inicio,
                                  fin: hora,
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Marca.rojo)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

class _NuevoBloqueo {
  const _NuevoBloqueo({required this.inicio, required this.fin, this.motivo});

  final DateTime inicio;
  final DateTime fin;
  final String? motivo;
}

class _BloqueoDialog extends StatefulWidget {
  const _BloqueoDialog();

  @override
  State<_BloqueoDialog> createState() => _BloqueoDialogState();
}

class _BloqueoDialogState extends State<_BloqueoDialog> {
  final _motivoController = TextEditingController();
  late DateTime _inicio;
  late DateTime _fin;

  DateTime get _hoy {
    final ahora = DateTime.now();
    return DateTime(ahora.year, ahora.month, ahora.day);
  }

  @override
  void initState() {
    super.initState();
    _inicio = _hoy;
    _fin = _hoy;
  }

  @override
  void dispose() {
    _motivoController.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final primera = esInicio ? _hoy : _inicio;
    final actual = esInicio ? _inicio : _fin;
    final fecha = await showDatePicker(
      context: context,
      initialDate: actual.isBefore(primera) ? primera : actual,
      firstDate: primera,
      lastDate: DateTime(_hoy.year + 2, 12, 31),
      helpText: esInicio ? 'Desde' : 'Hasta',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
    );
    if (fecha == null || !mounted) return;
    setState(() {
      if (esInicio) {
        _inicio = fecha;
        if (_fin.isBefore(fecha)) _fin = fecha;
      } else {
        _fin = fecha;
      }
    });
  }

  void _guardar() {
    final motivo = _motivoController.text.trim();
    Navigator.of(context).pop(
      _NuevoBloqueo(
        inicio: _inicio,
        fin: _fin,
        motivo: motivo.isEmpty ? null : motivo,
      ),
    );
  }

  Widget _campoFecha(String etiqueta, DateTime fecha, bool esInicio) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _elegirFecha(esInicio: esInicio),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(formatoFechaLarga(fecha)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar día libre'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _campoFecha('Desde', _inicio, true),
              const SizedBox(height: 12),
              _campoFecha('Hasta (incluido)', _fin, false),
              const SizedBox(height: 12),
              TextField(
                key: const Key('bloqueo-motivo'),
                controller: _motivoController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  hintText: 'Vacaciones, cita médica…',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
