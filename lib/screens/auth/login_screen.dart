import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/screens/auth/auth_widgets.dart';
import 'package:taxi1/screens/auth/register_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/auth_error_format.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Inicio de sesión para colectiveros y administradores.
///
/// Un solo formulario que cambia su primer campo según el rol: **patente** para
/// el chofer (informe §7.3.1-A) y **correo** para el administrador. Por debajo
/// ambos son Firebase Auth con correo y contraseña; la patente se traduce a un
/// correo sintético en [AuthService].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialRole = UserRole.colectivero});

  final UserRole initialRole;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();

  late UserRole _role = widget.initialRole;
  int _conductor = 1;
  bool _submitting = false;
  String? _error;

  bool get _isDriver => _role == UserRole.colectivero;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  void _setRole(UserRole role) {
    if (role == _role) return;
    setState(() {
      _role = role;
      // El identificador de un rol no sirve en el otro (una patente no es un
      // correo), así que se limpia en vez de dejar basura en el campo.
      _identifier.clear();
      _error = null;
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
        await AuthService.instance.signInColectivero(
          patente: _identifier.text,
          clave: _password.text,
          conductor: _conductor,
        );
      } else {
        await AuthService.instance.signInAdministrador(
          email: _identifier.text,
          clave: _password.text,
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

    return AuthScaffold(
      title: l10n.authLoginTitle,
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
              if (_isDriver) ...[
                PatenteField(
                  controller: _identifier,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.sm),
                ConductorSlotSelector(
                  value: _conductor,
                  onChanged: (v) => setState(() => _conductor = v),
                ),
              ]
              else
                EmailField(
                  controller: _identifier,
                  textInputAction: TextInputAction.next,
                ),
              const SizedBox(height: AppSpacing.md),
              PasswordField(
                controller: _password,
                textInputAction: TextInputAction.done,
                onSubmitted: _submit,
              ),
            ],
          ),
        ),

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
              : Text(l10n.authSubmitLogin),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => RegisterScreen(initialRole: _role),
                  ),
                ),
          child: Text(l10n.authNoAccount),
        ),

        const SizedBox(height: AppSpacing.lg),
        // Recordatorio de que no hay puerta cerrada: quien sólo quiere ver el
        // mapa no necesita nada de esto.
        Text(
          l10n.authGuestHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
