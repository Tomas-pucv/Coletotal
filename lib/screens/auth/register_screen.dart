import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/garita.dart';
import 'package:taxi1/screens/auth/auth_widgets.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/auth_error_format.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Resultado de comprobar el código de garita mientras se escribe.
///
/// `sinConexion` es aparte de `invalido`: sin red no se sabe si el código
/// sirve, y antes se le decía al usuario que no servía.
enum _CodigoState { vacio, comprobando, valido, invalido, sinConexion }

/// Registro de colectiveros y administradores.
///
/// El rol no se elige libremente: lo concede el **código de garita**, que el
/// administrador entrega fuera de la app. El código se comprueba mientras se
/// escribe y muestra el nombre de la garita a la que da acceso, de modo que el
/// usuario sepa *antes* de enviar el formulario si su código sirve, en vez de
/// crear una cuenta y descubrirlo al final.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.initialRole = UserRole.colectivero});

  final UserRole initialRole;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _codigo = TextEditingController();

  late UserRole _role = widget.initialRole;
  bool _submitting = false;
  String? _error;

  Timer? _codigoDebounce;
  _CodigoState _codigoState = _CodigoState.vacio;
  Garita? _garita;

  /// Serializa las comprobaciones de código: si el usuario sigue escribiendo,
  /// la respuesta de una consulta anterior no debe pisar a la actual.
  int _codigoRequest = 0;

  bool get _isDriver => _role == UserRole.colectivero;

  @override
  void dispose() {
    _codigoDebounce?.cancel();
    _nombre.dispose();
    _identifier.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _codigo.dispose();
    super.dispose();
  }

  void _setRole(UserRole role) {
    if (role == _role) return;
    setState(() {
      _role = role;
      _identifier.clear();
      _error = null;
    });
    // Un código de chofer no sirve para registrarse como administrador, así que
    // al cambiar de rol hay que volver a comprobarlo.
    _checkCodigo(immediate: true);
  }

  void _onCodigoChanged(String _) => _checkCodigo();

  void _checkCodigo({bool immediate = false}) {
    _codigoDebounce?.cancel();
    final raw = _codigo.text.trim();

    if (raw.isEmpty) {
      setState(() {
        _codigoState = _CodigoState.vacio;
        _garita = null;
      });
      return;
    }

    setState(() => _codigoState = _CodigoState.comprobando);
    _codigoDebounce = Timer(
      Duration(milliseconds: immediate ? 0 : 500),
      () => _runCodigoLookup(raw),
    );
  }

  Future<void> _runCodigoLookup(String raw) async {
    final request = ++_codigoRequest;
    final auth = AuthService.instance;

    final CodigoAcceso? acceso;
    try {
      acceso = await auth.lookupCodigo(raw);
    } on AuthFailure {
      if (!mounted || request != _codigoRequest) return;
      setState(() {
        _codigoState = _CodigoState.sinConexion;
        _garita = null;
      });
      return;
    }
    final valido = acceso != null && acceso.rol == _role;
    final garita = valido ? await auth.getGarita(acceso.garitaId) : null;

    // Llegó tarde: ya hay una comprobación más nueva en curso.
    if (!mounted || request != _codigoRequest) return;

    setState(() {
      _codigoState = valido ? _CodigoState.valido : _CodigoState.invalido;
      _garita = garita;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final l10n = AppLocalizations.of(context)!;
    try {
      if (_isDriver) {
        await AuthService.instance.registerColectivero(
          nombre: _nombre.text,
          patente: _identifier.text,
          clave: _password.text,
          codigo: _codigo.text,
        );
      } else {
        await AuthService.instance.registerAdministrador(
          nombre: _nombre.text,
          email: _identifier.text,
          clave: _password.text,
          codigo: _codigo.text,
        );
      }
      if (!mounted) return;
      final nombre = AuthService.instance.profile?.displayName ?? '';
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.authWelcome(nombre))));
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = authErrorMessage(e.code, l10n, isDriver: _isDriver);
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = l10n.errAuthUnknown;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AuthScaffold(
      title: l10n.authRegisterTitle,
      children: [
        Text(l10n.authRoleQuestion, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        AuthRoleSelector(value: _role, onChanged: _setRole),
        const SizedBox(height: AppSpacing.xl),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.authName,
                  helperText: l10n.authNameHint,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? l10n.authRequired : null,
              ),
              const SizedBox(height: AppSpacing.md),

              if (_isDriver)
                PatenteField(
                  controller: _identifier,
                  textInputAction: TextInputAction.next,
                )
              else
                EmailField(
                  controller: _identifier,
                  textInputAction: TextInputAction.next,
                ),
              const SizedBox(height: AppSpacing.md),

              PasswordField(
                controller: _password,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final v = value ?? '';
                  if (v.isEmpty) return l10n.authRequired;
                  // Mínimo de Firebase Auth; validarlo acá evita un viaje a la
                  // red para recibir `weak-password`.
                  if (v.length < 6) return l10n.authPasswordShort;
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              PasswordField(
                controller: _passwordConfirm,
                label: l10n.authPasswordConfirm,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if ((value ?? '').isEmpty) return l10n.authRequired;
                  if (value != _password.text) return l10n.authPasswordMismatch;
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),

              _codigoField(l10n, scheme),
            ],
          ),
        ),

        if (_isDriver) ...[
          const SizedBox(height: AppSpacing.lg),
          InlineNotice(
            icon: Icons.key_outlined,
            message: l10n.authPasswordNote,
          ),
        ],

        if (_error case final error?) ...[
          const SizedBox(height: AppSpacing.lg),
          InlineNotice(
            icon: Icons.error_outline,
            message: error,
            tone: StatusTone.error,
          ),
        ],

        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.authSubmitRegister),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.authHasAccount),
        ),
      ],
    );
  }

  Widget _codigoField(AppLocalizations l10n, ColorScheme scheme) {
    // El sufijo es el que da la respuesta inmediata: reloj mientras consulta,
    // visto verde cuando el código sirve, aspa cuando no.
    final suffix = switch (_codigoState) {
      _CodigoState.vacio => null,
      _CodigoState.comprobando => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      _CodigoState.valido => Icon(Icons.check_circle, color: scheme.primary),
      _CodigoState.invalido => Icon(Icons.error_outline, color: scheme.error),
      _CodigoState.sinConexion => Icon(
        Icons.cloud_off,
        color: scheme.onSurfaceVariant,
      ),
    };

    final helper = switch (_codigoState) {
      _CodigoState.comprobando => l10n.authCodigoChecking,
      _CodigoState.valido => l10n.authCodigoValid(
        _garita?.nombre ?? l10n.navGarita,
      ),
      _CodigoState.invalido => l10n.authCodigoInvalid,
      _CodigoState.sinConexion => l10n.errAuthNetwork,
      _CodigoState.vacio => l10n.authCodigoHelp,
    };

    return TextFormField(
      controller: _codigo,
      onChanged: _onCodigoChanged,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submit(),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
        LengthLimitingTextInputFormatter(32),
      ],
      decoration: InputDecoration(
        labelText: l10n.authCodigo,
        prefixIcon: const Icon(Icons.vpn_key_outlined),
        suffixIcon: suffix,
        helperText: helper,
        helperMaxLines: 3,
        helperStyle: TextStyle(
          color: switch (_codigoState) {
            _CodigoState.valido => scheme.primary,
            _CodigoState.invalido => scheme.error,
            _ => scheme.onSurfaceVariant,
          },
        ),
      ),
      validator: (value) {
        if ((value ?? '').trim().isEmpty) return l10n.authRequired;
        // No se bloquea con `comprobando`: el registro vuelve a validar el
        // código contra Firestore antes de tocar Auth, así que como mucho se
        // recibe el mismo error un segundo más tarde.
        if (_codigoState == _CodigoState.invalido) return l10n.authCodigoInvalid;
        return null;
      },
    );
  }
}
