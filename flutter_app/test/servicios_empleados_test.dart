import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/empleado.dart';
import 'package:barberiapro/models/servicio.dart';
import 'package:barberiapro/pages/empleados_page.dart';
import 'package:barberiapro/pages/servicios_page.dart';
import 'package:barberiapro/utils/fotos.dart';
import 'package:barberiapro/services/empleados_repository.dart';
import 'package:barberiapro/services/servicios_repository.dart';

Widget _app(Widget pagina) => MaterialApp(home: Scaffold(body: pagina));

void _pantallaAncha(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('Servicios', () {
    testWidgets('crea un servicio en el negocio activo', (tester) async {
      final repository = _FakeServiciosRepository([]);

      await tester.pumpWidget(
        _app(ServiciosPage(negocioId: 'negocio-1', repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Todavía no hay servicios'), findsOneWidget);

      await tester.tap(find.text('Nuevo servicio'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('servicio-nombre')),
        'Corte clásico',
      );
      await tester.enterText(find.byKey(const Key('servicio-precio')), '500');
      await tester.enterText(find.byKey(const Key('servicio-duracion')), '45');
      await tester.tap(find.text('Crear servicio'));
      await tester.pumpAndSettle();

      expect(find.text('Corte clásico'), findsOneWidget);
      expect(find.text(r'RD$500'), findsOneWidget);
      expect(repository.ultimoNegocioGuardado, 'negocio-1');
      expect(repository.ultimosDatos?['precio'], 500);
      expect(repository.ultimosDatos?['duracion_minutos'], 45);
      expect(repository.ultimosDatos?['activo'], true);
    });

    testWidgets('agrega servicios del catálogo con el precio del dueño', (
      tester,
    ) async {
      final repository = _FakeServiciosRepository([
        const Servicio(id: 's1', nombre: 'Lavado con rolos', precio: 400),
      ]);
      await tester.pumpWidget(
        _app(ServiciosPage(negocioId: 'negocio-1', repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('seleccionar-servicios')));
      await tester.pumpAndSettle();
      // "Lavado con rolos" ya existe: no se puede volver a agregar.
      // Por defecto se ve el catálogo de barbería.
      expect(
        find.byKey(const Key('sugerido-Corte de caballero')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sugerido-Planchado')), findsNothing);
      await tester.tap(find.byKey(const Key('sugerido-Corte + barba')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salón'));
      await tester.pumpAndSettle();
      expect(find.text('Ya está en tus servicios'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sugerido-Planchado')));
      await tester.pumpAndSettle();
      // Sin precio no se agrega.
      await tester.tap(find.byKey(const Key('agregar-seleccionados')));
      await tester.pumpAndSettle();
      expect(find.text('Escribe el precio'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('precio-Planchado')), '600');
      // Lo marcado en Barbería se conserva al cambiar de pestaña.
      expect(find.text('Agregar 2'), findsOneWidget);
      await tester.tap(find.text('Barbería'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('precio-Corte + barba')),
        '150',
      );
      await tester.tap(find.byKey(const Key('agregar-seleccionados')));
      await tester.pumpAndSettle();

      expect(repository.creadosEnLote.length, 2);
      final creado = repository.creadosEnLote.firstWhere(
        (c) => c['nombre'] == 'Planchado',
      );
      expect(creado['nombre'], 'Planchado');
      expect(creado['precio'], 600);
      expect(creado['duracion_minutos'], 45);
      expect(creado['icono'], 'plancha');
      expect(find.text('Planchado'), findsOneWidget);
    });

    testWidgets('crea un servicio con foto y la sube después de guardarlo', (
      tester,
    ) async {
      final repository = _FakeServiciosRepository([]);
      await tester.pumpWidget(
        _app(
          ServiciosPage(
            negocioId: 'negocio-1',
            repository: repository,
            elegirFoto: () async =>
                FotoElegida(Uint8List.fromList(_pngTransparente), 'image/png'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo servicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('servicio-subir-foto')));
      await tester.pumpAndSettle();
      expect(find.text('Cambiar foto'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('servicio-nombre')), 'Uñas');
      await tester.enterText(find.byKey(const Key('servicio-precio')), '800');
      await tester.tap(find.text('Crear servicio'));
      await tester.pumpAndSettle();

      expect(repository.fotosSubidas.single.$1, 'nuevo-0');
      expect(repository.fotosSubidas.single.$3, 'image/png');
      expect(repository.ultimosDatos!.containsKey('imagen_url'), isFalse);
    });

    testWidgets('quitar la foto la borra del servicio', (tester) async {
      final repository = _FakeServiciosRepository([
        const Servicio(
          id: 's1',
          nombre: 'Balayage',
          precio: 3000,
          imagenUrl: 'https://ejemplo.com/balayage.jpg',
        ),
      ]);
      await tester.pumpWidget(
        _app(ServiciosPage(negocioId: 'negocio-1', repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Balayage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('servicio-quitar-foto')));
      await tester.pumpAndSettle();
      expect(find.text('Subir foto'), findsOneWidget);
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(repository.ultimosDatos!['imagen_url'], isNull);
      expect(repository.ultimosDatos!.containsKey('imagen_url'), isTrue);
      expect(repository.fotosSubidas, isEmpty);
    });

    testWidgets('valida precio negativo y duración en cero', (tester) async {
      final repository = _FakeServiciosRepository([]);

      await tester.pumpWidget(
        _app(ServiciosPage(negocioId: 'negocio-1', repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo servicio'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crear servicio'));
      await tester.pumpAndSettle();
      expect(find.text('El nombre es obligatorio.'), findsOneWidget);
      expect(find.text('El precio es obligatorio.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('servicio-nombre')), 'Barba');
      await tester.enterText(find.byKey(const Key('servicio-precio')), '-5');
      await tester.enterText(find.byKey(const Key('servicio-duracion')), '0');
      await tester.tap(find.text('Crear servicio'));
      await tester.pumpAndSettle();

      expect(find.text('No puede ser negativo.'), findsOneWidget);
      expect(find.text('Debe ser mayor que 0.'), findsOneWidget);
      expect(repository.ultimoNegocioGuardado, isNull);
    });

    testWidgets('busca y desactiva servicios', (tester) async {
      final repository = _FakeServiciosRepository([
        const Servicio(id: 's1', nombre: 'Corte', precio: 500),
        const Servicio(id: 's2', nombre: 'Barba', precio: 300),
      ]);

      _pantallaAncha(tester);
      await tester.pumpWidget(
        _app(ServiciosPage(negocioId: 'negocio-1', repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'barb');
      await tester.pumpAndSettle();
      expect(find.text('Barba'), findsOneWidget);
      expect(find.text('Corte'), findsNothing);

      await tester.tap(find.byTooltip('Acciones de Barba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desactivar'));
      await tester.pumpAndSettle();

      expect(repository.servicios.last.activo, isFalse);
      expect(find.text('Inactivo'), findsOneWidget);
    });
  });

  group('Empleados', () {
    testWidgets('crea un empleado en el negocio activo', (tester) async {
      final repository = _FakeEmpleadosRepository([]);

      await tester.pumpWidget(
        _app(
          EmpleadosPage(
            negocioId: 'negocio-2',
            repository: repository,
            serviciosRepository: _FakeServiciosRepository([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo empleado'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crear empleado'));
      await tester.pumpAndSettle();
      expect(find.text('El nombre es obligatorio.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('empleado-nombre')),
        'Pedro Gómez',
      );
      await tester.enterText(
        find.byKey(const Key('empleado-telefono')),
        '809-555-0000',
      );
      await tester.tap(find.text('Crear empleado'));
      await tester.pumpAndSettle();

      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.text('Sin cuenta'), findsOneWidget);
      expect(repository.ultimoNegocio, 'negocio-2');
    });

    testWidgets('guarda la comisión del barbero y la muestra en su ficha', (
      tester,
    ) async {
      final repository = _FakeEmpleadosRepository([]);
      _pantallaAncha(tester);
      await tester.pumpWidget(
        _app(
          EmpleadosPage(
            negocioId: 'negocio-1',
            repository: repository,
            serviciosRepository: _FakeServiciosRepository([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nuevo empleado'));
      await tester.pumpAndSettle();
      expect(find.text('Comisión (%)'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('empleado-nombre')),
        'Luis Pérez',
      );

      await tester.enterText(find.byKey(const Key('empleado-comision')), '101');
      await tester.tap(find.text('Crear empleado'));
      await tester.pumpAndSettle();
      expect(find.textContaining('entre 0 y 100'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('empleado-comision')),
        '12.5',
      );
      await tester.tap(find.text('Crear empleado'));
      await tester.pumpAndSettle();
      expect(repository.empleados.single.comisionPct, 12.5);

      await tester.tap(find.text('Luis Pérez'));
      await tester.pumpAndSettle();
      expect(find.text('Comisión: 12.5%'), findsOneWidget);
    });

    testWidgets('asigna servicios a un empleado', (tester) async {
      final repository = _FakeEmpleadosRepository([
        const Empleado(id: 'e1', nombre: 'Pedro Gómez'),
      ]);
      final servicios = _FakeServiciosRepository([
        const Servicio(id: 's1', nombre: 'Corte', precio: 500),
        const Servicio(id: 's2', nombre: 'Barba', precio: 300),
      ]);

      _pantallaAncha(tester);
      await tester.pumpWidget(
        _app(
          EmpleadosPage(
            negocioId: 'negocio-1',
            repository: repository,
            serviciosRepository: servicios,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Gómez'));
      await tester.pumpAndSettle();

      // Sin filas = hace todos; sin horario propio = el del negocio.
      expect(find.text('Todos los servicios'), findsOneWidget);
      expect(find.text('Usa el horario del negocio'), findsOneWidget);

      await tester.tap(find.text('Elegir servicios'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('servicios-todos')));
      await tester.pumpAndSettle();

      // Sin elegir ninguno no se puede guardar.
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Elige al menos un servicio'), findsOneWidget);

      await tester.tap(find.text('Corte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repository.servicios['e1'], {'s1'});
      expect(find.text('Todos los servicios'), findsNothing);
      expect(find.widgetWithText(Chip, 'Corte'), findsOneWidget);
    });

    testWidgets('guarda un horario propio', (tester) async {
      final repository = _FakeEmpleadosRepository([
        const Empleado(id: 'e1', nombre: 'Pedro Gómez'),
      ]);

      _pantallaAncha(tester);
      await tester.pumpWidget(
        _app(
          EmpleadosPage(
            negocioId: 'negocio-1',
            repository: repository,
            serviciosRepository: _FakeServiciosRepository([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Gómez'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar horario'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('horario-negocio')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      // Propuesta por defecto: lunes a sábado de 9:00 AM a 6:00 PM.
      final horario = repository.horarios['e1']!;
      expect(horario.map((dia) => dia.diaSemana), [1, 2, 3, 4, 5, 6]);
      expect(horario.first.horaInicio, '09:00');
      expect(find.text('Usa el horario del negocio'), findsNothing);
      expect(find.text('Libre'), findsOneWidget);
    });

    testWidgets('agrega un día libre', (tester) async {
      final repository = _FakeEmpleadosRepository([
        const Empleado(id: 'e1', nombre: 'Pedro Gómez'),
      ]);

      _pantallaAncha(tester);
      await tester.pumpWidget(
        _app(
          EmpleadosPage(
            negocioId: 'negocio-1',
            repository: repository,
            serviciosRepository: _FakeServiciosRepository([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Gómez'));
      await tester.pumpAndSettle();
      expect(find.text('Sin días libres programados.'), findsOneWidget);

      await tester.tap(find.text('Agregar día libre'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('bloqueo-motivo')),
        'Vacaciones',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repository.bloqueosGuardados, hasLength(1));
      expect(find.text('Vacaciones'), findsOneWidget);
    });

    testWidgets('invita a la app y muestra errores de la invitación', (
      tester,
    ) async {
      final repository = _FakeEmpleadosRepository([
        const Empleado(id: 'e1', nombre: 'Pedro Gómez'),
      ]);

      _pantallaAncha(tester);
      await tester.pumpWidget(
        _app(
          EmpleadosPage(
            negocioId: 'negocio-1',
            repository: repository,
            serviciosRepository: _FakeServiciosRepository([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Gómez'));
      await tester.pumpAndSettle();

      // Error devuelto por la función.
      repository.errorInvitacion = 'Ese correo ya tiene una cuenta.';
      await tester.tap(find.text('Invitar a la app'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('invitar-email')), 'malo');
      await tester.tap(find.text('Enviar invitación'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresa un correo válido.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('invitar-email')),
        'pedro@example.com',
      );
      await tester.tap(find.text('Enviar invitación'));
      await tester.pumpAndSettle();
      expect(find.text('Ese correo ya tiene una cuenta.'), findsOneWidget);

      // Invitación correcta: la ficha queda ligada a una cuenta.
      repository.errorInvitacion = null;
      await tester.tap(find.text('Invitar a la app'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invitar-email')),
        'Pedro@Example.com',
      );
      await tester.tap(find.text('Enviar invitación'));
      await tester.pumpAndSettle();

      expect(repository.invitaciones, ['e1:pedro@example.com']);
      expect(find.text('Tiene cuenta'), findsOneWidget);
      expect(find.text('Invitar a la app'), findsNothing);
    });

    testWidgets('el detalle cabe en un celular', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _FakeEmpleadosRepository([
        const Empleado(
          id: 'e1',
          nombre: 'Pedro Gómez Rodríguez',
          telefono: '809-555-0000',
        ),
      ]);
      repository.horarios['e1'] = const [
        HorarioDia(diaSemana: 1, horaInicio: '09:00', horaFin: '18:00'),
      ];

      await tester.pumpWidget(
        _app(
          EmpleadosPage(
            negocioId: 'negocio-1',
            repository: repository,
            serviciosRepository: _FakeServiciosRepository([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Gómez Rodríguez'));
      await tester.pumpAndSettle();

      expect(find.text('Invitar a la app'), findsOneWidget);
      expect(find.text('9:00 AM – 6:00 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empleado con cuenta muestra "Tiene cuenta"', (tester) async {
      final repository = _FakeEmpleadosRepository([
        const Empleado(id: 'e1', nombre: 'Luis Peña', perfilId: 'p1'),
      ]);

      _pantallaAncha(tester);
      await tester.pumpWidget(
        _app(
          EmpleadosPage(
            negocioId: 'negocio-1',
            repository: repository,
            serviciosRepository: _FakeServiciosRepository([]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tiene cuenta'), findsOneWidget);

      await tester.tap(find.text('Luis Peña'));
      await tester.pumpAndSettle();
      expect(find.text('Tiene cuenta'), findsOneWidget);
      expect(find.text('Invitar a la app'), findsNothing);
    });
  });
}

class _FakeServiciosRepository implements ServiciosRepository {
  _FakeServiciosRepository(this.servicios);

  final List<Servicio> servicios;
  String? ultimoNegocioGuardado;
  Map<String, Object?>? ultimosDatos;

  @override
  Future<List<Servicio>> listar(String negocioId) async =>
      List<Servicio>.of(servicios);

  final fotosSubidas = <(String, int, String)>[];

  @override
  Future<void> subirFoto({
    required String negocioId,
    required String servicioId,
    required Uint8List bytes,
    required String tipo,
  }) async {
    fotosSubidas.add((servicioId, bytes.length, tipo));
  }

  @override
  Future<String> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? servicioId,
  }) async {
    ultimoNegocioGuardado = negocioId;
    ultimosDatos = datos;
    final id = servicioId ?? 'nuevo-${servicios.length}';
    final servicio = Servicio(
      id: id,
      nombre: datos['nombre']?.toString() ?? '',
      descripcion: datos['descripcion']?.toString() ?? '',
      precio: datos['precio'] as num,
      duracionMinutos: datos['duracion_minutos'] as int,
      activo: datos['activo'] as bool,
    );
    if (servicioId == null) {
      servicios.add(servicio);
    } else {
      servicios[servicios.indexWhere((item) => item.id == servicioId)] =
          servicio;
    }
    return id;
  }

  final creadosEnLote = <Map<String, Object?>>[];

  @override
  Future<void> crearVarios({
    required String negocioId,
    required List<Map<String, Object?>> servicios,
  }) async {
    creadosEnLote.addAll(servicios);
    for (final datos in servicios) {
      this.servicios.add(
        Servicio(
          id: 'lote-${this.servicios.length}',
          nombre: datos['nombre'].toString(),
          precio: datos['precio'] as num,
          duracionMinutos: datos['duracion_minutos'] as int,
          icono: datos['icono'] as String?,
        ),
      );
    }
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String servicioId,
    required bool activo,
  }) async {
    final index = servicios.indexWhere((item) => item.id == servicioId);
    final actual = servicios[index];
    servicios[index] = Servicio(
      id: actual.id,
      nombre: actual.nombre,
      descripcion: actual.descripcion,
      precio: actual.precio,
      duracionMinutos: actual.duracionMinutos,
      activo: activo,
    );
  }
}

class _FakeEmpleadosRepository implements EmpleadosRepository {
  _FakeEmpleadosRepository(this.empleados);

  final List<Empleado> empleados;
  final Map<String, Set<String>> servicios = {};
  final Map<String, List<HorarioDia>> horarios = {};
  final List<BloqueoEmpleado> bloqueosGuardados = [];
  final List<String> invitaciones = [];
  String? ultimoNegocio;
  String? errorInvitacion;

  @override
  Future<List<Empleado>> listar(String negocioId) async =>
      List<Empleado>.of(empleados);

  @override
  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? empleadoId,
  }) async {
    ultimoNegocio = negocioId;
    final empleado = Empleado(
      id: empleadoId ?? 'nuevo-${empleados.length}',
      nombre: datos['nombre']?.toString() ?? '',
      telefono: datos['telefono']?.toString() ?? '',
      activo: datos['activo'] as bool,
      comisionPct: datos['comision_pct'] as num? ?? 0,
    );
    if (empleadoId == null) {
      empleados.add(empleado);
    } else {
      empleados[empleados.indexWhere((item) => item.id == empleadoId)] =
          empleado;
    }
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String empleadoId,
    required bool activo,
  }) async {}

  @override
  Future<Set<String>> serviciosAsignados({
    required String negocioId,
    required String empleadoId,
  }) async => {...?servicios[empleadoId]};

  @override
  Future<void> guardarServicios({
    required String negocioId,
    required String empleadoId,
    required Set<String> servicioIds,
  }) async {
    servicios[empleadoId] = servicioIds;
  }

  @override
  Future<List<HorarioDia>> horario({
    required String negocioId,
    required String empleadoId,
  }) async => [...?horarios[empleadoId]];

  @override
  Future<void> guardarHorario({
    required String negocioId,
    required String empleadoId,
    required List<HorarioDia> dias,
  }) async {
    horarios[empleadoId] = dias;
  }

  @override
  Future<List<BloqueoEmpleado>> bloqueos({
    required String negocioId,
    required String empleadoId,
  }) async => List<BloqueoEmpleado>.of(bloqueosGuardados);

  @override
  Future<void> agregarBloqueo({
    required String negocioId,
    required String empleadoId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? motivo,
  }) async {
    bloqueosGuardados.add(
      BloqueoEmpleado(
        id: 'b${bloqueosGuardados.length}',
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        motivo: motivo ?? '',
      ),
    );
  }

  @override
  Future<void> eliminarBloqueo({
    required String negocioId,
    required String bloqueoId,
  }) async {
    bloqueosGuardados.removeWhere((bloqueo) => bloqueo.id == bloqueoId);
  }

  @override
  Future<void> invitar({
    required String empleadoId,
    required String email,
  }) async {
    if (errorInvitacion != null) throw InvitacionException(errorInvitacion!);
    invitaciones.add('$empleadoId:$email');
    final index = empleados.indexWhere((item) => item.id == empleadoId);
    final actual = empleados[index];
    empleados[index] = Empleado(
      id: actual.id,
      nombre: actual.nombre,
      telefono: actual.telefono,
      activo: actual.activo,
      perfilId: 'perfil-$empleadoId',
    );
  }
}

/// PNG de 1×1 transparente para las pruebas de foto.
const _pngTransparente = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
