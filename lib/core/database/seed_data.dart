// ignore_for_file: unused_local_variable, avoid_print

import 'package:isar/isar.dart';

import '../../data/models/company_model.dart';
import '../../data/models/inventory_models.dart';
import '../../data/models/party_model.dart';

class SeedData {
  final Isar isar;

  SeedData(this.isar);

  Future<void> seedAll({bool force = false}) async {
    // Only seed reference data (units of measure) if not already present
    final existingUnits = await isar.unitOfMeasures.count();
    if (existingUnits > 0 && !force) {
      return;
    }
    await _seedUnitsOfMeasure();
  }

  Future<void> _seedUnitsOfMeasure() async {
    await isar.writeTxn(() async {
      final units = [
        UnitOfMeasure()
          ..name = 'Piece'
          ..abbrev = 'Pcs',
        UnitOfMeasure()
          ..name = 'Kilogram'
          ..abbrev = 'Kg',
        UnitOfMeasure()
          ..name = 'Gram'
          ..abbrev = 'g',
      ];

      for (final unit in units) {
        await isar.unitOfMeasures.put(unit);
      }
    });

    print('✓ Units of measure seeded');
  }

  Future<void> clearAllData() async {
    await isar.writeTxn(() async {
      await isar.companys.clear();
      await isar.partys.clear();
      await isar.products.clear();
      await isar.itemCategorys.clear();
      await isar.unitOfMeasures.clear();
    });
    print('✓ All data cleared');
  }
}
