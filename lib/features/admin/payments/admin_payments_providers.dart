// lib/features/admin/payments/admin_payments_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int kPaymentsPageSize = 20;

class PaymentFilter {
  final String? status;   // null = all
  final String? provider; // null = all
  final String businessSearch;

  const PaymentFilter({this.status, this.provider, this.businessSearch = ''});

  PaymentFilter copyWith({
    Object? status = _sentinel,
    Object? provider = _sentinel,
    String? businessSearch,
  }) =>
      PaymentFilter(
        status: status == _sentinel ? this.status : status as String?,
        provider: provider == _sentinel ? this.provider : provider as String?,
        businessSearch: businessSearch ?? this.businessSearch,
      );

  @override
  bool operator ==(Object other) =>
      other is PaymentFilter &&
      other.status == status &&
      other.provider == provider &&
      other.businessSearch == businessSearch;

  @override
  int get hashCode => Object.hash(status, provider, businessSearch);
}

const _sentinel = Object();

final paymentFilterProvider = StateProvider<PaymentFilter>((_) => const PaymentFilter());
final paymentPageProvider = StateProvider<int>((_) => 0);

class PaymentListItem {
  final String id;
  final String businessId;
  final String businessName;
  final double amount;
  final String currency;
  final String status;
  final String provider;
  final String? reference;
  final DateTime createdAt;

  const PaymentListItem({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.provider,
    required this.reference,
    required this.createdAt,
  });
}

class PaymentListPage {
  final List<PaymentListItem> items;
  final int totalCount;
  const PaymentListPage({required this.items, required this.totalCount});
  static const empty = PaymentListPage(items: [], totalCount: 0);
  int get totalPages => (totalCount / kPaymentsPageSize).ceil().clamp(1, 1 << 30);
}

final paymentListProvider = FutureProvider.autoDispose<PaymentListPage>((ref) async {
  final filter = ref.watch(paymentFilterProvider);
  final page = ref.watch(paymentPageProvider);

  try {
    final client = Supabase.instance.client;

    // business_id filtering by name requires a join; PostgREST supports
    // filtering on an embedded resource's column directly.
    var query = client
        .from('payments')
        .select('id, business_id, amount, currency, status, provider, reference, created_at, businesses!inner(name)');

    if (filter.status != null) query = query.eq('status', filter.status!);
    if (filter.provider != null) query = query.eq('provider', filter.provider!);
    if (filter.businessSearch.trim().isNotEmpty) {
      query = query.ilike('businesses.name', '%${filter.businessSearch.trim()}%');
    }

    final from = page * kPaymentsPageSize;
    final to = from + kPaymentsPageSize - 1;

    final response = await query
        .order('created_at', ascending: false)
        .range(from, to)
        .count(CountOption.exact);

    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final items = rows.map((r) {
      final biz = r['businesses'] as Map<String, dynamic>?;
      return PaymentListItem(
        id: r['id'] as String,
        businessId: r['business_id'] as String,
        businessName: biz?['name'] as String? ?? 'Unknown',
        amount: (r['amount'] as num?)?.toDouble() ?? 0,
        currency: r['currency'] as String? ?? 'PHP',
        status: r['status'] as String? ?? 'pending',
        provider: r['provider'] as String? ?? 'manual',
        reference: r['reference'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
    }).toList();

    return PaymentListPage(items: items, totalCount: response.count);
  } catch (_) {
    return PaymentListPage.empty;
  }
});

// ── Business search, for the "Add manual payment" form's autocomplete ────

class BusinessOption {
  final String id;
  final String name;
  const BusinessOption(this.id, this.name);
}

final businessSearchProvider =
    FutureProvider.family.autoDispose<List<BusinessOption>, String>((ref, query) async {
  if (query.trim().length < 2) return [];
  try {
    final client = Supabase.instance.client;
    final rows = await client
        .from('businesses')
        .select('id, name')
        .ilike('name', '%${query.trim()}%')
        .order('name')
        .limit(10);
    return (rows as List)
        .map((r) => BusinessOption(r['id'] as String, r['name'] as String))
        .toList();
  } catch (_) {
    return [];
  }
});