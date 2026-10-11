import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/errors/failures.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_text_field.dart';
import '../domain/credentials.dart';
import 'session_controller.dart';

/// Création de compte (§3.C).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _firstName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  String? _generalError;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _firstName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final email = _email.text.trim();
    final firstName = _firstName.text.trim();
    final errors = <String, String>{
      firstNameField: ?validateFirstName(firstName),
      emailField: ?validateEmail(email),
      passwordField: ?validatePassword(
        _password.text,
        email: email,
        firstName: firstName,
      ),
    };
    setState(() {
      _fieldErrors = errors;
      _generalError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _submitting = true);
    try {
      // Le routeur redirige vers le tableau de bord dès que la session change.
      await ref
          .read(sessionProvider.notifier)
          .register(
            email: email,
            password: _password.text,
            firstName: firstName,
          );
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
      appBar: AppBar(title: const Text('Créer un compte')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KoloSpacing.xl),
          children: [
            Text(
              'Ton compte sauvegarde tes opérations et te permet de les '
              'retrouver sur un autre téléphone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: KoloColors.textSecondary,
              ),
            ),
            const SizedBox(height: KoloSpacing.xl),
            KoloTextField(
              label: 'Prénom',
              controller: _firstName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.givenName],
              errorText: _fieldErrors[firstNameField],
              enabled: !_submitting,
            ),
            const SizedBox(height: KoloSpacing.lg),
            KoloTextField(
              label: 'Adresse e-mail',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              errorText: _fieldErrors[emailField],
              enabled: !_submitting,
            ),
            const SizedBox(height: KoloSpacing.lg),
            KoloTextField(
              label: 'Mot de passe',
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
              label: 'Créer mon compte',
              loading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: KoloSpacing.sm),
            KoloButton(
              label: "J'ai déjà un compte",
              variant: KoloButtonVariant.text,
              onPressed: _submitting
                  ? null
                  : () => context.pushReplacement(Routes.login),
            ),
            const SizedBox(height: KoloSpacing.lg),
            Text(
              'Ton mot de passe est chiffré sur le serveur : personne, pas même '
              'nous, ne peut le lire.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: KoloColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
