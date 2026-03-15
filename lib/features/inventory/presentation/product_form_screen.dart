// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../data/models/inventory_models.dart';
import '../logic/product_master_provider.dart';
import 'category_list_screen.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final Product? product;
  const ProductFormScreen({super.key, this.product});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _nameCtrl = TextEditingController();
  final _saleRateCtrl = TextEditingController();
  final _openingCtrl = TextEditingController();

  UnitOfMeasure? _uom;
  ItemCategory? _category;
  bool _trackStock = true;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _nameCtrl.text = p.name;
      _saleRateCtrl.text = p.salePrice.toString();
      _openingCtrl.text = p.openingQty.toString();
      _trackStock = p.isTracked;

      // Load unit data
      _loadProductData(p);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _saleRateCtrl.dispose();
    _openingCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProductData(Product product) async {
    final unitAsync = ref.read(productUnitProvider);
    final catAsync = ref.read(productCategoryProvider);

    unitAsync.whenData((units) {
      if (product.uomId != null) {
        _uom = units.firstWhere(
          (unit) => unit.id == product.uomId,
          orElse: () => units.first,
        );
      }
    });

    catAsync.whenData((cats) {
      if (product.categoryId != null) {
        try {
          _category = cats.firstWhere((c) => c.id == product.categoryId);
        } catch (_) {}
      }
    });

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.read(currentCompanyProvider)!;
    final dao = ref.read(productMasterDaoProvider);
    final isTablet = MediaQuery.of(context).size.width > 600;

    final unitAsync = ref.watch(productUnitProvider);
    final catAsync = ref.watch(productCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: Text(
          widget.product == null ? 'Add Product' : 'Edit Product',
          style: TextStyle(fontSize: isTablet ? 24 : 20),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                company.name,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
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
          padding: EdgeInsets.fromLTRB(
            isTablet ? 24 : 16,
            isTablet ? 20 : 16,
            isTablet ? 24 : 16,
            (isTablet ? 20 : 16) + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(isTablet ? 20 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product Details',
                      style: TextStyle(
                        fontSize: isTablet ? 18 : 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    SizedBox(height: isTablet ? 16 : 12),
                    _field(_nameCtrl, 'Product Name'),
                    SizedBox(height: isTablet ? 16 : 12),
                    _field(_saleRateCtrl, 'Sale Rate', isNumber: true),
                    SizedBox(height: isTablet ? 16 : 12),
                    unitAsync.when(
                      data: (units) => DropdownButtonFormField<UnitOfMeasure>(
                        initialValue: _uom,
                        decoration: InputDecoration(
                          labelText: 'Unit',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                color: Colors.blueAccent),
                            tooltip: 'Manage Units',
                            onPressed: () async {
                              final dao = ref.read(productMasterDaoProvider);
                              final beforeUnits = await dao.getUnits();
                              final beforeIds =
                                  beforeUnits.map((u) => u.id).toSet();

                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CategoryListScreen(),
                                ),
                              );

                              final afterUnits = await dao.getUnits();
                              UnitOfMeasure? newlyAddedUnit;
                              for (final unit in afterUnits) {
                                if (!beforeIds.contains(unit.id)) {
                                  if (newlyAddedUnit == null ||
                                      unit.id > newlyAddedUnit.id) {
                                    newlyAddedUnit = unit;
                                  }
                                }
                              }

                              if (mounted && newlyAddedUnit != null) {
                                setState(() => _uom = newlyAddedUnit);
                              }

                              ref.invalidate(productUnitProvider);
                            },
                          ),
                        ),
                        items: units
                            .map((u) => DropdownMenuItem(
                                value: u, child: Text(u.abbrev)))
                            .toList(),
                        onChanged: (v) => setState(() => _uom = v),
                      ),
                      loading: () => const SizedBox(
                        height: 48,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, __) => const Text('UOM error'),
                    ),
                    SizedBox(height: isTablet ? 16 : 12),
                    catAsync.when(
                      data: (cats) => DropdownButtonFormField<ItemCategory?>(
                        initialValue: _category,
                        decoration: InputDecoration(
                          labelText: 'Category (optional)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                color: Colors.blueAccent),
                            tooltip: 'Manage Categories',
                            onPressed: () async {
                              final beforeCategories =
                                  await dao.getCategories(company.id);
                              final beforeIds =
                                  beforeCategories.map((c) => c.id).toSet();

                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CategoryListScreen(),
                                ),
                              );

                              final afterCategories =
                                  await dao.getCategories(company.id);
                              ItemCategory? newlyAddedCategory;
                              for (final category in afterCategories) {
                                if (!beforeIds.contains(category.id)) {
                                  if (newlyAddedCategory == null ||
                                      category.id > newlyAddedCategory.id) {
                                    newlyAddedCategory = category;
                                  }
                                }
                              }

                              if (mounted && newlyAddedCategory != null) {
                                setState(() => _category = newlyAddedCategory);
                              }

                              ref.invalidate(productCategoryProvider);
                            },
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<ItemCategory?>(
                            value: null,
                            child: Text('-- No Category --'),
                          ),
                          ...cats.map((c) => DropdownMenuItem<ItemCategory?>(
                                value: c,
                                child: Text(c.name),
                              )),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                      ),
                      loading: () => const SizedBox(
                        height: 48,
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isTablet ? 16 : 12),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: EdgeInsets.all(isTablet ? 16 : 12),
                child: Column(
                  children: [
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _trackStock,
                      onChanged: (v) {
                        setState(() {
                          _trackStock = v;
                          if (!v) {
                            _openingCtrl.clear();
                          }
                        });
                      },
                      title: const Text('Track Stock'),
                    ),
                    if (_trackStock) ...[
                      SizedBox(height: isTablet ? 8 : 6),
                      _field(_openingCtrl, 'Opening Stock', isNumber: true),
                    ],
                  ],
                ),
              ),
              SizedBox(height: isTablet ? 20 : 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade400, width: 2),
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isTablet ? 12 : 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        padding:
                            EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed: () async {
                        final saleRate =
                            double.tryParse(_saleRateCtrl.text) ?? 0;
                        if (saleRate < 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sale Rate cannot be negative'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        if (_nameCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Product Name is required'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        final p = widget.product ?? Product();

                        p.companyId = company.id;
                        p.name = _nameCtrl.text.trim();
                        final currentSku = widget.product?.sku ?? '';
                        if (currentSku.isEmpty) {
                          final slug = p.name
                              .toLowerCase()
                              .replaceAll(RegExp(r'[^a-z0-9]'), '-')
                              .replaceAll(RegExp(r'-+'), '-')
                              .replaceAll(RegExp(r'^-|-$'), '');
                          p.sku =
                              '${company.id}-$slug-${DateTime.now().millisecondsSinceEpoch}';
                        } else {
                          p.sku = currentSku;
                        }
                        p.salePrice = saleRate;
                        p.lastCost = 0;
                        p.isTracked = _trackStock;
                        p.openingQty = double.tryParse(_openingCtrl.text) ?? 0;
                        p.categoryId = _category?.id;
                        p.uomId = _uom?.id;

                        await dao.saveProduct(p);

                        if (widget.product == null &&
                            _trackStock &&
                            p.openingQty > 0) {
                          await dao.insertOpeningStock(
                            companyId: company.id,
                            productId: p.id,
                            qty: p.openingQty,
                          );
                        }

                        ref.invalidate(productListProvider);
                        if (mounted) Navigator.pop(context);
                      },
                      child: Text(
                        widget.product == null
                            ? 'Save Product'
                            : 'Update Product',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool isNumber = false}) {
    return TextField(
      controller: c,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      onChanged: label == 'Opening Stock'
          ? (value) {
              // Automatically enable stock tracking if opening stock is entered
              if (value.isNotEmpty &&
                  double.tryParse(value) != null &&
                  double.tryParse(value)! > 0) {
                if (!_trackStock) {
                  setState(() => _trackStock = true);
                }
              }
            }
          : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
