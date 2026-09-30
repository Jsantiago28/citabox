import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../services/clientes_repository.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../widgets/estado_cita_badge.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({
    super.key,
    required this.negocioId,
    required this.repository,
    this.moneda = 'DOP',
  });

  final String negocioId;
  final ClientesRepository repository;
  final String moneda;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _searchController = TextEditingController();
  List<Cliente> _clientes = [];
  Map<String, ResumenCliente> _resumen = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _changingStatusId;

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final clientes = await widget.repository.listar(widget.negocioId);
      if (mounted) setState(() => _clientes = clientes);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar los clientes.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    // El resumen es complementario: si falla, la lista sigue usable.
    try {
      final resumen = await widget.repository.resumen(widget.negocioId);
      if (mounted) setState(() => _resumen = resumen);
    } catch (_) {}
  }

  Future<void> _abrirFormulario([Cliente? cliente]) async {
    final datos = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _ClienteFormDialog(cliente: cliente),
    );
    if (datos == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repository.guardar(
        negocioId: widget.negocioId,
        clienteId: cliente?.id,
        datos: datos,
      );
      await _cargarClientes();
    } catch (_) {
      if (mounted) _mostrarError('No se pudo guardar el cliente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cambiarEstado(Cliente cliente) async {
    setState(() => _changingStatusId = cliente.id);
    try {
      await widget.repository.cambiarEstado(
        negocioId: widget.negocioId,
        clienteId: cliente.id,
        activo: !cliente.activo,
      );
      await _cargarClientes();
    } catch (_) {
      if (mounted) {
        _mostrarError('No se pudo actualizar el estado del cliente.');
      }
    } finally {
      if (mounted) setState(() => _changingStatusId = null);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  List<Cliente> get _clientesFiltrados {
    final consulta = _searchController.text.trim().toLowerCase();
    if (consulta.isEmpty) return _clientes;

    return _clientes
        .where((cliente) {
          return cliente.nombre.toLowerCase().contains(consulta) ||
              cliente.telefono.toLowerCase().contains(consulta) ||
              cliente.email.toLowerCase().contains(consulta);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final clientes = _clientesFiltrados;
        final isWide = constraints.maxWidth >= 860;

        final buscador = SizedBox(
          width: isWide ? 280 : double.infinity,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar cliente…',
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
          label: const Text('Nuevo cliente'),
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
                          'Clientes',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_clientes.length} registrados',
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
              Expanded(child: _buildContent(clientes, isWide)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(List<Cliente> clientes, bool isWide) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _cargarClientes,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (clientes.isEmpty) {
      return Center(
        child: Text(
          _clientes.isEmpty
              ? 'Todavía no hay clientes.'
              : 'No hay coincidencias.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: clientes.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) => _fila(clientes[index], isWide),
      ),
    );
  }

  Widget _fila(Cliente cliente, bool isWide) {
    final resumen = _resumen[cliente.id] ?? const ResumenCliente();
    final visitas =
        '${resumen.visitas} ${resumen.visitas == 1 ? 'visita' : 'visitas'}';
    final gastado = formatoMoneda(resumen.gastado, widget.moneda);
    final contacto = cliente.telefono.isNotEmpty
        ? cliente.telefono
        : (cliente.email.isNotEmpty ? cliente.email : 'Sin contacto');

    final nombre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                cliente.nombre,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cliente.activo ? Marca.texto : Marca.textoSuave,
                ),
              ),
            ),
            if (!cliente.activo) ...[
              const SizedBox(width: 8),
              const _Etiqueta(texto: 'Inactivo', color: Marca.textoSuave),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          isWide ? contacto : '$contacto · $visitas',
          style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
        ),
      ],
    );

    return InkWell(
      onTap: () => _abrirFormulario(cliente),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            AvatarIniciales(texto: iniciales(cliente.nombre)),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: nombre),
            if (isWide) ...[
              Expanded(
                child: Text(
                  visitas,
                  style: const TextStyle(color: Marca.textoSuave),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  gastado,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 110,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: resumen.frecuente
                      ? const _Etiqueta(texto: 'Frecuente', color: Marca.verde)
                      : null,
                ),
              ),
            ] else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    gastado,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (resumen.frecuente) ...[
                    const SizedBox(height: 4),
                    const _Etiqueta(texto: 'Frecuente', color: Marca.verde),
                  ],
                ],
              ),
            _acciones(cliente),
          ],
        ),
      ),
    );
  }

  Widget _acciones(Cliente cliente) {
    final busy = _changingStatusId == cliente.id;
    return PopupMenuButton<String>(
      tooltip: 'Acciones de ${cliente.nombre}',
      enabled: !busy,
      onSelected: (accion) {
        if (accion == 'editar') _abrirFormulario(cliente);
        if (accion == 'estado') _cambiarEstado(cliente);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'editar', child: Text('Editar')),
        PopupMenuItem(
          value: 'estado',
          child: Text(cliente.activo ? 'Desactivar' : 'Activar'),
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

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ClienteFormDialog extends StatefulWidget {
  const _ClienteFormDialog({this.cliente});

  final Cliente? cliente;

  @override
  State<_ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends State<_ClienteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _emailController;
  late final TextEditingController _notasController;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(
      text: widget.cliente?.nombre ?? '',
    );
    _telefonoController = TextEditingController(
      text: widget.cliente?.telefono ?? '',
    );
    _emailController = TextEditingController(text: widget.cliente?.email ?? '');
    _notasController = TextEditingController(text: widget.cliente?.notas ?? '');
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(<String, Object?>{
      'nombre': _nombreController.text.trim(),
      'telefono': _telefonoController.text.trim().isEmpty
          ? null
          : _telefonoController.text.trim(),
      'email': _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      'notas': _notasController.text.trim().isEmpty
          ? null
          : _notasController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.cliente == null ? 'Nuevo cliente' : 'Editar cliente'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('cliente-nombre'),
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
                  key: const Key('cliente-telefono'),
                  controller: _telefonoController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('cliente-email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isNotEmpty &&
                        !RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
                      return 'Ingresa un email válido.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('cliente-notas'),
                  controller: _notasController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notas'),
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
          child: Text(
            widget.cliente == null ? 'Crear cliente' : 'Guardar cambios',
          ),
        ),
      ],
    );
  }
}
