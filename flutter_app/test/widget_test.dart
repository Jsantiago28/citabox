// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/app.dart';
import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/models/cliente.dart';
import 'package:barberiapro/pages/clientes_page.dart';
import 'package:barberiapro/pages/login_page.dart';
import 'package:barberiapro/services/clientes_repository.dart';
import 'package:barberiapro/utils/whatsapp.dart';

void main() {
  testWidgets('shows setup instructions when Supabase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(const BarberiaApp(supabaseConfigured: false));

    expect(find.text('Barbería PRO'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });

  testWidgets('login form validates email and password', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
  });

  testWidgets('login accepts a valid email', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.enterText(
      find.byType(TextFormField).first,
      'owner@example.com',
    );
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa un correo válido.'), findsNothing);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
  });

  testWidgets('clients can be searched by name', (tester) async {
    final repository = _FakeClientesRepository([
      const Cliente(id: 'c1', nombre: 'Juan Pérez'),
      const Cliente(id: 'c2', nombre: 'María Santos'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientesPage(negocioId: 'business-1', repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'maría');
    await tester.pumpAndSettle();

    expect(find.text('María Santos'), findsOneWidget);
    expect(find.text('Juan Pérez'), findsNothing);
    expect(repository.lastBusinessId, 'business-1');
  });

  testWidgets('clients show visits, spending and frequent badge', (
    tester,
  ) async {
    final repository = _FakeClientesRepository(
      [
        const Cliente(id: 'c1', nombre: 'Juan Pérez', telefono: '809-555-1234'),
        const Cliente(id: 'c2', nombre: 'Laura Méndez'),
      ],
      {
        'c1': const ResumenCliente(visitas: 18, gastado: 9400),
        'c2': const ResumenCliente(visitas: 1, gastado: 500),
      },
    );

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientesPage(negocioId: 'business-1', repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('18 visitas'), findsOneWidget);
    expect(find.text(r'RD$9,400'), findsOneWidget);
    expect(find.text('1 visita'), findsOneWidget);
    expect(find.text('Frecuente'), findsOneWidget);
  });

  testWidgets('new client is saved to the active business', (tester) async {
    final repository = _FakeClientesRepository([]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientesPage(negocioId: 'business-2', repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cliente-nombre')),
      'Ana López',
    );
    await tester.tap(find.text('Crear cliente'));
    await tester.pumpAndSettle();

    expect(find.text('Ana López'), findsOneWidget);
    expect(repository.lastSavedBusinessId, 'business-2');
  });

  group('ficha del cliente', () {
    Cita cita(
      String id,
      String fecha,
      EstadoCita estado, {
      num precio = 500,
      String servicio = 'Corte',
      String barbero = 'Carlos',
      String notas = '',
    }) => Cita(
      id: id,
      fecha: fecha,
      horaInicio: '10:00:00',
      precio: precio,
      estado: estado,
      clienteId: 'c1',
      servicioId: servicio,
      servicioNombre: servicio,
      empleadoId: barbero,
      empleadoNombre: barbero,
      notas: notas,
    );

    _FakeClientesRepository repositorio() => _FakeClientesRepository(
      [
        const Cliente(
          id: 'c1',
          nombre: 'Juan Pérez',
          telefono: '809-555-1234',
          email: 'juan@example.com',
          notas: 'fade 1.5, sin navaja',
        ),
        const Cliente(id: 'c2', nombre: 'Laura Méndez'),
      ],
      {'c1': const ResumenCliente(visitas: 2, gastado: 1300, faltas: 2)},
      {
        'c1': [
          cita('a', '2026-01-10', EstadoCita.completada, notas: 'Con barba'),
          cita(
            'b',
            '2026-02-10',
            EstadoCita.llego,
            precio: 800,
            servicio: 'Corte y barba',
            barbero: 'Pedro',
          ),
          cita('c', '2026-03-10', EstadoCita.noVino),
          cita('d', '2026-04-10', EstadoCita.noVino),
          cita('e', '2026-05-10', EstadoCita.cancelada),
          cita('f', '2099-01-05', EstadoCita.confirmada),
          for (var i = 1; i <= 8; i++)
            cita('x$i', '2025-0$i-01', EstadoCita.cancelada),
        ],
      },
    );

    Future<void> abrirFicha(
      WidgetTester tester,
      _FakeClientesRepository repository, {
      List<Uri>? enlaces,
    }) async {
      tester.view.physicalSize = const Size(1300, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientesPage(
              negocioId: 'business-1',
              repository: repository,
              abrirEnlace: (uri) async {
                enlaces?.add(uri);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Juan Pérez'));
      await tester.pumpAndSettle();
    }

    testWidgets('la lista marca a los clientes con faltas', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientesPage(
              negocioId: 'business-1',
              repository: repositorio(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Faltas'), findsOneWidget);
    });

    testWidgets('muestra indicadores, aviso, favoritos e historial', (
      tester,
    ) async {
      await abrirFicha(tester, repositorio());

      expect(find.byTooltip('Volver a clientes'), findsOneWidget);
      expect(find.text('juan@example.com'), findsOneWidget);
      expect(find.text('Cliente con faltas: pide apartado'), findsOneWidget);
      expect(find.text('Faltas'), findsOneWidget);
      expect(find.text(r'RD$1,300'), findsOneWidget);
      expect(find.text(r'RD$650'), findsOneWidget);
      expect(find.text('10/2/2026'), findsOneWidget);
      expect(find.text('5/1/2099 · 10:00 AM'), findsOneWidget);
      expect(find.text('fade 1.5, sin navaja'), findsOneWidget);
      expect(find.text('Corte y barba'), findsOneWidget);
      expect(find.text('Pedro'), findsOneWidget);
      expect(find.text('Historial de citas (14)'), findsOneWidget);

      // Más recientes primero y de 10 en 10.
      final primera = tester.getTopLeft(find.text('5/1/2099 · Corte')).dy;
      final segunda = tester.getTopLeft(find.text('10/5/2026 · Corte')).dy;
      expect(primera, lessThan(segunda));
      expect(find.text('Con barba'), findsOneWidget);
      expect(find.text('1/1/2025 · Corte'), findsNothing);
      await tester.tap(find.text('Ver más (4)'));
      await tester.pumpAndSettle();
      expect(find.text('1/1/2025 · Corte'), findsOneWidget);

      await tester.tap(find.byTooltip('Volver a clientes'));
      await tester.pumpAndSettle();
      expect(find.text('Laura Méndez'), findsOneWidget);
    });

    testWidgets('llamar y WhatsApp abren los enlaces del teléfono', (
      tester,
    ) async {
      final enlaces = <Uri>[];
      await abrirFicha(tester, repositorio(), enlaces: enlaces);

      await tester.tap(find.text('Llamar'));
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();

      // WhatsApp usa el mismo enlace que la agenda (utils/whatsapp.dart).
      expect(enlaces, [
        Uri.parse('tel:8095551234'),
        Uri.parse(enlaceWhatsApp('809-555-1234', 'Hola Juan')),
      ]);
      expect(
        enlaces.last.toString(),
        'https://wa.me/18095551234?text=Hola%20Juan',
      );
    });

    testWidgets('las notas se editan desde la ficha', (tester) async {
      final repository = repositorio();
      await abrirFicha(tester, repository);

      await tester.tap(find.text('Editar notas'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cliente-ficha-notas')),
        'fade 2\nsin navaja',
      );
      await tester.tap(find.text('Guardar notas'));
      await tester.pumpAndSettle();

      expect(repository.lastSavedDatos, {'notas': 'fade 2\nsin navaja'});
      expect(find.text('fade 2\nsin navaja'), findsOneWidget);
      expect(repository.clientes.first.telefono, '809-555-1234');
    });
  });
}

class _FakeClientesRepository implements ClientesRepository {
  _FakeClientesRepository(
    this.clientes, [
    this.resumenes = const {},
    this.citas = const {},
  ]);

  final List<Cliente> clientes;
  String? lastBusinessId;
  String? lastSavedBusinessId;
  Map<String, Object?>? lastSavedDatos;
  final Map<String, ResumenCliente> resumenes;
  final Map<String, List<Cita>> citas;

  @override
  Future<Map<String, ResumenCliente>> resumen(String negocioId) async =>
      resumenes;

  @override
  Future<List<Cita>> historial({
    required String negocioId,
    required String clienteId,
  }) async {
    lastBusinessId = negocioId;
    return List<Cita>.of(citas[clienteId] ?? const []);
  }

  @override
  Future<List<Cliente>> listar(String negocioId) async {
    lastBusinessId = negocioId;
    return List<Cliente>.of(clientes);
  }

  @override
  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? clienteId,
  }) async {
    lastSavedBusinessId = negocioId;
    lastSavedDatos = datos;
    // Como en Supabase, una actualización solo cambia las columnas enviadas.
    final index = clienteId == null
        ? -1
        : clientes.indexWhere((item) => item.id == clienteId);
    final actual = index < 0 ? null : clientes[index];
    String campo(String clave, String? anterior) => datos.containsKey(clave)
        ? (datos[clave]?.toString() ?? '')
        : (anterior ?? '');
    final cliente = Cliente(
      id: clienteId ?? 'new-client',
      nombre: campo('nombre', actual?.nombre),
      telefono: campo('telefono', actual?.telefono),
      email: campo('email', actual?.email),
      notas: campo('notas', actual?.notas),
      activo: actual?.activo ?? true,
    );
    if (index < 0) {
      clientes.add(cliente);
    } else {
      clientes[index] = cliente;
    }
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String clienteId,
    required bool activo,
  }) async {
    lastBusinessId = negocioId;
    final index = clientes.indexWhere((item) => item.id == clienteId);
    clientes[index] = Cliente(
      id: clientes[index].id,
      nombre: clientes[index].nombre,
      telefono: clientes[index].telefono,
      email: clientes[index].email,
      notas: clientes[index].notas,
      activo: activo,
    );
  }
}
