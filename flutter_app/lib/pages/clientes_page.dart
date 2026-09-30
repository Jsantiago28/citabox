import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../services/clientes_repository.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({
    super.key,
    required this.negocioId,
    required this.repository,
  });

  final String negocioId;
  final ClientesRepository repository;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _searchController = TextEditingController();
  List<Cliente> _clientes = [];
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

        return Padding(
          padding: EdgeInsets.all(isWide ? 28 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clientes',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('${_clientes.length} registrados'),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _abrirFormulario(),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Nuevo cliente'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar cliente',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
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

    if (isWide) {
      return SingleChildScrollView(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Nombre')),
              DataColumn(label: Text('Teléfono')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Acciones')),
            ],
            rows: clientes.map(_desktopRow).toList(growable: false),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: clientes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _mobileTile(clientes[index]),
    );
  }

  DataRow _desktopRow(Cliente cliente) {
    return DataRow(
      cells: [
        DataCell(Text(cliente.nombre)),
        DataCell(Text(cliente.telefono.isEmpty ? '—' : cliente.telefono)),
        DataCell(Text(cliente.email.isEmpty ? '—' : cliente.email)),
        DataCell(_EstadoCliente(activo: cliente.activo)),
        DataCell(_acciones(cliente)),
      ],
    );
  }

  Widget _mobileTile(Cliente cliente) {
    final contacto = [
      cliente.telefono,
      cliente.email,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            cliente.nombre.isEmpty ? '?' : cliente.nombre[0].toUpperCase(),
          ),
        ),
        title: Text(cliente.nombre),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(contacto.isEmpty ? 'Sin datos de contacto' : contacto),
            const SizedBox(height: 6),
            _EstadoCliente(activo: cliente.activo, compact: true),
          ],
        ),
        isThreeLine: true,
        trailing: _acciones(cliente),
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
            : const Icon(Icons.more_vert),
      ),
    );
  }
}

class _EstadoCliente extends StatelessWidget {
  const _EstadoCliente({required this.activo, this.compact = false});

  final bool activo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = activo ? const Color(0xFF287A4B) : const Color(0xFF72756F);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(color: color, fontSize: compact ? 11 : 13),
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
