import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart';
import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../core/constants/currencies.dart';
import '../../../core/errors/failures.dart';
import '../../../core/model/enums.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_text_field.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/session_controller.dart';
import '../../categories/domain/category.dart';
import '../data/transactions_repository.dart';
import '../domain/transaction.dart';
import '../domain/transaction_validator.dart';

/// Ajout ou modification d'une opération (§3.E).
///
/// - L'identifiant est généré **à l'ouverture** : une double soumission
///   réutilise le même et ne crée pas de doublon.
/// - Enregistrement 100 % local, aucun appel réseau.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.transactionId,
    this.initialType = TransactionType.expense,
  });

  /// `null` pour une création.
  final String? transactionId;
  final TransactionType initialType;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late final String _id;
  late final bool _isEdit;
  late TransactionType _type;
  late LocalDate _date;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _categoryId;
  KoloTransaction? _original;
  Map<String, String> _errors = const {};
  bool _loading = false;
  bool _notFound = false;
  bool _saving = false;

  /// Dernière catégorie choisie par type, pour retrouver la sélection quand
  /// on bascule Dépense ↔ Revenu.
  final Map<TransactionType, String?> _categoryByType = {};

  @override
  void initState() {
    super.initState();
    _isEdit = widget.transactionId != null;
    _id = widget.transactionId ?? ref.read(idGeneratorProvider)();
    _type = widget.initialType;
    _date = ref.read(timeSourceProvider).today();
    if (_isEdit) {
      _loading = true;
      unawaited(_loadOriginal());
    } else {
      unawaited(_preselectCategory(_type));
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  TransactionsRepository get _repo => ref.read(transactionsRepositoryProvider);

  String? get _owner => ref.read(currentOwnerProvider);

  Future<void> _loadOriginal() async {
    final tx = await _repo.findById(_id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (tx == null || tx.deletedAt != null || tx.userId != _owner) {
        _notFound = true;
        return;
      }
      _original = tx;
      _type = tx.type;
      _date = tx.occurredOn;
      _categoryId = tx.categoryId;
      _categoryByType[tx.type] = tx.categoryId;
      _amount.text = groupThousands(tx.amount);
      _note.text = tx.note ?? '';
    });
  }

  Future<void> _preselectCategory(TransactionType type) async {
    if (_categoryByType.containsKey(type)) {
      setState(() => _categoryId = _categoryByType[type]);
      return;
    }
    final last = await _repo.lastUsedCategoryId(_owner, type);
    if (!mounted || _type != type) return;
    setState(() {
      _categoryId = last;
      _categoryByType[type] = last;
    });
  }

  void _setType(TransactionType type) {
    if (type == _type) return;
    _categoryByType[_type] = _categoryId;
    setState(() {
      _type = type;
      _categoryId = null;
      _errors = Map.of(_errors)..remove(TransactionValidator.categoryField);
    });
    unawaited(_preselectCategory(type));
  }

  Future<void> _pickDate() async {
    final today = ref.read(timeSourceProvider).today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: today.addDays(TransactionValidator.maxDaysAhead).toDateTime(),
      helpText: "Date de l'opération",
    );
    if (picked != null) setState(() => _date = LocalDate.fromDateTime(picked));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final owner = _owner;
    final currency = ref.read(currencyProvider).value ?? Currencies.defaultCurrency;
    final draft = TransactionDraft(
      type: _type,
      amount: parseAmountInput(_amount.text, currency: currency),
      categoryId: _categoryId,
      note: _note.text,
      occurredOn: _date,
    );
    try {
      final outcome = await _repo.save(id: _id, ownerId: owner, draft: draft);
      if (!mounted) return;
      _afterSave(outcome, owner);
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _errors = e.fields);
    } on Object catch (e) {
      if (mounted) _showMessage(userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _afterSave(SaveOutcome outcome, String? owner) {
    final repo = _repo;
    final id = _id;
    final alerts = ref.read(budgetAlertServiceProvider);
    final month = ref.read(timeSourceProvider).currentMonth();
    if (_type == TransactionType.expense && month.contains(_date)) {
      unawaited(alerts.check(ownerId: owner, month: month));
    }
    context.pop();

    final messenger = rootMessengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    if (outcome == SaveOutcome.created) {
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('Opération enregistrée'),
          duration: const Duration(seconds: 5),
          // Depuis Flutter 3.29, une snackbar avec action reste affichée par
          // défaut : la spécification impose 5 s (§3.E).
          persist: false,
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () => unawaited(repo.delete(id: id, ownerId: owner)),
          ),
        ),
      );
    } else if (outcome == SaveOutcome.updated) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Modification enregistrée')),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Supprimer cette opération ?',
      message: 'Elle disparaîtra de ton historique et de tes totaux.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _repo.delete(id: _id, ownerId: _owner);
      if (!mounted) return;
      context.pop();
      rootMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Opération supprimée')),
      );
    } on Object catch (e) {
      if (mounted) _showMessage(userMessageFor(e));
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _clearError(String field) {
    if (_errors.containsKey(field)) {
      setState(() => _errors = Map.of(_errors)..remove(field));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoloColors.surface,
      appBar: AppBar(
        backgroundColor: KoloColors.surface,
        leading: IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(_isEdit ? "Modifier l'opération" : 'Nouvelle opération'),
        actions: [
          if (_isEdit && _original != null)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
              color: KoloColors.negative,
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingState();
    if (_notFound) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: "Cette opération n'existe plus",
        message: 'Elle a peut-être été supprimée.',
        actionLabel: 'Retour',
        onAction: () => context.pop(),
      );
    }
    final theme = Theme.of(context);
    final amountColor = _type == TransactionType.income
        ? KoloColors.positive
        : KoloColors.negative;
    final currency = ref.watch(currencyProvider).value ?? Currencies.defaultCurrency;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              KoloSpacing.lg,
              KoloSpacing.sm,
              KoloSpacing.lg,
              KoloSpacing.lg,
            ),
            children: [
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Dépense'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Revenu'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _setType(s.first),
              ),
              const SizedBox(height: KoloSpacing.lg),
              AmountField(
                key: const Key('amount-field'),
                controller: _amount,
                autofocus: !_isEdit,
                color: amountColor,
                currency: currency,
                errorText: _errors[TransactionValidator.amountField],
                onChanged: (_) => _clearError(TransactionValidator.amountField),
              ),
              Center(
                child: Text(
                  'Devise : ${currency.symbol} (${currency.code})',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: KoloSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: Text('Catégorie', style: theme.textTheme.labelLarge),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push(Routes.categories),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Gérer'),
                  ),
                ],
              ),
              _CategoryGrid(
                type: _type,
                selectedId: _categoryId,
                extraCategoryId: _original?.categoryId,
                onSelected: (id) {
                  setState(() => _categoryId = id);
                  _clearError(TransactionValidator.categoryField);
                },
              ),
              if (_errors[TransactionValidator.categoryField] case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: KoloSpacing.sm),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: KoloColors.negative,
                    ),
                  ),
                ),
              const SizedBox(height: KoloSpacing.xl),
              Text('Date', style: theme.textTheme.labelLarge),
              const SizedBox(height: KoloSpacing.sm),
              _DateChips(
                value: _date,
                today: ref.read(timeSourceProvider).today(),
                onChanged: (d) {
                  setState(() => _date = d);
                  _clearError(TransactionValidator.dateField);
                },
                onPickOther: _pickDate,
              ),
              if (_errors[TransactionValidator.dateField] case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: KoloSpacing.sm),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: KoloColors.negative,
                    ),
                  ),
                ),
              const SizedBox(height: KoloSpacing.xl),
              KoloTextField(
                label: 'Note (facultatif)',
                controller: _note,
                hint: 'Ex. : Zém pour le marché',
                maxLength: kMaxNoteLength,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                errorText: _errors[TransactionValidator.noteField],
                onChanged: (_) => _clearError(TransactionValidator.noteField),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KoloSpacing.lg,
            KoloSpacing.sm,
            KoloSpacing.lg,
            KoloSpacing.lg,
          ),
          child: KoloButton(
            key: const Key('save-transaction'),
            label: 'Enregistrer',
            loading: _saving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}

/// Grille des catégories du type courant.
class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid({
    required this.type,
    required this.selectedId,
    required this.onSelected,
    this.extraCategoryId,
  });

  final TransactionType type;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// Catégorie de l'opération modifiée : affichée même si elle est archivée.
  final String? extraCategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeCategoriesProvider(type));
    final lookup = ref.watch(categoryLookupProvider).value ?? const {};
    return active.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox(height: 120, child: LoadingState()),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(activeCategoriesProvider(type)),
      ),
      data: (categories) {
        final extra = extraCategoryId == null ? null : lookup[extraCategoryId];
        final list = <KoloCategory>[
          ...categories,
          if (extra != null &&
              extra.type == type &&
              !categories.any((c) => c.id == extra.id))
            extra,
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 84).floor().clamp(3, 6);
            final width =
                (constraints.maxWidth - (columns - 1) * KoloSpacing.sm) /
                columns;
            return Wrap(
              spacing: KoloSpacing.sm,
              runSpacing: KoloSpacing.sm,
              children: [
                for (final c in list)
                  SizedBox(
                    width: width,
                    child: _CategoryTile(
                      category: c,
                      selected: c.id == selectedId,
                      onTap: () => onSelected(c.id),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final KoloCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: category.name,
      excludeSemantics: true,
      child: Material(
        color: selected ? KoloColors.primarySoft : KoloColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: KoloRadii.cardRadius,
          side: BorderSide(
            color: selected ? KoloColors.primary : KoloColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: KoloRadii.cardRadius,
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: KoloSpacing.md,
              horizontal: KoloSpacing.xs,
            ),
            child: Column(
              children: [
                CategoryIcon(
                  iconKey: category.icon,
                  size: 36,
                  background: selected ? KoloColors.surface : null,
                ),
                const SizedBox(height: KoloSpacing.xs),
                Text(
                  category.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Raccourcis de date : Aujourd'hui, Hier, autre date (§3.E).
class _DateChips extends StatelessWidget {
  const _DateChips({
    required this.value,
    required this.today,
    required this.onChanged,
    required this.onPickOther,
  });

  final LocalDate value;
  final LocalDate today;
  final ValueChanged<LocalDate> onChanged;
  final VoidCallback onPickOther;

  @override
  Widget build(BuildContext context) {
    final yesterday = today.addDays(-1);
    final isOther = value != today && value != yesterday;
    return Wrap(
      spacing: KoloSpacing.sm,
      runSpacing: KoloSpacing.sm,
      children: [
        ChoiceChip(
          label: const Text("Aujourd'hui"),
          selected: value == today,
          onSelected: (_) => onChanged(today),
        ),
        ChoiceChip(
          label: const Text('Hier'),
          selected: value == yesterday,
          onSelected: (_) => onChanged(yesterday),
        ),
        ChoiceChip(
          avatar: const Icon(Icons.calendar_today_rounded, size: 16),
          label: Text(isOther ? KoloDates.short(value) : 'Autre date'),
          selected: isOther,
          onSelected: (_) => onPickOther(),
        ),
      ],
    );
  }
}
