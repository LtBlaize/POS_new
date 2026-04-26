// lib/core/providers/credit_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/credit.dart';
import '../services/credit_service.dart';
import '../../features/auth/auth_provider.dart';

final creditCustomersProvider =
    AsyncNotifierProvider<CreditCustomersNotifier, List<CreditCustomer>>(
        CreditCustomersNotifier.new);

class CreditCustomersNotifier extends AsyncNotifier<List<CreditCustomer>> {
  @override
  Future<List<CreditCustomer>> build() async {
    final profile = ref.watch(profileProvider).value;
    if (profile == null) return [];
    final businessId = profile.businessId;
    if (businessId == null) return [];
    return ref.read(creditServiceProvider).getCustomers(businessId);
  }

  String get _businessId {
    final id = ref.read(profileProvider).value?.businessId;
    if (id == null) throw Exception('No business linked to profile');
    return id;
  }

  Future<CreditCustomer> findOrCreate({
    required String name,
    required String phone,
  }) async {
    final businessId = _businessId;
    final svc = ref.read(creditServiceProvider);
    var customer = await svc.findCustomerByPhone(businessId, phone);
    customer ??= await svc.createCustomer(
      businessId: businessId,
      name: name,
      phone: phone,
    );
    ref.invalidateSelf();
    return customer;
  }

  Future<void> addCredit({
    required String customerId,
    required double amount,
    String? note,
    String? orderId,
  }) async {
    await ref.read(creditServiceProvider).addCredit(
          customerId: customerId,
          businessId: _businessId, // ← now passed correctly
          amount: amount,
          note: note,
          orderId: orderId,
        );
    ref.invalidateSelf();
  }

  Future<void> recordPayment({
    required String customerId,
    required double amount,
    String? note,
  }) async {
    await ref.read(creditServiceProvider).recordPayment(
          customerId: customerId,
          businessId: _businessId, // ← now passed correctly
          amount: amount,
          note: note,
        );
    ref.invalidateSelf();
  }
}

final creditTransactionsProvider =
    FutureProvider.family<List<CreditTransaction>, String>(
        (ref, customerId) async {
  return ref.read(creditServiceProvider).getTransactions(customerId);
});