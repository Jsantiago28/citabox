import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/registro_negocio.dart';
import '../services/citas_repository.dart';
import '../services/clientes_repository.dart';
import '../services/registro_repository.dart';
import '../services/reportes_repository.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../widgets/logo_barberia.dart';
import 'agenda_page.dart';
import 'clientes_page.dart';
import 'dashboard_page.dart';
import 'proximamente_page.dart';
import 'registro_page.dart';
import 'reportes_page.dart';

class BusinessHomePage extends StatefulWidget {
  const BusinessHomePage({
    super.key,
    required this.userId,
    required this.email,
  });

  final String userId;
  final String email;

  @override
  State<BusinessHomePage> createState() => _BusinessHomePageState();
}

class _BusinessHomePageState extends State<BusinessHomePage> {
  late Future<Map<String, dynamic>?> _profile;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  Future<Map<String, dynamic>?> _loadProfile() async {
    final result = await Supabase.instance.client
        .from('perfiles')
        .select('negocio_id, nombre, rol, activo, negocios(id, nombre, moneda)')
        .eq('id', widget.userId)
        .maybeSingle();
    return result;
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Widget _conBarra(Widget body) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barbería PRO'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _conBarra(const Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return _conBarra(
            _ProfileMessage(
              message: 'No se pudo cargar el perfil del negocio.',
              onRetry: () => setState(() => _profile = _loadProfile()),
            ),
          );
        }

        final profile = snapshot.data;
        if (profile == null) {
          final client = Supabase.instance.client;
          return _conBarra(
            RegistroPage.completar(
              repository: SupabaseRegistroRepository(client),
              pendiente: RegistroNegocio.fromMetadata(
                client.auth.currentUser?.userMetadata,
              ),
              onNegocioCreado: () => setState(() => _profile = _loadProfile()),
            ),
          );
        }

        if (profile['activo'] != true) {
          return _conBarra(
            const _ProfileMessage(
              message: 'El perfil de esta cuenta está inactivo.',
            ),
          );
        }

        final business = profile['negocios'] as Map<String, dynamic>?;
        final negocioId = profile['negocio_id']?.toString();
        if (negocioId == null || negocioId.isEmpty) {
          return _conBarra(
            const _ProfileMessage(
              message: 'Esta cuenta no tiene un negocio asociado.',
            ),
          );
        }

        return BusinessWorkspace(
          key: ValueKey(widget.userId),
          userId: widget.userId,
          negocioId: negocioId,
          negocioNombre: business?['nombre']?.toString() ?? 'Barbería PRO',
          moneda: business?['moneda']?.toString() ?? 'DOP',
          nombre: profile['nombre']?.toString() ?? widget.email,
          esOwner: profile['rol'] == 'OWNER',
          onSignOut: _signOut,
        );
      },
    );
  }
}

enum _Seccion {
  inicio('Inicio', Icons.home_outlined),
  agenda('Agenda', Icons.calendar_month_outlined),
  clientes('Clientes', Icons.people_outline),
  servicios('Servicios', Icons.content_cut),
  empleados('Empleados', Icons.badge_outlined),
  reportes('Reportes', Icons.insert_chart_outlined),
  configuracion('Configuración', Icons.settings_outlined);

  const _Seccion(this.etiqueta, this.icono);

  final String etiqueta;
  final IconData icono;
}

class BusinessWorkspace extends StatefulWidget {
  const BusinessWorkspace({
    super.key,
    required this.userId,
    required this.negocioId,
    required this.negocioNombre,
    required this.moneda,
    required this.nombre,
    required this.esOwner,
    required this.onSignOut,
    this.citasRepository,
    this.clientesRepository,
    this.reportesRepository,
  });

  final String userId;
  final String negocioId;
  final String negocioNombre;
  final String moneda;
  final String nombre;
  final bool esOwner;
  final VoidCallback onSignOut;

  /// Inyectables en pruebas; por defecto usan Supabase.
  final CitasRepository? citasRepository;
  final ClientesRepository? clientesRepository;
  final ReportesRepository? reportesRepository;

  @override
  State<BusinessWorkspace> createState() => _BusinessWorkspaceState();
}

class _BusinessWorkspaceState extends State<BusinessWorkspace> {
  late final CitasRepository _citas =
      widget.citasRepository ??
      SupabaseCitasRepository(Supabase.instance.client);
  late final ClientesRepository _clientes =
      widget.clientesRepository ??
      SupabaseClientesRepository(Supabase.instance.client);
  late final ReportesRepository _reportes =
      widget.reportesRepository ??
      SupabaseReportesRepository(Supabase.instance.client);
  late final Future<String?> _empleadoId;
  _Seccion _seccion = _Seccion.inicio;

  List<_Seccion> get _secciones => widget.esOwner
      ? _Seccion.values
      : const [
          _Seccion.inicio,
          _Seccion.agenda,
          _Seccion.clientes,
          _Seccion.reportes,
        ];

  String _etiqueta(_Seccion seccion) =>
      seccion == _Seccion.agenda && !widget.esOwner
      ? 'Mi agenda'
      : seccion.etiqueta;

  @override
  void initState() {
    super.initState();
    // El dueño ve todo el negocio; el barbero solo sus citas.
    _empleadoId = widget.esOwner
        ? Future.value(null)
        : _citas.empleadoDelPerfil(
            negocioId: widget.negocioId,
            perfilId: widget.userId,
          );
  }

  void _ir(_Seccion seccion) => setState(() => _seccion = seccion);

  Widget _pagina(String? empleadoId) {
    if (!widget.esOwner &&
        empleadoId == null &&
        (_seccion == _Seccion.inicio ||
            _seccion == _Seccion.agenda ||
            _seccion == _Seccion.reportes)) {
      return const _ProfileMessage(
        message:
            'Tu perfil aún no está vinculado a un empleado. '
            'Pide al dueño del negocio que lo vincule para ver tu agenda.',
      );
    }

    return switch (_seccion) {
      _Seccion.inicio => DashboardPage(
        key: ValueKey('inicio-$empleadoId'),
        negocioId: widget.negocioId,
        negocioNombre: widget.negocioNombre,
        nombre: widget.nombre,
        moneda: widget.moneda,
        empleadoId: empleadoId,
        repository: _citas,
        onVerAgenda: () => _ir(_Seccion.agenda),
      ),
      _Seccion.agenda => AgendaPage(
        key: ValueKey('agenda-$empleadoId'),
        negocioId: widget.negocioId,
        titulo: _etiqueta(_Seccion.agenda),
        moneda: widget.moneda,
        empleadoId: empleadoId,
        repository: _citas,
      ),
      _Seccion.clientes => ClientesPage(
        negocioId: widget.negocioId,
        moneda: widget.moneda,
        repository: _clientes,
      ),
      _Seccion.servicios => const ProximamentePage(
        titulo: 'Servicios',
        icono: Icons.content_cut,
        descripcion: 'Precios y duración de cada servicio de tu negocio.',
      ),
      _Seccion.empleados => const ProximamentePage(
        titulo: 'Empleados',
        icono: Icons.badge_outlined,
        descripcion: 'Tu equipo de barberos y sus horarios.',
      ),
      _Seccion.reportes => ReportesPage(
        key: ValueKey('reportes-$empleadoId'),
        negocioId: widget.negocioId,
        moneda: widget.moneda,
        empleadoId: empleadoId,
        mostrarBarberos: widget.esOwner,
        repository: _reportes,
      ),
      _Seccion.configuracion => const ProximamentePage(
        titulo: 'Configuración',
        icono: Icons.settings_outlined,
        descripcion: 'Datos del negocio, horarios y enlace de reservas.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _empleadoId,
      builder: (context, snapshot) {
        final listo = snapshot.connectionState == ConnectionState.done;
        final pagina = listo
            ? _pagina(snapshot.data)
            : const Center(child: CircularProgressIndicator());

        return LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth >= 860;
            final menu = _MenuLateral(
              secciones: _secciones,
              seleccionada: _seccion,
              etiqueta: _etiqueta,
              nombre: widget.nombre,
              rol: widget.esOwner ? 'Dueño' : 'Barbero',
              onSeleccionar: (seccion) {
                if (!ancho) Navigator.of(context).pop();
                _ir(seccion);
              },
              onSignOut: widget.onSignOut,
            );

            if (ancho) {
              return Scaffold(
                body: Row(
                  children: [
                    menu,
                    Expanded(child: pagina),
                  ],
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                backgroundColor: Marca.negro,
                foregroundColor: Colors.white,
                title: const LogoBarberia(tamano: 18),
              ),
              drawer: Drawer(
                backgroundColor: Marca.lateral,
                width: 260,
                child: menu,
              ),
              body: pagina,
            );
          },
        );
      },
    );
  }
}

class _MenuLateral extends StatelessWidget {
  const _MenuLateral({
    required this.secciones,
    required this.seleccionada,
    required this.etiqueta,
    required this.nombre,
    required this.rol,
    required this.onSeleccionar,
    required this.onSignOut,
  });

  final List<_Seccion> secciones;
  final _Seccion seleccionada;
  final String Function(_Seccion) etiqueta;
  final String nombre;
  final String rol;
  final ValueChanged<_Seccion> onSeleccionar;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: Marca.lateral,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: LogoBarberia(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Marca.dorado,
                    child: Text(
                      iniciales(nombre),
                      style: const TextStyle(
                        color: Marca.negro,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          rol,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final seccion in secciones)
                    _ItemMenu(
                      icono: seccion.icono,
                      etiqueta: etiqueta(seccion),
                      activo: seccion == seleccionada,
                      onTap: () => onSeleccionar(seccion),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _ItemMenu(
                icono: Icons.logout,
                etiqueta: 'Cerrar sesión',
                activo: false,
                onTap: onSignOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.icono,
    required this.etiqueta,
    required this.activo,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: activo ? Marca.lateralActivo : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icono,
                  size: 20,
                  color: activo ? Marca.doradoClaro : Colors.white70,
                ),
                const SizedBox(width: 12),
                Text(
                  etiqueta,
                  style: TextStyle(
                    color: activo ? Colors.white : Colors.white70,
                    fontWeight: activo ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
