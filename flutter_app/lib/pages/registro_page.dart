import 'package:flutter/material.dart';

import '../models/registro_negocio.dart';
import '../services/registro_repository.dart';
import '../theme.dart';
import '../utils/slug.dart';
import '../widgets/consentimiento_check.dart';
import '../widgets/logo_marca.dart';

class RegistroPage extends StatefulWidget {
  /// Registro completo: crea la cuenta y deja los datos del negocio
  /// pendientes en la cuenta hasta que haya sesión.
  const RegistroPage({super.key, required this.repository})
    : pendiente = null,
      onNegocioCreado = null;

  /// Cuenta ya autenticada sin perfil: solo pide los datos del negocio.
  /// Si hay datos pendientes del registro, los envía automáticamente.
  const RegistroPage.completar({
    super.key,
    required this.repository,
    required this.onNegocioCreado,
    this.pendiente,
  });

  final RegistroRepository repository;
  final RegistroNegocio? pendiente;
  final VoidCallback? onNegocioCreado;

  bool get _completando => onNegocioCreado != null;

  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  final _formKey = GlobalKey<FormState>();
  final _negocioNombre = TextEditingController();
  final _slug = TextEditingController();
  final _negocioTelefono = TextEditingController();
  final _ownerNombre = TextEditingController();
  final _ownerTelefono = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _codigo = TextEditingController();

  bool _slugEditadoManualmente = false;
  bool _enviando = false;
  bool _aceptaTerminos = false;
  bool _esperandoConfirmacion = false;
  String? _error;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    final pendiente = widget.pendiente;
    if (pendiente != null) {
      _negocioNombre.text = pendiente.negocioNombre;
      _slug.text = pendiente.slug;
      _negocioTelefono.text = pendiente.negocioTelefono;
      _ownerNombre.text = pendiente.ownerNombre;
      _ownerTelefono.text = pendiente.ownerTelefono;
      _slugEditadoManualmente = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _crearNegocio());
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _negocioNombre,
      _slug,
      _negocioTelefono,
      _ownerNombre,
      _ownerTelefono,
      _email,
      _password,
      _codigo,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  RegistroNegocio _datos() => RegistroNegocio(
    negocioNombre: _negocioNombre.text.trim(),
    slug: _slug.text.trim(),
    negocioTelefono: _negocioTelefono.text.trim(),
    ownerNombre: _ownerNombre.text.trim(),
    ownerTelefono: _ownerTelefono.text.trim(),
  );

  void _onNegocioNombreChanged(String value) {
    if (!_slugEditadoManualmente) setState(() => _slug.text = slugify(value));
  }

  void _onSlugChanged(String value) {
    _slugEditadoManualmente = true;
    final limpio = slugify(value);
    // Permite escribir el guion final mientras se teclea.
    final conGuion = value.endsWith('-') && limpio.isNotEmpty
        ? '$limpio-'
        : limpio;
    if (conGuion != value) {
      _slug.value = TextEditingValue(
        text: conGuion,
        selection: TextSelection.collapsed(offset: conGuion.length),
      );
    }
    setState(() {});
  }

  Future<void> _enviar() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    if (widget._completando) {
      await _crearNegocio();
    } else {
      await _crearCuenta();
    }
  }

  Future<void> _crearCuenta() async {
    setState(() => _enviando = true);
    try {
      final datos = _datos();
      if (await widget.repository.slugDisponible(datos.slug) == false) {
        throw const RegistroException('Ese slug ya está en uso. Elige otro.');
      }

      final conSesion = await widget.repository.crearCuenta(
        email: _email.text.trim(),
        password: _password.text,
        datos: datos,
      );
      if (!mounted) return;

      if (conSesion) {
        // AuthGate detecta la sesión y el panel completa el negocio con
        // los datos pendientes; un solo camino evita dobles llamadas.
        Navigator.of(context).pop();
      } else {
        setState(() => _esperandoConfirmacion = true);
      }
    } on RegistroException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo crear la cuenta. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _verificarCodigo() async {
    final codigo = _codigo.text.trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(codigo)) {
      setState(() {
        _aviso = null;
        _error = 'Escribe el código que te enviamos por correo.';
      });
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
      _aviso = null;
    });
    try {
      await widget.repository.verificarCodigo(
        email: _email.text.trim(),
        codigo: codigo,
      );
      // Con la sesión abierta, AuthGate muestra el panel y este completa
      // el negocio con los datos pendientes, igual que con sesión inmediata.
      if (mounted) Navigator.of(context).pop();
    } on RegistroException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo verificar el código. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _reenviarCodigo() async {
    setState(() {
      _enviando = true;
      _error = null;
      _aviso = null;
    });
    try {
      await widget.repository.reenviarCodigo(_email.text.trim());
      if (mounted) setState(() => _aviso = 'Te enviamos un código nuevo.');
    } on RegistroException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo reenviar el código. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _crearNegocio() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await widget.repository.crearNegocio(_datos());
      widget.onNegocioCreado?.call();
    } on RegistroException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo crear el negocio. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget._completando ? null : Marca.negro,
      appBar: widget._completando
          ? null
          : AppBar(
              backgroundColor: Marca.negro,
              foregroundColor: Colors.white,
              title: const LogoCitabox(tamano: 18),
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _esperandoConfirmacion
                      ? _confirmacion(context)
                      : _formulario(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _confirmacion(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.mark_email_read_outlined, size: 34),
        ),
        const SizedBox(height: 20),
        Text(
          'Revisa tu correo',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'Te enviamos un código de confirmación a ${_email.text.trim()}. '
          'Escríbelo aquí y tu negocio se creará automáticamente.',
        ),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
        ],
        if (_aviso != null) ...[Text(_aviso!), const SizedBox(height: 16)],
        TextField(
          key: const Key('registro-codigo'),
          controller: _codigo,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 10,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _enviando ? null : _verificarCodigo(),
          decoration: const InputDecoration(
            labelText: 'Código',
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        BotonDorado(
          onPressed: _enviando ? null : _verificarCodigo,
          etiqueta: _enviando ? 'Verificando…' : 'Confirmar',
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _enviando ? null : _reenviarCodigo,
          child: const Text('Reenviar código'),
        ),
      ],
    );
  }

  Widget _formulario(BuildContext context) {
    final completando = widget._completando;
    final slug = _slug.text.isEmpty ? 'tu-negocio' : _slug.text;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.storefront_outlined, size: 34),
          ),
          const SizedBox(height: 20),
          Text(
            completando ? 'Completa tu negocio' : 'Registra tu negocio',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            completando
                ? 'Tu cuenta ya está confirmada. Completa los datos del '
                      'negocio para terminar el registro.'
                : 'Crea tu cuenta de propietario.',
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('registro-negocio-nombre'),
            controller: _negocioNombre,
            textInputAction: TextInputAction.next,
            onChanged: _onNegocioNombreChanged,
            decoration: const InputDecoration(labelText: 'Nombre del negocio'),
            validator: (value) => (value?.trim() ?? '').isEmpty
                ? 'El nombre del negocio es obligatorio.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('registro-slug'),
            controller: _slug,
            textInputAction: TextInputAction.next,
            onChanged: _onSlugChanged,
            decoration: InputDecoration(
              labelText: 'Enlace público',
              helperText: 'reservar/$slug',
            ),
            validator: (value) => slugValido(value?.trim() ?? '')
                ? null
                : 'Usa minúsculas, números y guiones.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _negocioTelefono,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Teléfono del negocio',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('registro-owner-nombre'),
            controller: _ownerNombre,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Tu nombre'),
            validator: (value) => (value?.trim() ?? '').isEmpty
                ? 'Tu nombre es obligatorio.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _ownerTelefono,
            keyboardType: TextInputType.phone,
            textInputAction: completando
                ? TextInputAction.done
                : TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Tu teléfono'),
          ),
          if (!completando) ...[
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('registro-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Correo'),
              validator: (value) =>
                  RegExp(r'^\S+@\S+\.\S+$').hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Ingresa un correo válido.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('registro-password'),
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _enviar(),
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                helperText: 'Mínimo 8 caracteres.',
              ),
              validator: (value) => (value?.length ?? 0) < 8
                  ? 'La contraseña debe tener al menos 8 caracteres.'
                  : null,
            ),
          ],
          if (widget.pendiente == null) ...[
            const SizedBox(height: 12),
            ConsentimientoCheck(
              key: const Key('registro-consentimiento'),
              texto: 'Acepto los términos y la política de privacidad.',
              enlaces: const {
                'Ver términos': '/terminos',
                'Ver política de privacidad': '/privacidad',
              },
              valor: _aceptaTerminos,
              onChanged: (v) => setState(() => _aceptaTerminos = v),
              mensajeError: 'Debes aceptar los términos y la privacidad.',
            ),
          ],
          const SizedBox(height: 12),
          BotonDorado(
            onPressed: _enviando ? null : _enviar,
            etiqueta: _enviando ? 'Creando…' : 'Crear mi negocio',
          ),
        ],
      ),
    );
  }
}
