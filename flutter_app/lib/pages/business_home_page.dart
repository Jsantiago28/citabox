import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/registro_negocio.dart';
import '../services/apartados_repository.dart';
import '../services/avisos_en_vivo.dart';
import '../services/citas_repository.dart';
import '../services/clientes_repository.dart';
import '../services/configuracion_repository.dart';
import '../services/empleados_repository.dart';
import '../services/registro_repository.dart';
import '../services/primer_uso_repository.dart';
import '../services/reportes_repository.dart';
import '../services/plataforma_repository.dart';
import '../services/servicios_repository.dart';
import '../theme.dart';
import '../utils/formato.dart';
import '../utils/fotos.dart';
import '../utils/vocabulario.dart';
import '../widgets/logo_marca.dart';
import '../widgets/reportar_problema_dialog.dart';
import '../widgets/ya_pague_dialog.dart';
import 'agenda_page.dart';
import 'apartados_page.dart';
import 'clientes_page.dart';
import 'configuracion_page.dart';
import 'dashboard_page.dart';
import 'empleados_page.dart';
import 'registro_page.dart';
import 'reportes_page.dart';
import 'servicios_page.dart';

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
        .select(
          'negocio_id, nombre, rol, activo, negocios(id, nombre, moneda, tipo)',
        )
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
        title: const Text('Citabox'),
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
              onRetry: () => setState(() {
                _profile = _loadProfile();
              }),
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
              onNegocioCreado: () => setState(() {
                _profile = _loadProfile();
              }),
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
          negocioNombre: business?['nombre']?.toString() ?? 'Citabox',
          moneda: business?['moneda']?.toString() ?? 'DOP',
          tipo: TipoNegocio.desdeCodigo(business?['tipo']),
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
  apartados('Apartados', Icons.payments_outlined),
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
    this.tipo = TipoNegocio.barberia,
    required this.nombre,
    required this.esOwner,
    required this.onSignOut,
    this.citasRepository,
    this.clientesRepository,
    this.reportesRepository,
    this.apartadosRepository,
    this.suscripcionRepository,
    this.soporteRepository,
    this.avisosEnVivo,
  });

  final String userId;
  final String negocioId;
  final String negocioNombre;
  final String moneda;

  /// Tipo de negocio: decide las palabras de la app (barbero, estilista…).
  final TipoNegocio tipo;
  final String nombre;
  final bool esOwner;
  final VoidCallback onSignOut;

  /// Inyectables en pruebas; por defecto usan Supabase.
  final CitasRepository? citasRepository;
  final ClientesRepository? clientesRepository;
  final ReportesRepository? reportesRepository;
  final ApartadosRepository? apartadosRepository;
  final SuscripcionRepository? suscripcionRepository;
  final SoporteRepository? soporteRepository;

  /// Avisos en vivo; por defecto Supabase Realtime (null si no está iniciado).
  final AvisosEnVivo? avisosEnVivo;

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
  late final ApartadosRepository _apartados =
      widget.apartadosRepository ??
      SupabaseApartadosRepository(Supabase.instance.client);
  late Future<String?> _empleadoId;

  /// Checklist de primeros pasos; null si Supabase no está iniciado (pruebas).
  late final PrimerUsoRepository? _primerUso = () {
    try {
      return SupabasePrimerUsoRepository(Supabase.instance.client);
    } catch (_) {
      return null;
    }
  }();
  late Future<AvisoSuscripcion?> _aviso;
  _Seccion _seccion = _Seccion.inicio;

  late final AvisosEnVivo? _enVivo = widget.avisosEnVivo ?? _avisosPorDefecto();
  StreamSubscription<AvisoEnVivo>? _suscripcionAvisos;

  /// Avisos de agenda no vistos (puntito del menú) y contador de recargas.
  int _sinVer = 0;
  int _recarga = 0;

  AvisosEnVivo? _avisosPorDefecto() {
    try {
      return SupabaseAvisosEnVivo(
        Supabase.instance.client,
        negocioId: widget.negocioId,
        esOwner: widget.esOwner,
      );
    } catch (_) {
      return null;
    }
  }

  void _alLlegarAviso(AvisoEnVivo aviso) {
    if (!mounted) return;
    final paraApartados = aviso.tipo == TipoAviso.pagoReportado;
    final destino = paraApartados ? _Seccion.apartados : _Seccion.agenda;
    setState(() {
      _recarga++;
      if (!paraApartados && _seccion != _Seccion.agenda) _sinVer++;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(aviso.texto),
          action: SnackBarAction(label: 'Ver', onPressed: () => _ir(destino)),
        ),
      );
  }

  @override
  void dispose() {
    _suscripcionAvisos?.cancel();
    _enVivo?.cerrar();
    super.dispose();
  }

  /// Secciones que muestran solo lo del barbero y necesitan su empleado.
  bool get _necesitaEmpleado =>
      _seccion == _Seccion.inicio ||
      _seccion == _Seccion.agenda ||
      _seccion == _Seccion.apartados ||
      _seccion == _Seccion.reportes;

  List<_Seccion> get _secciones => widget.esOwner
      ? _Seccion.values
      : const [
          _Seccion.inicio,
          _Seccion.agenda,
          _Seccion.apartados,
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
    _empleadoId = _buscarEmpleado();
    _aviso = _buscarAviso();
    _suscripcionAvisos = _enVivo?.avisos.listen(_alLlegarAviso);
  }

  /// Aviso de suscripción (solo el dueño). Un fallo no estorba: sin aviso.
  Future<AvisoSuscripcion?> _buscarAviso() async {
    if (!widget.esOwner) return null;
    try {
      final repo =
          widget.suscripcionRepository ??
          SupabaseSuscripcionRepository(Supabase.instance.client);
      final s = await repo.obtener(widget.negocioId);
      return s == null ? null : avisoSuscripcion(s, DateTime.now());
    } catch (_) {
      return null;
    }
  }

  void _yaPague() {
    mostrarYaPague(
      context,
      soporte:
          widget.soporteRepository ??
          SupabaseSoporteRepository(Supabase.instance.client),
      negocioId: widget.negocioId,
      negocioNombre: widget.negocioNombre,
      cargarCuentas: SupabaseCuentasPagoRepository(Supabase.instance.client)
          .listar,
      subirRecibo: (foto) => subirFotoDelNegocio(
        Supabase.instance.client,
        negocioId: widget.negocioId,
        nombre: 'recibo',
        bytes: foto.bytes,
        tipo: foto.tipo,
      ),
    );
  }

  void _reportar() {
    mostrarReportarProblema(
      context,
      repository:
          widget.soporteRepository ??
          SupabaseSoporteRepository(Supabase.instance.client),
      negocioId: widget.negocioId,
      pantalla: _etiqueta(_seccion),
    );
  }

  // El dueño ve todo el negocio; el barbero solo sus citas.
  Future<String?> _buscarEmpleado() => widget.esOwner
      ? Future.value(null)
      : _citas.empleadoDelPerfil(
          negocioId: widget.negocioId,
          perfilId: widget.userId,
        );

  void _reintentarEmpleado() {
    setState(() {
      _empleadoId = _buscarEmpleado();
    });
  }

  void _ir(_Seccion seccion) => setState(() {
    _seccion = seccion;
    if (seccion == _Seccion.agenda) _sinVer = 0;
  });

  Widget _pagina(String? empleadoId, {bool falloEmpleado = false}) {
    // Un fallo de red no es lo mismo que un perfil sin vincular.
    if (!widget.esOwner && falloEmpleado && _necesitaEmpleado) {
      return _ProfileMessage(
        message: 'No se pudo cargar tu agenda.',
        onRetry: _reintentarEmpleado,
      );
    }
    if (!widget.esOwner && empleadoId == null && _necesitaEmpleado) {
      return const _ProfileMessage(
        message:
            'Tu perfil aún no está vinculado a un empleado. '
            'Pide al dueño del negocio que lo vincule para ver tu agenda.',
      );
    }

    return switch (_seccion) {
      _Seccion.inicio => DashboardPage(
        key: ValueKey('inicio-$empleadoId-$_recarga'),
        negocioId: widget.negocioId,
        negocioNombre: widget.negocioNombre,
        nombre: widget.nombre,
        moneda: widget.moneda,
        empleadoId: empleadoId,
        repository: _citas,
        onVerAgenda: () => _ir(_Seccion.agenda),
        apartadosRepository: _apartados,
        onVerApartados: () => _ir(_Seccion.apartados),
        mostrarPorBarbero: widget.esOwner,
        primerUsoRepository: widget.esOwner ? _primerUso : null,
        onIr: (paso) => _ir(switch (paso) {
          'servicios' => _Seccion.servicios,
          'barberos' => _Seccion.empleados,
          _ => _Seccion.configuracion,
        }),
      ),
      _Seccion.agenda => AgendaPage(
        key: ValueKey('agenda-$empleadoId-$_recarga'),
        negocioId: widget.negocioId,
        titulo: _etiqueta(_Seccion.agenda),
        negocioNombre: widget.negocioNombre,
        moneda: widget.moneda,
        empleadoId: empleadoId,
        esOwner: widget.esOwner,
        repository: _citas,
      ),
      _Seccion.apartados => ApartadosPage(
        key: ValueKey('apartados-$empleadoId-$_recarga'),
        negocioId: widget.negocioId,
        negocioNombre: widget.negocioNombre,
        moneda: widget.moneda,
        empleadoId: empleadoId,
        esOwner: widget.esOwner,
        repository: _apartados,
      ),
      _Seccion.clientes => ClientesPage(
        negocioId: widget.negocioId,
        moneda: widget.moneda,
        repository: _clientes,
      ),
      _Seccion.servicios => ServiciosPage(
        negocioId: widget.negocioId,
        moneda: widget.moneda,
        repository: SupabaseServiciosRepository(Supabase.instance.client),
      ),
      _Seccion.empleados => EmpleadosPage(
        negocioId: widget.negocioId,
        repository: SupabaseEmpleadosRepository(Supabase.instance.client),
        serviciosRepository: SupabaseServiciosRepository(
          Supabase.instance.client,
        ),
      ),
      _Seccion.reportes => ReportesPage(
        key: ValueKey('reportes-$empleadoId'),
        negocioId: widget.negocioId,
        moneda: widget.moneda,
        empleadoId: empleadoId,
        mostrarBarberos: widget.esOwner,
        repository: _reportes,
        negocioNombre: widget.negocioNombre,
      ),
      _Seccion.configuracion => ConfiguracionPage(
        negocioId: widget.negocioId,
        repository: SupabaseConfiguracionRepository(Supabase.instance.client),
        onTipoCambiado: (tipo) => setState(() => _tipo = tipo),
      ),
    };
  }

  /// Cambia al guardar el tipo en Configuración, sin recargar la app.
  late TipoNegocio _tipo = widget.tipo;

  @override
  Widget build(BuildContext context) {
    // También arriba del Navigator, para diálogos y pantallas apiladas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TipoNegocioHost.fijar(context, _tipo);
    });
    return Vocabulario(tipo: _tipo, child: _contenido(context));
  }

  Widget _contenido(BuildContext context) {
    return FutureBuilder<String?>(
      future: _empleadoId,
      builder: (context, snapshot) {
        final listo = snapshot.connectionState == ConnectionState.done;
        final pagina = listo
            ? _pagina(snapshot.data, falloEmpleado: snapshot.hasError)
            : const Center(child: CircularProgressIndicator());

        return LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth >= 860;
            final contenido = Column(
              children: [
                FutureBuilder<AvisoSuscripcion?>(
                  future: _aviso,
                  builder: (_, aviso) => aviso.data == null
                      ? const SizedBox.shrink()
                      : _BannerSuscripcion(
                          aviso: aviso.data!,
                          onYaPague: _yaPague,
                        ),
                ),
                Expanded(child: pagina),
              ],
            );
            final menu = _MenuLateral(
              secciones: _secciones,
              seleccionada: _seccion,
              etiqueta: _etiqueta,
              sinVerAgenda: _sinVer,
              nombre: widget.nombre,
              rol: widget.esOwner ? 'Dueño' : _tipo.profesional,
              onSeleccionar: (seccion) {
                if (!ancho) Navigator.of(context).pop();
                _ir(seccion);
              },
              onSignOut: widget.onSignOut,
              onReportar: () {
                if (!ancho) Navigator.of(context).pop();
                _reportar();
              },
            );

            if (ancho) {
              return Scaffold(
                body: Row(
                  children: [
                    menu,
                    Expanded(child: contenido),
                  ],
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                backgroundColor: Marca.negro,
                foregroundColor: Colors.white,
                title: const LogoCitabox(tamano: 18),
              ),
              drawer: Drawer(
                backgroundColor: Marca.lateral,
                width: 260,
                child: menu,
              ),
              body: contenido,
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
    required this.sinVerAgenda,
    required this.nombre,
    required this.rol,
    required this.onSeleccionar,
    required this.onSignOut,
    required this.onReportar,
  });

  final List<_Seccion> secciones;
  final _Seccion seleccionada;
  final String Function(_Seccion) etiqueta;
  final int sinVerAgenda;
  final String nombre;
  final String rol;
  final ValueChanged<_Seccion> onSeleccionar;
  final VoidCallback onSignOut;
  final VoidCallback onReportar;

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
              child: LogoCitabox(),
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
                      contador: seccion == _Seccion.agenda ? sinVerAgenda : 0,
                      onTap: () => onSeleccionar(seccion),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  _ItemMenu(
                    icono: Icons.support_agent_outlined,
                    etiqueta: 'Reportar un problema',
                    activo: false,
                    onTap: onReportar,
                  ),
                  _ItemMenu(
                    icono: Icons.logout,
                    etiqueta: 'Cerrar sesión',
                    activo: false,
                    onTap: onSignOut,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerSuscripcion extends StatelessWidget {
  const _BannerSuscripcion({required this.aviso, required this.onYaPague});

  final AvisoSuscripcion aviso;
  final VoidCallback onYaPague;

  @override
  Widget build(BuildContext context) {
    final color = aviso.urgente
        ? const Color(0xFFB3261E)
        : const Color(0xFF8A6D1F);
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            aviso.urgente ? Icons.warning_amber_rounded : Icons.info_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              aviso.texto,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('ya-pague'),
            onPressed: onYaPague,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Ya pagué'),
          ),
        ],
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
    this.contador = 0,
  });

  final int contador;
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
                Flexible(
                  child: Text(
                    etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: activo ? Colors.white : Colors.white70,
                      fontWeight: activo ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (contador > 0) ...[
                  const SizedBox(width: 8),
                  CircleAvatar(
                    key: const Key('contador-agenda'),
                    radius: 10,
                    backgroundColor: Marca.dorado,
                    child: Text(
                      '$contador',
                      style: const TextStyle(
                        color: Marca.negro,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
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
