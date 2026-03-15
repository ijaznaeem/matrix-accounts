import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:veyo_sync/core/config/providers.dart';
import 'package:veyo_sync/core/database/dao/party_dao.dart';
import 'package:veyo_sync/core/database/dao/product_master_dao.dart';
import 'package:veyo_sync/data/models/company_model.dart';
import 'package:veyo_sync/data/models/inventory_models.dart';
import 'package:veyo_sync/data/models/party_model.dart';
import 'package:veyo_sync/features/inventory/logic/product_master_provider.dart';
import 'package:veyo_sync/features/parties/logic/party_provider.dart';

class _FakeProductMasterDao implements ProductMasterDao {
  _FakeProductMasterDao({
    required this.productsByCompany,
    required this.categoriesByCompany,
  });

  final Map<int, List<Product>> productsByCompany;
  final Map<int, List<ItemCategory>> categoriesByCompany;

  @override
  Isar get isar => throw UnimplementedError();

  @override
  Future<List<Product>> getProductsByCompany(int companyId) async {
    return productsByCompany[companyId] ?? <Product>[];
  }

  @override
  Future<List<ItemCategory>> getCategories(int companyId) async {
    return categoriesByCompany[companyId] ?? <ItemCategory>[];
  }

  @override
  Future<List<UnitOfMeasure>> getUnits() async => <UnitOfMeasure>[];

  @override
  Future<void> saveProduct(Product product) async {}

  @override
  Future<void> saveCategory(ItemCategory category) async {}

  @override
  Future<void> deleteCategory(int id) async {}

  @override
  Future<void> saveUnit(UnitOfMeasure unit) async {}

  @override
  Future<void> insertOpeningStock({
    required int companyId,
    required int productId,
    required double qty,
  }) async {}
}

class _FakePartyDao implements PartyDao {
  _FakePartyDao({required this.partiesByCompany});

  final Map<int, List<Party>> partiesByCompany;
  int getAllByCompanyCallCount = 0;

  @override
  Isar get isar => throw UnimplementedError();

  @override
  Future<void> deleteParty(int id) async {}

  @override
  Future<void> ensureOpeningBalanceLedgerEntries(int companyId) async {}

  @override
  Future<List<Party>> getAllByCompany(int companyId) async {
    getAllByCompanyCallCount++;
    return partiesByCompany[companyId] ?? <Party>[];
  }

  @override
  Future<double> getPartyBalance({
    required int partyId,
    required int companyId,
  }) async =>
      0;

  @override
  Future<void> saveParty(Party party) async {}

  @override
  Future<void> updatePartyOpeningBalance({
    required int partyId,
    required int companyId,
    required double openingBalance,
    DateTime? asOfDate,
  }) async {}
}

Company _company(int id, String name) {
  return Company()
    ..id = id
    ..subscriberId = 1
    ..name = name
    ..primaryCurrency = 'PKR'
    ..financialYearStartMonth = 1
    ..isActive = true;
}

Product _product(int id, int companyId, String name) {
  return Product()
    ..id = id
    ..companyId = companyId
    ..name = name
    ..sku = 'SKU-$id';
}

ItemCategory _category(int id, int companyId, String name) {
  return ItemCategory()
    ..id = id
    ..companyId = companyId
    ..name = name;
}

Party _party(int id, int companyId, String name) {
  return Party()
    ..id = id
    ..companyId = companyId
    ..name = name
    ..partyType = PartyType.customer;
}

void main() {
  test('productListProvider returns products only for selected company',
      () async {
    final fakeDao = _FakeProductMasterDao(
      productsByCompany: {
        1: [_product(101, 1, 'Company A Product')],
        2: [_product(201, 2, 'Company B Product')],
      },
      categoriesByCompany: {},
    );

    final container = ProviderContainer(
      overrides: [
        productMasterDaoProvider.overrideWithValue(fakeDao),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentCompanyProvider.notifier).state = _company(1, 'A Co');

    final companyAProducts = await container.read(productListProvider.future);
    expect(companyAProducts, hasLength(1));
    expect(companyAProducts.first.companyId, 1);
    expect(companyAProducts.first.name, 'Company A Product');

    container.read(currentCompanyProvider.notifier).state = _company(2, 'B Co');

    final companyBProducts = await container.read(productListProvider.future);
    expect(companyBProducts, hasLength(1));
    expect(companyBProducts.first.companyId, 2);
    expect(companyBProducts.first.name, 'Company B Product');
    expect(companyBProducts.any((p) => p.companyId == 1), isFalse);
  });

  test('productCategoryProvider returns categories only for selected company',
      () async {
    final fakeDao = _FakeProductMasterDao(
      productsByCompany: {},
      categoriesByCompany: {
        1: [_category(11, 1, 'A Category')],
        2: [_category(22, 2, 'B Category')],
      },
    );

    final container = ProviderContainer(
      overrides: [
        productMasterDaoProvider.overrideWithValue(fakeDao),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentCompanyProvider.notifier).state = _company(1, 'A Co');

    final companyACategories =
        await container.read(productCategoryProvider.future);
    expect(companyACategories, hasLength(1));
    expect(companyACategories.first.companyId, 1);

    container.read(currentCompanyProvider.notifier).state = _company(2, 'B Co');

    final companyBCategories =
        await container.read(productCategoryProvider.future);
    expect(companyBCategories, hasLength(1));
    expect(companyBCategories.first.companyId, 2);
    expect(companyBCategories.any((c) => c.companyId == 1), isFalse);
  });

  test('partyListProvider returns parties only for selected company', () async {
    final fakeDao = _FakePartyDao(
      partiesByCompany: {
        1: [_party(1, 1, 'Company A Party')],
        2: [_party(2, 2, 'Company B Party')],
      },
    );

    final container = ProviderContainer(
      overrides: [
        partyDaoProvider.overrideWithValue(fakeDao),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentCompanyProvider.notifier).state = _company(1, 'A Co');

    final companyAParties = await container.read(partyListProvider.future);
    expect(companyAParties, hasLength(1));
    expect(companyAParties.first.companyId, 1);
    expect(companyAParties.first.name, 'Company A Party');

    container.read(currentCompanyProvider.notifier).state = _company(2, 'B Co');

    final companyBParties = await container.read(partyListProvider.future);
    expect(companyBParties, hasLength(1));
    expect(companyBParties.first.companyId, 2);
    expect(companyBParties.first.name, 'Company B Party');
    expect(companyBParties.any((party) => party.companyId == 1), isFalse);
  });

  test('partyListProvider refreshes when the refresh trigger changes',
      () async {
    final fakeDao = _FakePartyDao(
      partiesByCompany: {
        1: [_party(1, 1, 'Company A Party')],
      },
    );

    final container = ProviderContainer(
      overrides: [
        partyDaoProvider.overrideWithValue(fakeDao),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentCompanyProvider.notifier).state = _company(1, 'A Co');

    await container.read(partyListProvider.future);
    expect(fakeDao.getAllByCompanyCallCount, 1);

    container.read(partyListRefreshProvider.notifier).state++;
    await container.read(partyListProvider.future);

    expect(fakeDao.getAllByCompanyCallCount, 2);
  });
}
