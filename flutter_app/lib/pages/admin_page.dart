import 'package:flutter/material.dart';

import '../services/plataforma_repository.dart';

const _planes = <String, String>{
  'solo': 'Solo',
  'barberia': 'Barbería',
  'pro': 'Pro',
};

String _fechaCorta(DateTime? f) => f == null
    ? '—'
    : '${f.day.toString().padLeft(2, '0')}/'
          '${f.month.toString().padLeft(2, '0')}/${f.year}';

/// Panel del administrador de la plataforma (`#/admin`).
class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.repository});

  final AdminRepository repository;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late Future<_Datos?> _datos = _cargar();

  Future<_Datos?> _cargar() async {
    if (!await widget.repository.esAdmin()) return null;
    final negocios = await widget.repository.listarNegocios();
    final soporte = await widget.repository.listarSoporte();
    return _Datos(negocios, soporte);
  }

  void _recargar() => setState(() => _datos = _cargar());

  Future<void> _activar(NegocioAdmin n) async {
    final r = await showDialog<(String, DateTime)>(
      context: context,
      builder: (_) => _ActivarDialog(negocio: n),
    );
    if (r == null) return;
    try {
      await widget.repository.activar(negocioId: n.id, plan: r.$1, hasta: r.$2);
      _recargar();
    } catch (_) {
      _aviso('No se pudo activar.');
    }
  }

  Future<void> _suspender(NegocioAdmin n) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Suspender ${n.nombre}'),
        content: TextField(
          controller: motivo,
          decoration: const InputDecoration(labelText: 'Motivo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Suspender'),
          ),
        ],
      ),
    );
    final texto = motivo.text;
    if (ok != true) return;
    try {
      await widget.repository.suspender(negocioId: n.id, motivo: texto);
      _recargar();
    } catch (_) {
      _aviso('No se pudo suspender.');
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración de la plataforma'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _recargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_Datos?>(
        future: _datos,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No se pudo cargar el panel.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _recargar,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }
          final datos = snap.data;
          if (datos == null) {
            return const Center(child: Text('No autorizado'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Negocios (${datos.negocios.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Negocio')),
                    DataColumn(label: Text('Dueño')),
                    DataColumn(label: Text('Plan')),
                    DataColumn(label: Text('Estado')),
                    DataColumn(label: Text('Prueba hasta')),
                    DataColumn(label: Text('Pagado hasta')),
                    DataColumn(label: Text('Barberos'), numeric: true),
                    DataColumn(label: Text('Citas 30d'), numeric: true),
                    DataColumn(label: Text('Acciones')),
                  ],
                  rows: [
                    for (final n in datos.negocios)
                      DataRow(
                        cells: [
                          DataCell(Text('${n.nombre}\n/${n.slug}')),
                          DataCell(Text(n.duenoCorreo ?? '—')),
                          DataCell(Text(n.plan)),
                          DataCell(Text(n.estado)),
                          DataCell(Text(_fechaCorta(n.pruebaHasta))),
                          DataCell(Text(_fechaCorta(n.pagadoHasta))),
                          DataCell(Text('${n.barberos}')),
                          DataCell(Text('${n.citas30d}')),
                          DataCell(
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => _activar(n),
                                  child: const Text('Activar'),
                                ),
                                TextButton(
                                  onPressed: () => _suspender(n),
                                  child: const Text('Suspender'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Soporte (${datos.soporte.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (datos.soporte.isEmpty)
                const Text('Sin mensajes de soporte.')
              else
                for (final m in datos.soporte)
                  Card(
                    child: ListTile(
                      title: Text(m.mensaje),
                      subtitle: Text(
                        '${m.negocio} · ${_fechaCorta(m.creado?.toLocal())}'
                        '${m.contexto == null ? '' : '\n${m.contexto}'}',
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Datos {
  const _Datos(this.negocios, this.soporte);

  final List<NegocioAdmin> negocios;
  final List<MensajeSoporte> soporte;
}

class _ActivarDialog extends StatefulWidget {
  const _ActivarDialog({required this.negocio});

  final NegocioAdmin negocio;

  @override
  State<_ActivarDialog> createState() => _ActivarDialogState();
}

class _ActivarDialogState extends State<_ActivarDialog> {
  late String _plan = _planes.containsKey(widget.negocio.plan)
      ? widget.negocio.plan
      : 'barberia';
  late DateTime _hasta = () {
    final h = DateTime.now();
    return DateTime(h.year, h.month + 1, h.day);
  }();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Activar ${widget.negocio.nombre}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _plan,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: [
              for (final e in _planes.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _plan = v ?? _plan),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('Pagado hasta: ${_fechaCorta(_hasta)}'),
            onPressed: () async {
              final f = await showDatePicker(
                context: context,
                initialDate: _hasta,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 800)),
              );
              if (f != null) setState(() => _hasta = f);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_plan, _hasta)),
          child: const Text('Activar'),
        ),
      ],
    );
  }
}
