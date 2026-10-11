import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/network.dart';
import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/errors/failures.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_card.dart';
import '../../../core/widgets/kolo_text_field.dart';
import '../domain/credentials.dart';

/// Demande d'un code de réinitialisation (§3.C).
///
/// L'API répond toujours `202`, que le compte existe ou non : l'écran ne doit
/// donc **jamais** laisser croire que l'adresse est inconnue.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();

  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final email = _email.text.trim();
    final problem = validateEmail(email);
    setState(() {
      _error = problem;
      _sent = false;
    });
    if (problem != null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(authApiProvider).forgotPassword(email);
      if (mounted) setState(() => _sent = true);
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KoloSpacing.xl),
          children: [
            KoloTextField(
              label: 'Adresse e-mail',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              errorText: _error,
              enabled: !_submitting,
              onSubmitted: (_) => _submit(),
            ),
            if (_sent) ...[
              const SizedBox(height: KoloSpacing.lg),
              KoloCard(
                color: KoloColors.positiveSoft,
                borderColor: KoloColors.positiveSoft,
                child: Text(
                  'Si un compte existe avec cette adresse, un code vient d’y '
                  'être envoyé. Il est valable 15 minutes.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: KoloSpacing.lg),
              KoloButton(
                label: 'Saisir le code',
                onPressed: () => context.pushReplacement(
                  Routes.resetPasswordOf(_email.text.trim()),
                ),
              ),
            ] else ...[
              const SizedBox(height: KoloSpacing.xl),
              KoloButton(
                label: 'Recevoir un code',
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
