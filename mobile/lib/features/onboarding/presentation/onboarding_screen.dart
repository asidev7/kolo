import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../auth/presentation/session_controller.dart';

class _Page {
  const _Page(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    Icons.swap_vert_rounded,
    'Suis tes revenus et tes dépenses',
    'Note chaque entrée et chaque sortie d’argent en quelques secondes.',
  ),
  _Page(
    Icons.donut_large_rounded,
    'Contrôle ton budget du mois',
    'Fixe un plafond et vois en un coup d’œil ce qu’il te reste.',
  ),
  _Page(
    Icons.wifi_off_rounded,
    'Retrouve tes données même sans connexion',
    'Tout est enregistré sur ton téléphone. Pas besoin de réseau pour '
        'utiliser KOLO.',
  ),
];

/// Onboarding en 3 écrans, affiché une seule fois (§3.B).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ref.read(sessionProvider.notifier).completeOnboarding();
  }

  Future<void> _next() async {
    if (_index == _pages.length - 1) return _finish();
    await _controller.nextPage(
      duration: animationDuration(context),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(KoloSpacing.sm),
                child: TextButton(
                  onPressed: _finishing ? null : _finish,
                  child: const Text('Passer'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(KoloSpacing.xl),
                    child: Column(
                      children: [
                        const SizedBox(height: KoloSpacing.xxl),
                        Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: KoloColors.primarySoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            page.icon,
                            size: 56,
                            color: KoloColors.primary,
                          ),
                        ),
                        const SizedBox(height: KoloSpacing.xxl),
                        Text(
                          page.title,
                          style: theme.textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: KoloSpacing.md),
                        Text(
                          page.body,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: KoloColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Semantics(
              label: 'Page ${_index + 1} sur ${_pages.length}',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: animationDuration(context),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? KoloColors.primary
                            : KoloColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(KoloSpacing.xl),
              child: KoloButton(
                label: isLast ? 'Commencer' : 'Suivant',
                loading: _finishing,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
