import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/app/router.dart';
import 'package:kolo/features/auth/domain/session.dart';

void main() {
  const fresh = Session(onboardingSeen: false, mode: SessionMode.none);
  const onboarded = Session(onboardingSeen: true, mode: SessionMode.none);
  const local = Session(onboardingSeen: true, mode: SessionMode.local);

  test('session en chargement → écran de démarrage', () {
    expect(redirectFor(const AsyncLoading(), Routes.dashboard), Routes.splash);
    expect(redirectFor(const AsyncLoading(), Routes.splash), isNull);
  });

  test('onboarding jamais vu → onboarding, depuis partout', () {
    expect(
      redirectFor(const AsyncData(fresh), Routes.splash),
      Routes.onboarding,
    );
    expect(
      redirectFor(const AsyncData(fresh), Routes.dashboard),
      Routes.onboarding,
    );
    expect(redirectFor(const AsyncData(fresh), Routes.onboarding), isNull);
  });

  test('aucun mode choisi → accueil ; écrans publics accessibles', () {
    expect(
      redirectFor(const AsyncData(onboarded), Routes.onboarding),
      Routes.welcome,
    );
    expect(
      redirectFor(const AsyncData(onboarded), Routes.dashboard),
      Routes.welcome,
    );
    expect(redirectFor(const AsyncData(onboarded), Routes.localMode), isNull);
    expect(redirectFor(const AsyncData(onboarded), Routes.privacy), isNull);
  });

  test('mode local → les écrans d\'entrée mènent au tableau de bord', () {
    for (final entry in [
      Routes.splash,
      Routes.onboarding,
      Routes.welcome,
      Routes.localMode,
    ]) {
      expect(redirectFor(const AsyncData(local), entry), Routes.dashboard);
    }
    expect(redirectFor(const AsyncData(local), Routes.history), isNull);
    expect(redirectFor(const AsyncData(local), Routes.privacy), isNull);
  });
}
