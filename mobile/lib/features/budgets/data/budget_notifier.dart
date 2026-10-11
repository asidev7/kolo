import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Envoi d'une notification locale. Abstrait pour les tests.
abstract interface class LocalNotifier {
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  /// Demande l'autorisation à l'OS (Android 13+, iOS). Retourne `false` si
  /// l'utilisateur refuse.
  Future<bool> requestPermission();
}

/// Implémentation `flutter_local_notifications`. Aucune donnée ne quitte le
/// téléphone : notifications **locales** uniquement.
class PluginLocalNotifier implements LocalNotifier {
  PluginLocalNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _init;

  static const _channel = AndroidNotificationDetails(
    'budget_alerts',
    'Alertes budget',
    channelDescription: 'Prévient quand ton budget du mois atteint un seuil.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  Future<void> _ensureInitialized() => _init ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _ensureInitialized();
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(),
        ),
      );
    } on Object catch (e) {
      // Une notification manquée ne doit jamais faire échouer une saisie.
      debugPrint('Notification non affichée : ${e.runtimeType}');
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _ensureInitialized();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? false;
      }
      return false;
    } on Object {
      return false;
    }
  }
}
