import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/errors/failures.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_text_field.dart';
import 'session_controller.dart';

/// Connexion à un compte existant (§3.C).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Renseigne ton adresse et ton mot de passe.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .signIn(email: email, password: _password.text);
    } on Failure catch (failure) {
      // Le message du serveur est déjà en français simple (docs/API.md) :
      // « Identifiants incorrects » ne dit pas lequel des deux est faux.
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Se connecter')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KoloSpacing.xl),
          children: [
            KoloTextField(
              label: 'Adresse e-mail',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              enabled: !_submitting,
            ),
            const SizedBox(height: KoloSpacing.lg),
            KoloTextField(
              label: 'Mot de passe',
              controller: _password,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              enabled: !_submitting,
              onSubmitted: (_) => _submit(),
            ),
            if (_error case final message?) ...[
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
              label: 'Se connecter',
              loading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: KoloSpacing.sm),
            KoloButton(
              label: 'Mot de passe oublié ?',
              variant: KoloButtonVariant.text,
              onPressed: _submitting
                  ? null
                  : () => context.push(Routes.forgotPassword),
            ),
            const SizedBox(height: KoloSpacing.sm),
            KoloButton(
              label: 'Créer un compte',
              variant: KoloButtonVariant.text,
              onPressed: _submitting
                  ? null
                  : () => context.pushReplacement(Routes.register),
            ),
          ],
        ),
      ),
    );
  }
}
