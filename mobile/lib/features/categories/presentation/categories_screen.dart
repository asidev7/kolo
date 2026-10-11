import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/kolo_colors.dart';
import '../../../app/theme/kolo_tokens.dart';
import '../../../app/theme/kolo_typography.dart';
import '../../../core/errors/failures.dart';
import '../../../core/model/enums.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/kolo_button.dart';
import '../../../core/widgets/kolo_text_field.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/category.dart';

/// Catégories par défaut et personnalisées (§3.G).
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Catégories'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Dépenses'),
                Tab(text: 'Revenus'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _create(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nouvelle catégorie'),
          ),
          body: const TabBarView(
            children: [
              _CategoryList(type: TransactionType.expense),
              _CategoryList(type: TransactionType.income),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) {
    final index = DefaultTabController.of(context).index;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _NewCategorySheet(
        type: index == 0 ? TransactionType.expense : TransactionType.income,
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.type});

  final TransactionType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(activeCategoriesProvider(type));
    return categories.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(activeCategoriesProvider(type)),
      ),
      data: (list) => ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(indent: 72),
        itemBuilder: (context, i) {
          final c = list[i];
          return ListTile(
            minVerticalPadding: KoloSpacing.md,
            leading: CategoryIcon(iconKey: c.icon),
            title: Text(c.name),
            subtitle: c.isDefault ? const Text('Par défaut') : null,
            trailing: c.isDefault
                ? null
                : IconButton(
                    tooltip: 'Archiver ${c.name}',
                    icon: const Icon(Icons.archive_outlined),
                    onPressed: () => _archive(context, ref, c),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    KoloCategory category,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archiver « ${category.name} » ?',
      message:
          'Elle ne sera plus proposée à la saisie. Tes anciennes opérations '
          'gardent cette catégorie.',
      confirmLabel: 'Archiver',
    );
    if (!confirmed) return;
    try {
      await ref
          .read(categoriesRepositoryProvider)
          .archive(ownerId: ref.read(currentOwnerProvider), id: category.id);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    }
  }
}

class _NewCategorySheet extends ConsumerStatefulWidget {
  const _NewCategorySheet({required this.type});

  final TransactionType type;

  @override
  ConsumerState<_NewCategorySheet> createState() => _NewCategorySheetState();
}

class _NewCategorySheetState extends ConsumerState<_NewCategorySheet> {
  final _name = TextEditingController();
  late TransactionType _type = widget.type;
  String _icon = 'other';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(categoriesRepositoryProvider)
          .createCustom(
            ownerId: ref.read(currentOwnerProvider),
            name: _name.text,
            type: _type,
            icon: _icon,
          );
      if (mounted) Navigator.of(context).pop();
    } on ValidationFailure catch (e) {
      if (mounted) setState(() => _error = e.fields['name']);
    } on Object catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            KoloSpacing.xl,
            0,
            KoloSpacing.xl,
            KoloSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nouvelle catégorie', style: KoloTypography.subtitle),
              const SizedBox(height: KoloSpacing.lg),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Dépense'),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Revenu'),
                  ),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: KoloSpacing.lg),
              KoloTextField(
                label: 'Nom',
                controller: _name,
                autofocus: true,
                maxLength: CategoryRules.maxNameLength,
                textCapitalization: TextCapitalization.sentences,
                errorText: _error,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: KoloSpacing.md),
              Text('Icône', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: KoloSpacing.sm),
              Wrap(
                spacing: KoloSpacing.sm,
                runSpacing: KoloSpacing.sm,
                children: [
                  for (final key in CategoryIcons.selectable)
                    Semantics(
                      selected: key == _icon,
                      button: true,
                      label: 'Icône $key',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _icon = key),
                        child: Container(
                          width: kMinTapTarget,
                          height: kMinTapTarget,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: key == _icon
                                ? KoloColors.primary
                                : KoloColors.primarySoft,
                          ),
                          child: Icon(
                            CategoryIcons.of(key),
                            size: 22,
                            color: key == _icon
                                ? Colors.white
                                : KoloColors.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: KoloSpacing.xl),
              KoloButton(
                label: 'Créer la catégorie',
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
