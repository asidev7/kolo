import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/model/enums.dart';
import '../features/auth/domain/session.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/local_mode_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/session_controller.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/budgets/presentation/budget_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/settings/presentation/currency_screen.dart';
import '../features/settings/presentation/privacy_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';
import '../features/transactions/presentation/history_screen.dart';
import '../features/transactions/presentation/transaction_form_screen.dart';
import 'home_shell.dart';
import 'theme/kolo_page_transitions.dart';
import 'theme/kolo_tokens.dart';

/// Chemins de navigation. Toujours passer par ces constantes.
abstract final class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const welcome = '/welcome';
  static const localMode = '/welcome/local';
  static const register = '/welcome/register';
  static const login = '/welcome/login';
  static const forgotPassword = '/welcome/forgot';
  static const resetPassword = '/welcome/reset';
  static const dashboard = '/dashboard';
  static const history = '/history';
  static const statistics = '/statistics';
  static const profile = '/profile';
  static const categories = '/profile/categories';
  static const currency = '/profile/currency';
  static const privacy = '/privacy';
  static const budget = '/budget';
  static const newTransaction = '/transactions/new';

  static String editTransaction(String id) => '/transactions/$id';

  static String newTransactionOf(TransactionType type) =>
      '$newTransaction?type=${type.wire}';

  /// Écran de saisie du code, avec l'adresse déjà remplie.
  static String resetPasswordOf(String email) =>
      '$resetPassword?email=${Uri.encodeQueryComponent(email)}';

  /// Écrans accessibles avant d'avoir choisi un mode (local ou compte).
  static const _public = {
    welcome,
    localMode,
    register,
    login,
    forgotPassword,
    resetPassword,
    privacy,
  };

  static bool isPublic(String location) => _public.contains(location);
}

/// Page poussée avec la transition KOLO (voir [koloPageTransition]).
///
/// `go_router` ne reconnaît pas le `MaterialApp` de la version de Flutter
/// utilisée ici : une route déclarée avec `builder:` reçoit alors un
/// `NoTransitionPage`, c'est-à-dire **aucune** animation, et le
/// `PageTransitionsTheme` du thème n'est jamais consulté. On déclare donc la
/// page — et sa durée de 220 ms (§2.3) — explicitement.
CustomTransitionPage<Object?> koloPage({
  required LocalKey key,
  required Widget child,
  String? name,
  bool fullscreenDialog = false,
}) => CustomTransitionPage<Object?>(
  key: key,
  name: name,
  child: child,
  fullscreenDialog: fullscreenDialog,
  transitionDuration: kAnimationDuration,
  reverseTransitionDuration: kAnimationDuration,
  transitionsBuilder: koloPageTransition,
);

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  // Réévalue les redirections à chaque changement de session.
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(sessionProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        redirectFor(ref.read(sessionProvider), state.matchedLocation),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'local',
            pageBuilder: (context, state) => koloPage(
              key: state.pageKey,
              name: state.name ?? state.path,
              child: const LocalModeScreen(),
            ),
          ),
          GoRoute(
            path: 'register',
            pageBuilder: (context, state) => koloPage(
              key: state.pageKey,
              name: state.name ?? state.path,
              child: const RegisterScreen(),
            ),
          ),
          GoRoute(
            path: 'login',
            pageBuilder: (context, state) => koloPage(
              key: state.pageKey,
              name: state.name ?? state.path,
              child: const LoginScreen(),
            ),
          ),
          GoRoute(
            path: 'forgot',
            pageBuilder: (context, state) => koloPage(
              key: state.pageKey,
              name: state.name ?? state.path,
              child: const ForgotPasswordScreen(),
            ),
          ),
          GoRoute(
            path: 'reset',
            pageBuilder: (context, state) => koloPage(
              key: state.pageKey,
              name: state.name ?? state.path,
              child: ResetPasswordScreen(
                initialEmail: state.uri.queryParameters['email'],
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.privacy,
        pageBuilder: (context, state) => koloPage(
          key: state.pageKey,
          name: state.name ?? state.path,
          child: const PrivacyScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.history,
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.statistics,
                builder: (context, state) => const StatisticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'currency',
                    parentNavigatorKey: _rootKey,
                    pageBuilder: (context, state) => koloPage(
                      key: state.pageKey,
                      name: state.name ?? state.path,
                      child: const CurrencyScreen(),
                    ),
                  ),
                  GoRoute(
                    path: 'categories',
                    parentNavigatorKey: _rootKey,
                    pageBuilder: (context, state) => koloPage(
                      key: state.pageKey,
                      name: state.name ?? state.path,
                      child: const CategoriesScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.budget,
        pageBuilder: (context, state) => koloPage(
          key: state.pageKey,
          name: state.name ?? state.path,
          child: const BudgetScreen(),
        ),
      ),
      GoRoute(
        path: Routes.newTransaction,
        pageBuilder: (context, state) => koloPage(
          key: state.pageKey,
          name: state.name ?? state.path,
          fullscreenDialog: true,
          child: TransactionFormScreen(
            initialType: state.uri.queryParameters['type'] == 'income'
                ? TransactionType.income
                : TransactionType.expense,
          ),
        ),
      ),
      GoRoute(
        path: '/transactions/:id',
        pageBuilder: (context, state) => koloPage(
          key: state.pageKey,
          name: state.name ?? state.path,
          fullscreenDialog: true,
          child: TransactionFormScreen(
            transactionId: state.pathParameters['id'],
          ),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Règles de redirection (fonction pure, testée) :
/// session en chargement → démarrage ; onboarding non vu → onboarding ;
/// aucun mode choisi → accueil ; sinon on quitte les écrans d'entrée.
String? redirectFor(AsyncValue<Session> sessionValue, String location) {
  final session = sessionValue.value;
  if (session == null) {
    return location == Routes.splash ? null : Routes.splash;
  }
  if (!session.onboardingSeen) {
    return location == Routes.onboarding ? null : Routes.onboarding;
  }
  if (!session.hasChosenMode) {
    return Routes.isPublic(location) ? null : Routes.welcome;
  }
  const entry = {
    Routes.splash,
    Routes.onboarding,
    Routes.welcome,
    Routes.localMode,
    Routes.register,
    Routes.login,
    Routes.forgotPassword,
    Routes.resetPassword,
  };
  return entry.contains(location) ? Routes.dashboard : null;
}
