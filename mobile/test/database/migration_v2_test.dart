import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/database/app_database.dart';

import 'generated/kolo/generated/schema.dart';
import 'generated/kolo/generated/schema_v1.dart' as v1;
import 'generated/kolo/generated/schema_v2.dart' as v2;

/// Migration v1 → v2 (ajout de `sync_conflicts`, ARCHITECTURE §7).
///
/// Le schéma seul est vérifié par le test généré
/// (`generated/kolo/migration_test.dart`) ; ici on vérifie ce qui compte pour
/// l'utilisateur : **aucune ligne existante ne disparaît**. Une base v1
/// contient déjà des opérations et des entrées d'outbox non envoyées — les
/// perdre à la mise à jour serait une perte de données financières.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v1 → v2 conserve catégories, transactions et outbox', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.categories, const [
          v1.CategoriesData(
            id: 'cat-cafe',
            userId: 'u-1',
            createdAt: '2026-10-01T08:00:00.000Z',
            updatedAt: '2026-10-01T08:00:00.000Z',
            version: 0,
            syncStatus: 'synced',
            name: 'Café',
            type: 'expense',
            icon: 'local_cafe',
            isDefault: 0,
            sortOrder: 0,
          ),
          v1.CategoriesData(
            id: 'cat-salaire',
            userId: 'u-1',
            createdAt: '2026-10-01T08:00:00.000Z',
            updatedAt: '2026-10-01T08:00:00.000Z',
            version: 0,
            syncStatus: 'synced',
            name: 'Salaire',
            type: 'income',
            icon: 'payments',
            isDefault: 0,
            sortOrder: 1,
          ),
        ]);

        batch.insertAll(oldDb.transactions, const [
          v1.TransactionsData(
            id: 'tx-1',
            userId: 'u-1',
            createdAt: '2026-10-02T07:30:00.000Z',
            updatedAt: '2026-10-02T07:30:00.000Z',
            version: 3,
            deletedAt: null,
            syncStatus: 'pending',
            type: 'expense',
            amount: 1500,
            currency: 'XOF',
            categoryId: 'cat-cafe',
            note: 'Café du matin',
            noteSearch: 'cafe du matin',
            occurredOn: '2026-10-02',
          ),
          v1.TransactionsData(
            id: 'tx-2',
            userId: 'u-1',
            createdAt: '2026-10-01T09:00:00.000Z',
            updatedAt: '2026-10-01T09:00:00.000Z',
            version: 1,
            syncStatus: 'synced',
            type: 'income',
            amount: 120000,
            currency: 'XOF',
            categoryId: 'cat-salaire',
            occurredOn: '2026-10-01',
          ),
        ]);

        batch.insertAll(oldDb.outbox, const [
          v1.OutboxData(
            seq: 1,
            opId: 'op-1',
            entity: 'transaction',
            entityId: 'tx-1',
            opType: 'upsert',
            payload: '{"amount":1500}',
            changedFields: '["amount"]',
            baseVersion: 2,
            userId: 'u-1',
            status: 'pending',
            attempts: 0,
            createdAt: '2026-10-02T07:30:00.000Z',
          ),
        ]);
      },
      validateItems: (newDb) async {
        // `beforeOpen` réinsère les catégories par défaut après la migration :
        // on vérifie la conservation ligne à ligne, pas l'égalité de la table.
        final categories = await newDb.select(newDb.categories).get();
        final byId = {for (final c in categories) c.id: c};
        expect(byId['cat-cafe']?.name, 'Café');
        expect(byId['cat-cafe']?.type, 'expense');
        expect(byId['cat-salaire']?.type, 'income');

        final transactions = await newDb.select(newDb.transactions).get();
        expect(transactions, hasLength(2));
        final tx = transactions.firstWhere((t) => t.id == 'tx-1');
        expect(tx.userId, 'u-1');
        expect(tx.amount, 1500);
        expect(tx.currency, 'XOF');
        expect(tx.categoryId, 'cat-cafe');
        expect(tx.note, 'Café du matin');
        expect(tx.occurredOn, '2026-10-02');
        expect(tx.version, 3);
        expect(tx.syncStatus, 'pending');
        // La version du serveur connue n'est pas perdue : c'est le
        // `base_version` des prochains envois.
        expect(tx.createdAt, '2026-10-02T07:30:00.000Z');

        final outbox = await newDb.select(newDb.outbox).get();
        expect(outbox, hasLength(1));
        expect(outbox.single.opId, 'op-1');
        expect(outbox.single.entityId, 'tx-1');
        expect(outbox.single.entity, 'transaction');
        expect(outbox.single.opType, 'upsert');
        expect(outbox.single.payload, jsonEncode({'amount': 1500}));
        expect(outbox.single.changedFields, jsonEncode(['amount']));
        expect(outbox.single.baseVersion, 2);
        expect(outbox.single.userId, 'u-1');
        expect(outbox.single.status, 'pending');
        expect(outbox.single.attempts, 0);

        // Table ajoutée par la v2 : présente, et vide au moment de la
        // migration (les conflits naissent des synchronisations à venir).
        expect(await newDb.select(newDb.syncConflicts).get(), isEmpty);
      },
    );
  });
}
