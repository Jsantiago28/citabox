import 'package:flutter/material.dart';

import '../services/historial.dart';
import '../services/historial_repository.dart';
import '../theme.dart';
import '../utils/formato.dart';

const _etiquetas = {
  'citas': 'Citas',
  'apartados': 'Apartados',
  'clientes': 'Clientes',
  'servicios': 'Servicios',
  'empleados': 'Empleados',
  'perfiles': 'Usuarios',
};

const _iconos = {
  'citas': Icons.event_outlined,
  'apartados': Icons.payments_outlined,
  'clientes': Icons.person_outline,
  'servicios': Icons.content_cut,
  'empleados': Icons.badge_outlined,
  'perfiles': Icons.manage_accounts_outlined,
};

/// Historial de cambios del negocio (solo el dueño): quién hizo qué y cuándo.
class HistorialPage extends StatefulWidget {
  const HistorialPage({
    super.key,
    required this.negocioId,
    required this.repository,
  });

  final String negocioId;
  final HistorialRepository repository;

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  final _registros = <RegistroAuditoria>[];
  final _empleados = <String, String>{};
  String? _tabla;
  DateTimeRange? _rango;
  int _pagina = 0;
  bool _hayMas = false;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar(reiniciar: true);
  }

  Future<void> _cargar({bool reiniciar = false}) async {
    if (reiniciar) {
      _pagina = 0;
      _registros.clear();
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    final tabla = _tabla, rango = _rango;
    try {
      final pagina = await widget.repository.listar(
        widget.negocioId,
        pagina: _pagina,
        tabla: tabla,
        desde: rango?.start,
        hasta: rango?.end,
      );
      if (!mounted || tabla != _tabla || rango != _rango) return;
      setState(() {
        _registros.addAll(pagina.registros);
        _empleados.addAll(pagina.empleados);
        _hayMas = pagina.hayMas;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el historial.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _elegirTabla(String? tabla) {
    _tabla = tabla;
    _cargar(reiniciar: true);
  }

  Future<void> _elegirFechas() async {
    final hoy = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(hoy.year - 3),
      lastDate: hoy,
      initialDateRange: _rango,
    );
    if (rango == null || !mounted) return;
    _rango = rango;
    _cargar(reiniciar: true);
  }

  void _quitarFechas() {
    _rango = null;
    _cargar(reiniciar: true);
  }

  String _cuando(DateTime f) {
    final h = f.hour.toString().padLeft(2, '0');
    final m = f.minute.toString().padLeft(2, '0');
    return '${f.day}/${f.month}/${f.year} ${formatoHora('$h:$m')}';
  }

  void _verDetalle(RegistroAuditoria r) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle del cambio'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                describirCambio(r, empleados: _empleados),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${r.quien} · ${_cuando(r.fecha)}',
                style: const TextStyle(color: Marca.textoSuave, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _bloque('Antes', r.antes),
              const SizedBox(height: 12),
              _bloque('Después', r.despues),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _bloque(String titulo, Map<String, dynamic>? datos) {
    final campos = datos?.entries
        .where((e) => e.key != 'updated_at' && e.key != 'created_at')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (campos == null || campos.isEmpty)
          const Text('—', style: TextStyle(color: Marca.textoSuave))
        else
          for (final e in campos)
            SelectableText(
              '${e.key}: ${e.value ?? '—'}',
              style: const TextStyle(fontSize: 12),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de cambios')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    key: const Key('historial-filtro-todo'),
                    label: const Text('Todo'),
                    selected: _tabla == null,
                    onSelected: (_) => _elegirTabla(null),
                  ),
                  for (final tabla in tablasAuditadas)
                    ChoiceChip(
                      key: Key('historial-filtro-$tabla'),
                      label: Text(_etiquetas[tabla]!),
                      selected: _tabla == tabla,
                      onSelected: (_) => _elegirTabla(tabla),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('historial-fechas'),
                    onPressed: _elegirFechas,
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      _rango == null
                          ? 'Todas las fechas'
                          : formatoRangoFechas(_rango!.start, _rango!.end),
                    ),
                  ),
                  if (_rango != null)
                    IconButton(
                      key: const Key('historial-quitar-fechas'),
                      tooltip: 'Quitar fechas',
                      onPressed: _quitarFechas,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Column(
                  children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => _cargar(),
                      child: const Text('Reintentar'),
                    ),
                  ],
                )
              else ...[
                if (!_cargando && _registros.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No hay cambios registrados.')),
                  ),
                for (final r in _registros) _fila(r),
                if (_cargando)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_hayMas)
                  Center(
                    child: OutlinedButton(
                      key: const Key('historial-mas'),
                      onPressed: () {
                        _pagina++;
                        _cargar();
                      },
                      child: const Text('Cargar más'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fila(RegistroAuditoria r) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Marca.negro,
          child: Icon(
            _iconos[r.tabla] ?? Icons.history,
            color: Marca.doradoClaro,
            size: 18,
          ),
        ),
        title: Text(describirCambio(r, empleados: _empleados)),
        subtitle: Text('${r.quien} · ${_cuando(r.fecha)}'),
        trailing: TextButton(
          onPressed: () => _verDetalle(r),
          child: const Text('Ver detalle'),
        ),
      ),
    );
  }
}
