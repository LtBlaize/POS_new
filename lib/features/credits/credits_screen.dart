// lib/features/credits/credits_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/credit.dart';
import '../../core/providers/credit_provider.dart';
import '../../core/services/feature_manager.dart';
import 'widgets/pay_credit_dialog.dart';

class CreditsScreen extends ConsumerWidget {
  final FeatureManager featureManager;
  const CreditsScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _CreditsBody();
  }
}

class _CreditsBody extends ConsumerStatefulWidget {
  const _CreditsBody();

  @override
  ConsumerState<_CreditsBody> createState() => _CreditsBodyState();
}

class _CreditsBodyState extends ConsumerState<_CreditsBody> {
  String _search = '';
  CreditCustomer? _selected;

  
  static const _surface = Color(0xFF141827);
  static const _card = Color(0xFF1A1F35);
  static const _accent = Color(0xFFE94560);
 

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(creditCustomersProvider);

    return customersAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFE94560))),
      error: (e, _) =>
          Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
      data: (customers) {
        final filtered = _search.isEmpty
            ? customers
            : customers
                .where((c) =>
                    c.name.toLowerCase().contains(_search.toLowerCase()) ||
                    c.phone.contains(_search))
                .toList();

        final totalOwed =
            customers.fold<double>(0, (s, c) => s + c.totalOwed);
        final withBalance =
            customers.where((c) => c.totalOwed > 0).length;

        return Row(
          children: [
            // ── LEFT: Customer list ──────────────────────────────────────
            SizedBox(
              width: 340,
              child: Container(
                color: _surface,
                child: Column(
                  children: [
                    // Top bar
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Utang / Credit',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            '${customers.length} customers · $withBalance with balance',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12),
                          ),
                          const SizedBox(height: 16),

                          // Total owed summary chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _accent.withOpacity(0.2)),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Outstanding',
                                    style: TextStyle(
                                        color:
                                            Colors.white.withOpacity(0.55),
                                        fontSize: 12)),
                                Text(
                                  '₱${_fmt(totalOwed)}',
                                  style: const TextStyle(
                                      color: _accent,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Search
                          TextField(
                            onChanged: (v) =>
                                setState(() => _search = v),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search name or phone…',
                              hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.25),
                                  fontSize: 13),
                              prefixIcon: Icon(Icons.search,
                                  color: Colors.white.withOpacity(0.3),
                                  size: 18),
                              filled: true,
                              fillColor: _card,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),

                    // Customer list
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _search.isEmpty
                                    ? 'No customers yet.\nAdd utang at checkout.'
                                    : 'No results',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.25),
                                    fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 0, 12, 12),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (_, i) {
                                final c = filtered[i];
                                final isSelected =
                                    _selected?.id == c.id;
                                return _CustomerTile(
                                  customer: c,
                                  selected: isSelected,
                                  onTap: () =>
                                      setState(() => _selected = c),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // ── RIGHT: Customer detail ───────────────────────────────────
            Expanded(
              child: _selected == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_search_outlined,
                              size: 48,
                              color: Colors.white.withOpacity(0.1)),
                          const SizedBox(height: 12),
                          Text('Select a customer to view details',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.2),
                                  fontSize: 13)),
                        ],
                      ),
                    )
                  : _CustomerDetail(
                      key: ValueKey(_selected!.id),
                      customer: _selected!,
                      onUpdated: (updated) =>
                          setState(() => _selected = updated),
                    ),
            ),
          ],
        );
      },
    );
  }

  String _fmt(double v) =>
      NumberFormat('#,##0.00', 'en_PH').format(v);
}

// ── Customer tile ─────────────────────────────────────────────────────────────

class _CustomerTile extends StatelessWidget {
  final CreditCustomer customer;
  final bool selected;
  final VoidCallback onTap;

  const _CustomerTile({
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasBalance = customer.totalOwed > 0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE94560).withOpacity(0.12)
              : const Color(0xFF1A1F35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFFE94560).withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: hasBalance
                  ? const Color(0xFFE94560).withOpacity(0.15)
                  : const Color(0xFF10B981).withOpacity(0.15),
              child: Text(
                customer.name[0].toUpperCase(),
                style: TextStyle(
                  color: hasBalance
                      ? const Color(0xFFE94560)
                      : const Color(0xFF10B981),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  Text(customer.phone,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 11)),
                ],
              ),
            ),
            if (hasBalance)
              Text(
                '₱${NumberFormat('#,##0.00').format(customer.totalOwed)}',
                style: const TextStyle(
                    color: Color(0xFFE94560),
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              )
            else
              const Icon(Icons.check_circle,
                  color: Color(0xFF10B981), size: 16),
          ],
        ),
      ),
    );
  }
}

// ── Customer detail ───────────────────────────────────────────────────────────

class _CustomerDetail extends ConsumerWidget {
  final CreditCustomer customer;
  final ValueChanged<CreditCustomer> onUpdated;

  const _CustomerDetail({
    super.key,
    required this.customer,
    required this.onUpdated,
  });

  static const _accent = Color(0xFFE94560);
  static const _green = Color(0xFF10B981);
  

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync =
        ref.watch(creditTransactionsProvider(customer.id));

    return Container(
      color: const Color(0xFF0B0E1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            decoration: BoxDecoration(
              color: const Color(0xFF141827),
              border: Border(
                bottom: BorderSide(
                    color: Colors.white.withOpacity(0.06)),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _accent.withOpacity(0.15),
                  child: Text(
                    customer.name[0].toUpperCase(),
                    style: const TextStyle(
                        color: _accent,
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      Text(customer.phone,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 13)),
                    ],
                  ),
                ),

                // Balance badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Balance',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11)),
                    Text(
                      '₱${NumberFormat('#,##0.00').format(customer.totalOwed)}',
                      style: TextStyle(
                        color: customer.totalOwed > 0
                            ? _accent
                            : _green,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),

                // Pay button
                if (customer.totalOwed > 0)
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            PayCreditDialog(customer: customer),
                      );
                      if (result == true) {
                        // refresh the customers list to get updated balance
                        ref.invalidate(creditCustomersProvider);
                        ref.invalidate(
                            creditTransactionsProvider(customer.id));
                        // find updated customer
                        final updated = ref
                            .read(creditCustomersProvider)
                            .value
                            ?.firstWhere((c) => c.id == customer.id,
                                orElse: () => customer);
                        if (updated != null) onUpdated(updated);
                      }
                    },
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('Record Payment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ],
            ),
          ),

          // ── Transaction list ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
            child: Text('Transaction History',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600)),
          ),

          Expanded(
            child: txAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFFE94560))),
              error: (e, _) => Center(
                  child: Text('$e',
                      style: const TextStyle(color: Colors.white))),
              data: (txs) => txs.isEmpty
                  ? Center(
                      child: Text('No transactions yet',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.2),
                              fontSize: 13)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          28, 0, 28, 24),
                      itemCount: txs.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) =>
                          _TxTile(tx: txs[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transaction tile ──────────────────────────────────────────────────────────

class _TxTile extends StatelessWidget {
  final CreditTransaction tx;
  const _TxTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.type == CreditTxType.credit;
    final color =
        isCredit ? const Color(0xFFE94560) : const Color(0xFF10B981);
    final sign = isCredit ? '+' : '-';
    final icon = isCredit
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCredit ? 'Utang' : 'Payment',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                if (tx.note != null)
                  Text(tx.note!,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 11)),
                Text(
                  DateFormat('MMM d, y · h:mm a').format(tx.createdAt),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.25),
                      fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            '$sign₱${NumberFormat('#,##0.00').format(tx.amount)}',
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}