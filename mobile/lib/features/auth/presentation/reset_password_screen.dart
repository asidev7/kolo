import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/network.dart';
import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/errors/failures.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_text_field.dart';
import '../domain/credentials.dart';

/// Saisie du code reçu par e-mail et du nouveau mot de passe (§3.C).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail});

  /// Adresse pré-remplie quand on arrive depuis « Mot de passe oublié ».
  final String? initialEmail;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _code = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  bool _done = false;
  String? _generalError;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final email = _email.text.trim();
    final code = _code.text.trim();
    final errors = <String, String>{
      emailField: ?validateEmail(email),
      codeField: ?validateResetCode(code),
      passwordField: ?validatePassword(_password.text, email: email),
    };
    setState(() {
      _fieldErrors = errors;
      _generalError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(authApiProvider)
          .resetPassword(email: email, code: code, newPassword: _password.text);
      if (mounted) setState(() => _done = true);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _fieldErrors = failure.fields;
          _generalError = failure.fields.isEmpty ? failure.message : null;
        });
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _generalError = failure.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau mot de passe')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KoloSpacing.xl),
          children: [
            if (_done) ...[
              Text(
                'Ton mot de passe a été modifié. Toutes les sessions ont été '
                'déconnectées par sécurité.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: KoloSpacing.xl),
              KoloButton(
                label: 'Se connecter',
                onPressed: () => context.pushReplacement(Routes.login),
              ),
            ] else ...[
              Text(
                'Saisis le code à 6 chiffres reçu par e-mail, puis choisis un '
                'nouveau mot de passe.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: KoloColors.textSecondary,
                ),
              ),
              const SizedBox(height: KoloSpacing.xl),
              KoloTextField(
                label: 'Adresse e-mail',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                errorText: _fieldErrors[emailField],
                enabled: !_submitting,
              ),
              const SizedBox(height: KoloSpacing.lg),
              KoloTextField(
                label: 'Code reçu',
                controller: _code,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                maxLength: 6,
                errorText: _fieldErrors[codeField],
                enabled: !_submitting,
              ),
              const SizedBox(height: KoloSpacing.lg),
              KoloTextField(
                label: 'Nouveau mot de passe',
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                helperText: 'Au moins $minPasswordLength caractères.',
                errorText: _fieldErrors[passwordField],
                enabled: !_submitting,
                onSubmitted: (_) => _submit(),
              ),
              if (_generalError case final message?) ...[
                const SizedBox(height: KoloSpacing.lg),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: KoloColors.negative,
                  ),
                ),
              ],
              const SizedBox(height: KoloSpacing.xl),
              KoloButton(
                label: 'Changer mon mot de passe',
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
