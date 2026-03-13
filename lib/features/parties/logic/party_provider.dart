import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/database/dao/party_dao.dart';
import '../../../data/models/party_model.dart';

final partyDaoProvider = Provider<PartyDao>((ref) {
  final isar = ref.read(isarServiceProvider).isar;
  return PartyDao(isar);
});

final partyListRefreshProvider = StateProvider<int>((ref) => 0);

final partyListProvider = FutureProvider<List<Party>>((ref) async {
  ref.watch(partyListRefreshProvider);
  final dao = ref.read(partyDaoProvider);
  final company = ref.watch(currentCompanyProvider);
  if (company == null) return [];
  await dao.ensureOpeningBalanceLedgerEntries(company.id);
  return dao.getAllByCompany(company.id);
});
