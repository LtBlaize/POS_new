// lib/features/credits/credits_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/credit.dart';
import '../../core/providers/credit_provider.dart';
import '../../core/services/feature_manager.dart';
import 'widgets/pay_credit_dialog.dart';

// ── Breakpoint ────────────────────────────────────────────────────────────────
// < 900 px wide  → stacked / phone+portrait-tablet mode (master-detail via Navigator)
// ≥ 900 px wide  → side-by-side two-panel mode

class CreditsScreen extends ConsumerWidget {
  final FeatureManager featureManager;
  const CreditsScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      backgroundColor: Color(0xFF0B0E1A),
      body: _CreditsBody(),
    );
  }
}

// ── Body — picks layout based on available width ──────────────────────────────

class _CreditsBody extends ConsumerStatefulWidget {
  const _CreditsBody();

  @override
  ConsumerState<_CreditsBody> createState() => _CreditsBodyState();
}

class _CreditsBodyState extends ConsumerState<_CreditsBody> {
  String _search = '';
  CreditCustomer? _selected; // only used in two-panel mode

  static const _surface = Color(0xFF141827);
  static const _card = Color(0xFF1A1F35);
  static const _accent = Color(0xFFE94560);

  static const double _kBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTwoPanel = width >= _kBreakpoint;

    final customersAsync = ref.watch(creditCustomersProvider);

    return customersAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFE94560))),
      error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: Colors.white))),
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
        final withBalance = customers.where((c) => c.totalOwed > 0).length;

        // Build the customer list panel (shared between both layouts)
        final listPanel = _CustomerListPanel(
          customers: customers,
          filtered: filtered,
          totalOwed: totalOwed,
          withBalance: withBalance,
          search: _search,
          selectedId: _selected?.id,
          surfaceColor: _surface,
          cardColor: _card,
          accentColor: _accent,
          onSearchChanged: (v) => setState(() => _search = v),
          onCustomerTap: (c) {
            if (isTwoPanel) {
              setState(() => _selected = c);
            } else {
              // Push detail screen onto the local navigator
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _DetailPage(customer: c),
                ),
              );
            }
          },
        );

        if (isTwoPanel) {
          // ── Two-panel side-by-side ──────────────────────────────────
          final panelWidth = (width * 0.32).clamp(280.0, 380.0);
          return Row(
            children: [
              SizedBox(
                width: panelWidth,
                child: listPanel,
              ),
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
                        showBackButton: false,
                        onUpdated: (updated) =>
                            setState(() => _selected = updated),
                      ),
              ),
            ],
          );
        } else {
          // ── Single-column master list ───────────────────────────────
          return listPanel;
        }
      },
    );
  }
}

// ── Detail page wrapper (used in stacked / narrow mode) ──────────────────────

class _DetailPage extends ConsumerWidget {
  final CreditCustomer customer;
  const _DetailPage({required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for updated customer from provider so balance refreshes
    final customersAsync = ref.watch(creditCustomersProvider);
    final live = customersAsync.value
            ?.firstWhere((c) => c.id == customer.id, orElse: () => customer) ??
        customer;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E1A),
      body: _CustomerDetail(
        key: ValueKey(live.id),
        customer: live,
        showBackButton: true,
        onUpdated: (_) {
          ref.invalidate(creditCustomersProvider);
        },
      ),
    );
  }
}

// ── Customer list panel ───────────────────────────────────────────────────────

class _CustomerListPanel extends StatelessWidget {
  final List<CreditCustomer> customers;
  final List<CreditCustomer> filtered;
  final double totalOwed;
  final int withBalance;
  final String search;
  final String? selectedId;
  final Color surfaceColor;
  final Color cardColor;
  final Color accentColor;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<CreditCustomer> onCustomerTap;

  const _CustomerListPanel({
    required this.customers,
    required this.filtered,
    required this.totalOwed,
    required this.withBalance,
    required this.search,
    required this.selectedId,
    required this.surfaceColor,
    required this.cardColor,
    required this.accentColor,
    required this.onSearchChanged,
    required this.onCustomerTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: surfaceColor,
      child: Column(
        children: [
          // ── Top bar ────────────────────────────────────────────────
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
                      color: Colors.white.withOpacity(0.4), fontSize: 12),
                ),
                const SizedBox(height: 16),

                // Total outstanding chip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: accentColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Outstanding',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 12)),
                      Text(
                        '₱${NumberFormat('#,##0.00', 'en_PH').format(totalOwed)}',
                        style: TextStyle(
                            color: accentColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Search
                TextField(
                  onChanged: onSearchChanged,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search name or phone…',
                    hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 13),
                    prefixIcon: Icon(Icons.search,
                        color: Colors.white.withOpacity(0.3), size: 18),
                    filled: true,
                    fillColor: cardColor,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
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

          // ── Customer list ──────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      search.isEmpty
                          ? 'No customers yet.\nAdd utang at checkout.'
                          : 'No results',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.25),
                          fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return _CustomerTile(
                        customer: c,
                        selected: selectedId == c.id,
                        onTap: () => onCustomerTap(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
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
            // Arrow hint on narrow screens (no selectedId concept)
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
  final bool showBackButton;
  final ValueChanged<CreditCustomer> onUpdated;

  const _CustomerDetail({
    super.key,
    required this.customer,
    required this.showBackButton,
    required this.onUpdated,
  });

  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(creditTransactionsProvider(customer.id));
    final screenWidth = MediaQuery.of(context).size.width;
    // On very narrow screens the header row wraps into two rows
    final narrowHeader = screenWidth < 500;

    return Container(
      color: const Color(0xFF0B0E1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
              showBackButton ? 8 : 28,
              24,
              28,
              20,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF141827),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
            ),
            child: narrowHeader
                ? _NarrowHeader(
                    customer: customer,
                    showBackButton: showBackButton,
                    onPayPressed: () =>
                        _handlePay(context, ref),
                  )
                : _WideHeader(
                    customer: customer,
                    showBackButton: showBackButton,
                    onPayPressed: () =>
                        _handlePay(context, ref),
                  ),
          ),

          // ── Transaction list label ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
            child: Text('Transaction History',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600)),
          ),

          // ── Transactions ──────────────────────────────────────────
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
                      padding:
                          const EdgeInsets.fromLTRB(28, 0, 28, 24),
                      itemCount: txs.length,
                      separatorBuilder: (_, _) =>
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

  Future<void> _handlePay(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => PayCreditDialog(customer: customer),
    );
    if (result == true) {
      ref.invalidate(creditCustomersProvider);
      ref.invalidate(creditTransactionsProvider(customer.id));
      final updated = ref
          .read(creditCustomersProvider)
          .value
          ?.firstWhere((c) => c.id == customer.id,
              orElse: () => customer);
      if (updated != null) onUpdated(updated);
    }
  }
}

// ── Header variants ───────────────────────────────────────────────────────────

/// Wide header: avatar | name+phone | balance | pay button — all in one row
class _WideHeader extends StatelessWidget {
  final CreditCustomer customer;
  final bool showBackButton;
  final VoidCallback onPayPressed;

  const _WideHeader({
    required this.customer,
    required this.showBackButton,
    required this.onPayPressed,
  });

  static const _accent = Color(0xFFE94560);
  static const _green = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBackButton)
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Balance',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 11)),
            Text(
              '₱${NumberFormat('#,##0.00').format(customer.totalOwed)}',
              style: TextStyle(
                color: customer.totalOwed > 0 ? _accent : _green,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        if (customer.totalOwed > 0) ...[
          const SizedBox(width: 20),
          ElevatedButton.icon(
            onPressed: onPayPressed,
            icon: const Icon(Icons.payments_outlined, size: 16),
            label: const Text('Record Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ],
    );
  }
}

/// Narrow header: two-row layout for phones / portrait tablets
/// Row 1: [back] avatar | name+phone | balance
/// Row 2: pay button full-width
class _NarrowHeader extends StatelessWidget {
  final CreditCustomer customer;
  final bool showBackButton;
  final VoidCallback onPayPressed;

  const _NarrowHeader({
    required this.customer,
    required this.showBackButton,
    required this.onPayPressed,
  });

  static const _accent = Color(0xFFE94560);
  static const _green = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1
        Row(
          children: [
            if (showBackButton)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white70, size: 18),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            if (showBackButton) const SizedBox(width: 8),
            CircleAvatar(
              radius: 22,
              backgroundColor: _accent.withOpacity(0.15),
              child: Text(
                customer.name[0].toUpperCase(),
                style: const TextStyle(
                    color: _accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(customer.phone,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Balance',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 10)),
                Text(
                  '₱${NumberFormat('#,##0.00').format(customer.totalOwed)}',
                  style: TextStyle(
                    color: customer.totalOwed > 0 ? _accent : _green,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),

        // Row 2 — pay button
        if (customer.totalOwed > 0) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPayPressed,
              icon: const Icon(Icons.payments_outlined, size: 16),
              label: const Text('Record Payment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ],
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

    // Settlement badge
    Widget? badge;
    if (isCredit) {
      if (tx.isSettled) {
        badge = _Badge(label: 'Paid', color: const Color(0xFF10B981));
      } else if (tx.isPartiallyPaid) {
        badge = _Badge(
          label: '₱${tx.amountPaid.toStringAsFixed(2)} paid',
          color: const Color(0xFFF59E0B),
        );
      } else {
        badge = _Badge(label: 'Unpaid', color: const Color(0xFFE94560));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F35),
        borderRadius: BorderRadius.circular(10),
        border: isCredit && tx.isSettled
            ? Border.all(
                color: const Color(0xFF10B981).withOpacity(0.2))
            : null,
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
                Row(
                  children: [
                    Text(
                      isCredit ? 'Utang' : 'Payment',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      badge,
                    ],
                  ],
                ),
                if (tx.note != null)
                  Text(tx.note!,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 11)),
                if (isCredit && tx.isPartiallyPaid)
                  Text(
                    '₱${tx.amountRemaining!.toStringAsFixed(2)} remaining',
                    style: const TextStyle(
                        color: Color(0xFFF59E0B), fontSize: 11),
                  ),
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

// ── Badge ─────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
    );
  }
}