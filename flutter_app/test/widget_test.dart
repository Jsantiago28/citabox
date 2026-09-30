// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/app.dart';
import 'package:barberiapro/models/cliente.dart';
import 'package:barberiapro/pages/clientes_page.dart';
import 'package:barberiapro/pages/login_page.dart';
import 'package:barberiapro/services/clientes_repository.dart';

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
}

class _FakeClientesRepository implements ClientesRepository {
  _FakeClientesRepository(this.clientes);

  final List<Cliente> clientes;
  String? lastBusinessId;
  String? lastSavedBusinessId;

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
    final cliente = Cliente(
      id: clienteId ?? 'new-client',
      nombre: datos['nombre']?.toString() ?? '',
      telefono: datos['telefono']?.toString() ?? '',
      email: datos['email']?.toString() ?? '',
      notas: datos['notas']?.toString() ?? '',
    );
    if (clienteId == null) {
      clientes.add(cliente);
    } else {
      clientes[clientes.indexWhere((item) => item.id == clienteId)] = cliente;
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
