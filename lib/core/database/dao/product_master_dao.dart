import 'dart:convert';

import 'package:isar/isar.dart';

import '../../../data/models/inventory_models.dart';
import '../../../data/models/invoice_stock_models.dart';
import '../../../data/models/sync_change_model.dart';

class ProductMasterDao {
  final Isar isar;

  ProductMasterDao(this.isar);

  Future<void> saveProduct(Product product) async {
    await isar.writeTxn(() async {
      final isNew = product.id == Isar.autoIncrement;
      final savedId = await isar.products.put(product);
      await isar.syncChanges.put(SyncChange()
        ..companyId = product.companyId
        ..table = 'products'
        ..operation = isNew ? ChangeOperation.create : ChangeOperation.update
        ..recordId = savedId
        ..data = jsonEncode({
          'id': savedId,
          'company_id': product.companyId,
          'sku': product.sku,
          'name': product.name,
          'category_id': product.categoryId,
          'uom_id': product.uomId,
          'is_tracked': product.isTracked,
          'last_cost': product.lastCost,
          'sale_price': product.salePrice,
          'opening_qty': product.openingQty,
          'is_active': product.isActive,
        })
        ..createdAt = DateTime.now()
        ..synced = false);
    });
  }

  Future<List<Product>> getProductsByCompany(int companyId) async {
    return isar.products.filter().companyIdEqualTo(companyId).findAll();
  }

  Future<void> saveCategory(ItemCategory category) async {
    await isar.writeTxn(() async {
      final isNew = category.id == Isar.autoIncrement;
      final savedId = await isar.itemCategorys.put(category);
      await isar.syncChanges.put(SyncChange()
        ..companyId = category.companyId
        ..table = 'item_categories'
        ..operation = isNew ? ChangeOperation.create : ChangeOperation.update
        ..recordId = savedId
        ..data = jsonEncode({
          'id': savedId,
          'company_id': category.companyId,
          'name': category.name,
          'parent_category_id': category.parentCategoryId,
        })
        ..createdAt = DateTime.now()
        ..synced = false);
    });
  }

  Future<List<ItemCategory>> getCategories(int companyId) async {
    return isar.itemCategorys.filter().companyIdEqualTo(companyId).findAll();
  }

  Future<void> deleteCategory(int id) async {
    await isar.writeTxn(() async {
      // Get the category before deletion so we can record companyId
      final cat = await isar.itemCategorys.get(id);
      await isar.itemCategorys.delete(id);
      if (cat != null) {
        await isar.syncChanges.put(SyncChange()
          ..companyId = cat.companyId
          ..table = 'item_categories'
          ..operation = ChangeOperation.delete
          ..recordId = id
          ..data = jsonEncode({'id': id})
          ..createdAt = DateTime.now()
          ..synced = false);
      }
    });
  }

  Future<void> saveUnit(UnitOfMeasure unit) async {
    await isar.writeTxn(() async {
      final isNew = unit.id == Isar.autoIncrement;
      final savedId = await isar.unitOfMeasures.put(unit);
      await isar.syncChanges.put(SyncChange()
        ..companyId = 0
        ..table = 'units_of_measure'
        ..operation = isNew ? ChangeOperation.create : ChangeOperation.update
        ..recordId = savedId
        ..data = jsonEncode({
          'id': savedId,
          'name': unit.name,
          'abbrev': unit.abbrev,
        })
        ..createdAt = DateTime.now()
        ..synced = false);
    });
  }

  Future<List<UnitOfMeasure>> getUnits() async {
    return isar.unitOfMeasures.where().findAll();
  }

  Future<void> insertOpeningStock({
    required int companyId,
    required int productId,
    required double qty,
  }) async {
    if (qty == 0) return;

    final stock = StockLedger()
      ..companyId = companyId
      ..productId = productId
      ..date = DateTime.now()
      ..movementType = StockMovementType.inAdjustment
      ..quantityDelta = qty;

    await isar.writeTxn(() async {
      final stockId = await isar.stockLedgers.put(stock);
      await isar.syncChanges.put(SyncChange()
        ..companyId = companyId
        ..table = 'stock_ledgers'
        ..operation = ChangeOperation.create
        ..recordId = stockId
        ..data = jsonEncode({
          'id': stockId,
          'company_id': companyId,
          'product_id': productId,
          'date': stock.date.toIso8601String(),
          'movement_type': StockMovementType.inAdjustment.name,
          'quantity_delta': qty,
          'unit_cost': 0,
          'total_cost': 0,
          'transaction_id': null,
          'invoice_id': null,
        })
        ..createdAt = DateTime.now()
        ..synced = false);
    });
  }
}
