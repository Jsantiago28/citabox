import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/registro_negocio.dart';
import '../services/clientes_repository.dart';
import '../services/registro_repository.dart';
import 'clientes_page.dart';
import 'registro_page.dart';

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
        .select('negocio_id, nombre, rol, activo, negocios(id, nombre)')
        .eq('id', widget.userId)
        .maybeSingle();
    return result;
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
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
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ProfileMessage(
              message: 'No se pudo cargar el perfil del negocio.',
              onRetry: () => setState(() => _profile = _loadProfile()),
            );
          }

          final profile = snapshot.data;
          if (profile == null) {
            final client = Supabase.instance.client;
            return RegistroPage.completar(
              repository: SupabaseRegistroRepository(client),
              pendiente: RegistroNegocio.fromMetadata(
                client.auth.currentUser?.userMetadata,
              ),
              onNegocioCreado: () => setState(() => _profile = _loadProfile()),
            );
          }

          if (profile['activo'] != true) {
            return const _ProfileMessage(
              message: 'El perfil de esta cuenta está inactivo.',
            );
          }

          final business = profile['negocios'] as Map<String, dynamic>?;
          final negocioId = profile['negocio_id']?.toString();
          if (negocioId == null || negocioId.isEmpty) {
            return const _ProfileMessage(
              message: 'Esta cuenta no tiene un negocio asociado.',
            );
          }

          return _BusinessWorkspace(
            negocioId: negocioId,
            negocioNombre: business?['nombre']?.toString() ?? 'Barbería PRO',
            profile: profile,
            email: widget.email,
          );
        },
      ),
    );
  }
}

class _BusinessWorkspace extends StatefulWidget {
  const _BusinessWorkspace({
    required this.negocioId,
    required this.negocioNombre,
    required this.profile,
    required this.email,
  });

  final String negocioId;
  final String negocioNombre;
  final Map<String, dynamic> profile;
  final String email;

  @override
  State<_BusinessWorkspace> createState() => _BusinessWorkspaceState();
}

class _BusinessWorkspaceState extends State<_BusinessWorkspace> {
  static const _destinations = [
    _WorkspaceDestination('Inicio', Icons.home_outlined, Icons.home),
    _WorkspaceDestination('Clientes', Icons.people_outline, Icons.people),
  ];

  int _selectedIndex = 0;

  Widget _page() {
    if (_selectedIndex == 1) {
      return ClientesPage(
        negocioId: widget.negocioId,
        repository: SupabaseClientesRepository(Supabase.instance.client),
      );
    }

    return _DashboardOverview(
      negocioNombre: widget.negocioNombre,
      nombre: widget.profile['nombre']?.toString() ?? widget.email,
      rol: widget.profile['rol']?.toString() ?? '—',
      onOpenClientes: () => setState(() => _selectedIndex = 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        final page = _page();

        if (isWide) {
          return Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: page),
            ],
          );
        }

        return Column(
          children: [
            Expanded(child: page),
            NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceDestination {
  const _WorkspaceDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({
    required this.negocioNombre,
    required this.nombre,
    required this.rol,
    required this.onOpenClientes,
  });

  final String negocioNombre;
  final String nombre;
  final String rol;
  final VoidCallback onOpenClientes;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola, $nombre',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(negocioNombre),
              const SizedBox(height: 4),
              Chip(avatar: const Icon(Icons.badge_outlined), label: Text(rol)),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.people_outline),
                  ),
                  title: const Text('Clientes'),
                  subtitle: const Text(
                    'Consulta y administra la ficha de tus clientes.',
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: onOpenClientes,
                ),
              ),
            ],
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
