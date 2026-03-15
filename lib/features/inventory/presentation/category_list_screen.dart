// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../data/models/inventory_models.dart';
import '../logic/product_master_provider.dart';

class CategoryListScreen extends ConsumerWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catAsync = ref.watch(productCategoryProvider);
    final unitAsync = ref.watch(productUnitProvider);
    final company = ref.watch(currentCompanyProvider);
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(
          'Categories & Units',
          style: TextStyle(fontSize: isTablet ? 24 : 20),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (company != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  company.name,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.all(isTablet ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Product Categories',
                onAdd: () => _showCategoryDialog(context, ref, null),
              ),
              const SizedBox(height: 10),
              catAsync.when(
                data: (categories) {
                  if (categories.isEmpty) {
                    return _buildEmptyState(
                      icon: Icons.category_outlined,
                      title: 'No categories yet',
                      subtitle: 'Tap + Add to create your first category',
                    );
                  }

                  return Column(
                    children: categories
                        .map((category) => _CategoryTile(
                              category: category,
                              onEdit: () =>
                                  _showCategoryDialog(context, ref, category),
                              onDelete: () =>
                                  _confirmDelete(context, ref, category),
                            ))
                        .toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Error loading categories')),
              ),
              SizedBox(height: isTablet ? 24 : 20),
              _buildSectionHeader(
                title: 'Units of Measure',
                onAdd: () => _showUnitDialog(context, ref, null),
              ),
              const SizedBox(height: 10),
              unitAsync.when(
                data: (units) {
                  if (units.isEmpty) {
                    return _buildEmptyState(
                      icon: Icons.straighten,
                      title: 'No units found',
                      subtitle: 'Tap + Add to create a new unit',
                    );
                  }

                  return Column(
                    children: units
                        .map((unit) => _UnitTile(
                              unit: unit,
                              onEdit: () => _showUnitDialog(context, ref, unit),
                            ))
                        .toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Error loading units')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required VoidCallback onAdd,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Future<void> _showCategoryDialog(
      BuildContext context, WidgetRef ref, ItemCategory? existing) async {
    final ctrl = TextEditingController(text: existing?.name ?? '');
    final company = ref.read(currentCompanyProvider);
    if (company == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Category' : 'Edit Category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;

    final dao = ref.read(productMasterDaoProvider);
    final category = existing ?? ItemCategory()
      ..companyId = company.id;
    category.name = name;
    await dao.saveCategory(category);

    ref.read(productCategoryRefreshProvider.notifier).state++;
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ItemCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
            'Delete "${category.name}"? Products assigned to this category will not be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(productMasterDaoProvider).deleteCategory(category.id);
    ref.read(productCategoryRefreshProvider.notifier).state++;
  }

  Future<void> _showUnitDialog(
      BuildContext context, WidgetRef ref, UnitOfMeasure? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final abbrevCtrl = TextEditingController(text: existing?.abbrev ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Unit' : 'Edit Unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Unit Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: abbrevCtrl,
              decoration: const InputDecoration(
                labelText: 'Abbreviation',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final name = nameCtrl.text.trim();
    final abbrev = abbrevCtrl.text.trim();
    if (name.isEmpty || abbrev.isEmpty) return;

    final dao = ref.read(productMasterDaoProvider);
    final unit = existing ?? UnitOfMeasure();
    unit.name = name;
    unit.abbrev = abbrev;
    await dao.saveUnit(unit);
    ref.invalidate(productUnitProvider);
  }
}

class _CategoryTile extends StatelessWidget {
  final ItemCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryTile({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent.withOpacity(0.1),
          child: const Icon(Icons.category, color: Colors.blueAccent, size: 20),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: Colors.blueAccent,
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red,
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  final UnitOfMeasure unit;
  final VoidCallback onEdit;

  const _UnitTile({
    required this.unit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent.withOpacity(0.1),
          child:
              const Icon(Icons.straighten, color: Colors.blueAccent, size: 20),
        ),
        title: Text(
          unit.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          unit.abbrev,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          color: Colors.blueAccent,
          onPressed: onEdit,
          tooltip: 'Edit',
        ),
      ),
    );
  }
}
