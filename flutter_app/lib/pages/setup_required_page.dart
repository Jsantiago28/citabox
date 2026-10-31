import 'package:flutter/material.dart';

import '../widgets/logo_marca.dart';

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconoCitabox(tamano: 48),
                const SizedBox(height: 20),
                Text(
                  'Citabox',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Configura SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY para iniciar la aplicación.',
                ),
                const SizedBox(height: 16),
                const SelectableText(
                  'flutter run -d edge --dart-define-from-file=dart_defines.local.json',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
