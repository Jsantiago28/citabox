import 'package:flutter/material.dart';

import '../services/plataforma_repository.dart';

const _planes = <String, String>{
  'solo': 'Solo',
  'barberia': 'Equipo',
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
    final resumen = await widget.repository.resumenUso();
    final soporte = await widget.repository.listarSoporte();
    final cuentas = await widget.repository.listarCuentas();
    return _Datos(negocios, soporte, cuentas, resumen);
  }

  void _recargar() {
    // El callback de setState no debe devolver el Future.
    setState(() {
      _datos = _cargar();
    });
  }

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

  Future<void> _recordatorios(NegocioAdmin n) async {
    final r = await showDialog<_Recordatorios>(
      context: context,
      builder: (_) => _RecordatoriosDialog(negocio: n),
    );
    if (r == null) return;
    try {
      await widget.repository.configurarRecordatorios(
        negocioId: n.id,
        activo: r.activo,
        cupo: r.cupo,
        precioMensual: r.precioMensual,
        precioExtra: r.precioExtra,
      );
      _recargar();
    } catch (_) {
      _aviso('No se pudieron guardar los recordatorios.');
    }
  }

  Future<void> _agregarCuenta() async {
    final datos = await showDialog<_NuevaCuenta>(
      context: context,
      builder: (_) => const _CuentaDialog(),
    );
    if (datos == null) return;
    try {
      await widget.repository.guardarCuenta(
        banco: datos.banco,
        tipo: datos.tipo,
        numero: datos.numero,
        titular: datos.titular,
      );
      _recargar();
    } catch (_) {
      _aviso('No se pudo guardar la cuenta.');
    }
  }

  Future<void> _borrarCuenta(CuentaPago c) async {
    try {
      await widget.repository.borrarCuenta(c.id);
      _recargar();
    } catch (_) {
      _aviso('No se pudo borrar la cuenta.');
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
          final ahora = DateTime.now();
          if (datos == null) {
            return const Center(child: Text('No autorizado'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Uso', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _ResumenUso(resumen: datos.resumen),
              const SizedBox(height: 24),
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
                    DataColumn(label: Text('Equipo'), numeric: true),
                    DataColumn(label: Text('Citas 30d'), numeric: true),
                    DataColumn(label: Text('En línea 30d'), numeric: true),
                    DataColumn(label: Text('Clientes'), numeric: true),
                    DataColumn(label: Text('Último acceso')),
                    DataColumn(label: Text('Última cita')),
                    DataColumn(label: Text('Recordatorios auto')),
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
                          DataCell(Text('${n.citasEnLinea30d}')),
                          DataCell(Text('${n.clientes}')),
                          DataCell(Text(haceCuanto(n.ultimoAcceso, ahora))),
                          DataCell(Text(haceCuanto(n.ultimaCita, ahora))),
                          DataCell(Text(textoRecordatoriosAdmin(n))),
                          DataCell(
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => _activar(n),
                                  child: const Text('Activar'),
                                ),
                                TextButton(
                                  onPressed: () => _recordatorios(n),
                                  child: const Text('Recordatorios'),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cuentas para cobrar',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('agregar-cuenta'),
                    onPressed: _agregarCuenta,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar cuenta'),
                  ),
                ],
              ),
              const Text(
                'Las ven los dueños en el aviso de pago y en "Ya pagué".',
              ),
              const SizedBox(height: 8),
              if (datos.cuentas.isEmpty)
                const Text('Sin cuentas. Agrega al menos una.')
              else
                for (final c in datos.cuentas)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance),
                      title: Text('${c.banco} · ${c.tipo}'),
                      subtitle: Text('${c.numero}\n${c.titular}'),
                      trailing: IconButton(
                        tooltip: 'Borrar',
                        onPressed: () => _borrarCuenta(c),
                        icon: const Icon(Icons.delete_outline),
                      ),
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
  const _Datos(this.negocios, this.soporte, this.cuentas, this.resumen);

  final ResumenUso resumen;

  final List<NegocioAdmin> negocios;
  final List<MensajeSoporte> soporte;
  final List<CuentaPago> cuentas;
}

class _NuevaCuenta {
  const _NuevaCuenta(this.banco, this.tipo, this.numero, this.titular);

  final String banco;
  final String tipo;
  final String numero;
  final String titular;
}

class _CuentaDialog extends StatefulWidget {
  const _CuentaDialog();

  @override
  State<_CuentaDialog> createState() => _CuentaDialogState();
}

class _CuentaDialogState extends State<_CuentaDialog> {
  final _form = GlobalKey<FormState>();
  final _banco = TextEditingController();
  final _numero = TextEditingController();
  final _titular = TextEditingController();
  String _tipo = 'Corriente';

  @override
  void dispose() {
    _banco.dispose();
    _numero.dispose();
    _titular.dispose();
    super.dispose();
  }

  String? _requerido(String? v) =>
      (v?.trim().length ?? 0) < 2 ? 'Obligatorio.' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar cuenta'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('cuenta-banco'),
              controller: _banco,
              decoration: const InputDecoration(labelText: 'Banco'),
              validator: _requerido,
            ),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'Corriente', child: Text('Corriente')),
                DropdownMenuItem(value: 'Ahorros', child: Text('Ahorros')),
              ],
              onChanged: (v) => setState(() => _tipo = v ?? _tipo),
            ),
            TextFormField(
              key: const Key('cuenta-numero'),
              controller: _numero,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Número de cuenta'),
              validator: (v) =>
                  RegExp(r'^[0-9-]{4,30}$').hasMatch(v?.trim() ?? '')
                  ? null
                  : 'Solo números y guiones.',
            ),
            TextFormField(
              key: const Key('cuenta-titular'),
              controller: _titular,
              decoration: const InputDecoration(labelText: 'A nombre de'),
              validator: _requerido,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('cuenta-guardar'),
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _NuevaCuenta(
                _banco.text.trim(),
                _tipo,
                _numero.text.trim(),
                _titular.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// 'No' o 'Sí · 12/300 (2 extra) · RD$300 + RD$2'.
String textoRecordatoriosAdmin(NegocioAdmin n) {
  if (!n.recordatoriosAuto) {
    return n.whatsappMes > 0 ? 'No (${n.whatsappMes} este mes)' : 'No';
  }
  final extra = n.whatsappExtra > 0 ? ' (${n.whatsappExtra} extra)' : '';
  return 'Sí · ${n.whatsappMes}/${n.whatsappCupo}$extra · '
      'RD\$${_monto(n.whatsappPrecioMensual)} + '
      'RD\$${_monto(n.whatsappPrecioExtra)}';
}

String _monto(num valor) =>
    valor == valor.roundToDouble() ? valor.round().toString() : '$valor';

typedef _Recordatorios = ({
  bool activo,
  int cupo,
  num precioMensual,
  num precioExtra,
});

class _RecordatoriosDialog extends StatefulWidget {
  const _RecordatoriosDialog({required this.negocio});

  final NegocioAdmin negocio;

  @override
  State<_RecordatoriosDialog> createState() => _RecordatoriosDialogState();
}

class _RecordatoriosDialogState extends State<_RecordatoriosDialog> {
  final _form = GlobalKey<FormState>();
  late bool _activo = widget.negocio.recordatoriosAuto;
  late final _cupo = TextEditingController(
    text: '${widget.negocio.whatsappCupo}',
  );
  late final _mensual = TextEditingController(
    text: _monto(widget.negocio.whatsappPrecioMensual),
  );
  late final _extra = TextEditingController(
    text: _monto(widget.negocio.whatsappPrecioExtra),
  );

  @override
  void dispose() {
    _cupo.dispose();
    _mensual.dispose();
    _extra.dispose();
    super.dispose();
  }

  static String? _validar(String? v, {bool entero = false}) {
    final n = entero ? int.tryParse(v?.trim() ?? '') : num.tryParse(v ?? '');
    return n == null || n < 0 ? 'Escribe 0 o más.' : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Recordatorios de ${widget.negocio.nombre}'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              key: const Key('admin-recordatorios-activo'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Envío automático contratado'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
            TextFormField(
              key: const Key('admin-recordatorios-cupo'),
              controller: _cupo,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Mensajes incluidos al mes',
              ),
              validator: (v) => _validar(v, entero: true),
            ),
            TextFormField(
              key: const Key('admin-recordatorios-mensual'),
              controller: _mensual,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Precio al mes (RD\$)',
              ),
              validator: _validar,
            ),
            TextFormField(
              key: const Key('admin-recordatorios-extra'),
              controller: _extra,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Precio por mensaje extra (RD\$)',
              ),
              validator: _validar,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop<_Recordatorios>(context, (
              activo: _activo,
              cupo: int.parse(_cupo.text.trim()),
              precioMensual: num.parse(_mensual.text.trim()),
              precioExtra: num.parse(_extra.text.trim()),
            ));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
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

/// Fichas con los totales de la plataforma.
class _ResumenUso extends StatelessWidget {
  const _ResumenUso({required this.resumen});

  final ResumenUso resumen;

  @override
  Widget build(BuildContext context) {
    final fichas = [
      ('Negocios', resumen.negocios, '${resumen.nuevos30d} nuevos en 30 días'),
      ('Activos', resumen.activos7d, 'con citas en 7 días'),
      ('Pagando', resumen.pagando, '${resumen.enPrueba} en prueba'),
      ('Pausados', resumen.pausados, 'vencidos o suspendidos'),
      (
        'Citas 30 días',
        resumen.citas30d,
        '${resumen.citasEnLinea30d} en línea',
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (titulo, valor, detalle) in fichas)
          SizedBox(
            width: 180,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      '$valor',
                      key: Key('uso-$titulo'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      detalle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
