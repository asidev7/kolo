import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:kolo/database/app_database.dart';

/// Base SQLite en mémoire, neuve à chaque appel.
AppDatabase newTestDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);
