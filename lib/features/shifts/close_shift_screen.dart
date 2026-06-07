// lib/features/shifts/close_shift_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/shift.dart';
import '../../core/providers/shift_provider.dart';
import '../../core/services/shift_service.dart';

final _liveExpensesProvider = StateProvider<double>((ref) => 0);

class CloseShiftScreen extends ConsumerStatefulWidget {
  final VoidCallback onShiftClosed;
  final VoidCallback onCancel;

  const CloseShiftScreen({
    super.key,
    required this.onShiftClosed,
    required this.onCancel,
  });

  @override
  ConsumerState<CloseShiftScreen> createState() =>
      _CloseShiftScreenState();
}

class _CloseShiftScreenState extends ConsumerState<CloseShiftScreen> {
  final _actualCashCtrl = TextEditingController(text: '0.00');
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  bool _confirming = false;
  String? _error;
  CashierShift? _closedShift;

  static const _bg = Color(0xFF0B0E1A);
  static const _card = Color(0xFF141827);
  static const _surface = Color(0xFF1A1F35);
  static const _accent = Color(0xFFE94560);

  double get _actualCash =>
      double.tryParse(_actualCashCtrl.text.replaceAll(',', '')) ?? 0;

  Future<void> _closeShift(CashierShift shift) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final closed =
          await ref.read(currentShiftProvider.notifier).closeShift(
                actualCashCount: _actualCash,
                notes: _notesCtrl.text.trim().isEmpty
                    ? null
                    : _notesCtrl.text.trim(),
              );
      setState(() {
        _closedShift = closed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to close shift. Try again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _actualCashCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftAsync = ref.watch(currentShiftProvider);

    if (_closedShift != null) {
      return _ShiftReceiptView(
        shift: _closedShift!,
        onDone: widget.onShiftClosed,
      );
    }

    return shiftAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0B0E1A),
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFFE94560))),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: _bg,
        body: Center(
            child: Text('$e',
                style: const TextStyle(color: Colors.white))),
      ),
      data: (shift) {
        if (shift == null) {
          return Scaffold(
            backgroundColor: _bg,
            body: Center(
              child: Text('No open shift found.',
                  style:
                      TextStyle(color: Colors.white.withValues(alpha:0.4))),
            ),
          );
        }
        return _buildCloseForm(shift);
      },
    );
  }

  Widget _buildCloseForm(CashierShift shift) {
    final duration = DateTime.now().difference(shift.openedAt);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: widget.onCancel,
        ),
        title: const Text('Close Shift',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child:
              Divider(height: 1, color: Colors.white.withValues(alpha:0.06)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ShiftInfoBanner(
                  shift: shift, hours: hours, minutes: minutes),
              const SizedBox(height: 20),

              _SectionTitle(title: 'SALES SUMMARY'),
              const SizedBox(height: 10),
              // NOTE: totals are estimated from live orders — final totals
              // are computed at close time by shift_service.dart
              _SalesSummaryCard(shift: shift),
              const SizedBox(height: 20),

              _SectionTitle(title: 'EXPENSES'),
              const SizedBox(height: 10),
              _ExpensesCard(shiftId: shift.id),
              const SizedBox(height: 20),

              _SectionTitle(title: 'CASH RECONCILIATION'),
              const SizedBox(height: 10),
              Consumer(
                builder: (context, ref, _) {
                  final liveExpenses = ref.watch(_liveExpensesProvider);
                  return _CashReconciliationCard(
                    shift: shift,
                    liveExpenses: liveExpenses,
                    actualCashCtrl: _actualCashCtrl,
                    actualCash: _actualCash,
                    onChanged: () => setState(() {}),
                  );
                },
              ),
              const SizedBox(height: 20),

              Consumer(
                builder: (context, ref, _) {
                  final liveExpenses = ref.watch(_liveExpensesProvider);
                  return _OverShortPreview(
                    expectedCash: shift.openingCash +
                        shift.cashSales -
                        liveExpenses,
                    actualCash: _actualCash,
                  );
                },
              ),
              const SizedBox(height: 20),

              _SectionTitle(title: 'NOTES (OPTIONAL)'),
              const SizedBox(height: 10),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText:
                      'Any notes for this shift (e.g. equipment issues, incidents)',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha:0.25),
                      fontSize: 13),
                  filled: true,
                  fillColor: _surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: _accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 24),

              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: _accent.withValues(alpha:0.3)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: _accent, fontSize: 13)),
                ),

              if (!_confirming)
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _confirming = true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_rounded, size: 18),
                              SizedBox(width: 10),
                              Text('Close Shift',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: _accent.withValues(alpha:0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: _accent, size: 32),
                      const SizedBox(height: 10),
                      const Text('Close this shift?',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'This cannot be undone. Make sure all sales are recorded.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha:0.45),
                            fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _confirming = false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white54,
                                side: BorderSide(
                                    color:
                                        Colors.white.withValues(alpha:0.15)),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _loading
                                  ? null
                                  : () => _closeShift(shift),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Text('Yes, Close Shift',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shift Info Banner ─────────────────────────────────────────────────────────

class _ShiftInfoBanner extends StatelessWidget {
  final CashierShift shift;
  final int hours;
  final int minutes;

  const _ShiftInfoBanner(
      {required this.shift,
      required this.hours,
      required this.minutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha:0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE94560).withValues(alpha:0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_outline,
                color: Color(0xFFE94560), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shift.staffName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text(
                  'Opened ${DateFormat('MMM d · h:mm a').format(shift.openedAt)}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha:0.35),
                      fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${hours}h ${minutes}m',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              Text('shift duration',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha:0.3),
                      fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sales Summary Card ────────────────────────────────────────────────────────
// FIX: labels now match shift_service.dart grouping:
//   gcashSales = GCash + Maya + E-Wallet
//   otherSales = Card + anything else

class _SalesSummaryCard extends StatelessWidget {
  final CashierShift shift;

  const _SalesSummaryCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha:0.06)),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Total Sales',
            value: shift.totalSales,
            color: Colors.white,
            isBold: true,
          ),
          const _Divider(),

          // Cash
          _SummaryRow(
            label: 'Cash',
            icon: Icons.payments_outlined,
            value: shift.cashSales,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(height: 8),

          // GCash / Maya / E-Wallet (grouped)
          _SummaryRow(
            label: 'GCash / Maya / E-Wallet',
            icon: Icons.phone_android_outlined,
            value: shift.gcashSales,
            color: const Color(0xFF3B82F6),
            subtitle: 'Includes GCash & Maya',
          ),
          const SizedBox(height: 8),

          // Card / Other
          _SummaryRow(
            label: 'Card / Other',
            icon: Icons.credit_card_outlined,
            value: shift.otherSales,
            color: const Color(0xFF8B5CF6),
            subtitle: 'Includes Card Payments',
          ),
         

          // REPLACE
          if (shift.creditGiven > 0 || shift.creditsPaid > 0) ...[
            const _Divider(),
            if (shift.creditGiven > 0)
              _SummaryRow(
                label: 'Utang Given',
                icon: Icons.receipt_long_outlined,
                value: shift.creditGiven,
                color: const Color(0xFFE94560),
                prefix: '+',
              ),
            if (shift.creditsPaid > 0) ...[
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Utang Collected',
                icon: Icons.payments_outlined,
                value: shift.creditsPaid,
                color: const Color(0xFF10B981),
                prefix: '+',
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Cash Reconciliation ───────────────────────────────────────────────────────

class _CashReconciliationCard extends StatelessWidget {
  final CashierShift shift;
  final double liveExpenses;
  final TextEditingController actualCashCtrl;
  final double actualCash;
  final VoidCallback onChanged;

  const _CashReconciliationCard({
    required this.shift,
    required this.liveExpenses,
    required this.actualCashCtrl,
    required this.actualCash,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha:0.06)),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Opening Cash',
            icon: Icons.account_balance_wallet_outlined,
            value: shift.openingCash,
            color: Colors.white70,
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Cash Sales',
            icon: Icons.add_circle_outline,
            value: shift.cashSales,
            color: const Color(0xFF10B981),
            prefix: '+',
          ),
          const _Divider(),
          if (liveExpenses > 0) ...[
            _SummaryRow(
              label: 'Expenses',
              icon: Icons.remove_circle_outline,
              value: liveExpenses,
              color: const Color(0xFFE94560),
              prefix: '−',
            ),
            const _Divider(),
          ],
          _SummaryRow(
            label: 'Expected in Drawer',
            value: shift.openingCash + shift.cashSales - liveExpenses,
            color: Colors.white,
            isBold: true,
          ),
          const SizedBox(height: 16),

          // Actual cash input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFE94560).withValues(alpha:0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTUAL CASH COUNT',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha:0.35),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('₱',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha:0.4),
                            fontSize: 24)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: actualCashCtrl,
                        onChanged: (_) => onChanged(),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.]')),
                        ],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '0.00',
                          hintStyle: TextStyle(
                              color: Color(0xFF374151), fontSize: 28),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Count the physical bills and coins in the drawer',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha:0.25),
                      fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Over/Short Preview ────────────────────────────────────────────────────────

class _OverShortPreview extends StatelessWidget {
  final double expectedCash;
  final double actualCash;

  const _OverShortPreview(
      {required this.expectedCash, required this.actualCash});

  @override
  Widget build(BuildContext context) {
    final diff = actualCash - expectedCash;
    final isOver = diff > 0;
    final isExact = diff == 0;
    final color = isExact
        ? const Color(0xFF10B981)
        : isOver
            ? const Color(0xFF3B82F6)
            : const Color(0xFFE94560);
    final label = isExact ? 'Exact' : isOver ? 'Over' : 'Short';
    final icon = isExact
        ? Icons.check_circle_outline
        : isOver
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          Text(
            '${diff >= 0 ? '+' : ''}₱${NumberFormat('#,##0.00').format(diff.abs())}',
            style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ── Shift Receipt View ────────────────────────────────────────────────────────
// FIX: labels updated to match shift_service.dart grouping

class _ShiftReceiptView extends StatelessWidget {
  final CashierShift shift;
  final VoidCallback onDone;

  static const _bg = Color(0xFF0B0E1A);
  static const _card = Color(0xFF141827);
  static const _accent = Color(0xFFE94560);
  static const _green = Color(0xFF10B981);

  const _ShiftReceiptView({required this.shift, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final diff = shift.overShort;
    final overShortColor = diff == 0
        ? _green
        : diff > 0
            ? const Color(0xFF3B82F6)
            : _accent;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Shift Report',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        actions: [
          TextButton.icon(
            onPressed: onDone,
            icon: const Icon(Icons.check, color: Color(0xFF10B981)),
            label: const Text('Done',
                style: TextStyle(color: Color(0xFF10B981))),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Success banner ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha:0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _green.withValues(alpha:0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha:0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          color: _green, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Shift Closed',
                              style: TextStyle(
                                  color: _green,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          Text(
                            DateFormat('MMM d, y · h:mm a')
                                .format(shift.closedAt!),
                            style: TextStyle(
                                color: Colors.white.withValues(alpha:0.35),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Receipt card ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withValues(alpha:0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cashier info
                    Center(
                      child: Column(
                        children: [
                          Text(
                            shift.staffName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${DateFormat('h:mm a').format(shift.openedAt)} – ${DateFormat('h:mm a').format(shift.closedAt!)}',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha:0.35),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ReceiptDivider(),

                    // ── Sales breakdown ──────────────────────────────
                    const SizedBox(height: 16),
                    _ReceiptLabel('SALES'),
                    const SizedBox(height: 10),
                    _ReceiptRow('Total Sales', shift.totalSales,
                        bold: true),
                    // FIX: labels match shift_service.dart grouping
                    _ReceiptRow('  Cash', shift.cashSales,
                        color: _green),
                    _ReceiptRow(
                        '  GCash / Maya / E-Wallet', shift.gcashSales,
                        color: const Color(0xFF3B82F6)),
                    _ReceiptRow('  Card / Other', shift.otherSales,
                        color: const Color(0xFF8B5CF6)),
                    // REPLACE
                    if (shift.creditGiven > 0)
                      _ReceiptRow('  Utang Given', shift.creditGiven,
                          color: _accent, prefix: '+'),
                    if (shift.creditsPaid > 0)
                      _ReceiptRow('  Utang Collected', shift.creditsPaid,
                          color: _green, prefix: '+'),

                    const SizedBox(height: 16),
                    _ReceiptDivider(),

                    // ── Cash reconciliation ──────────────────────────
                    const SizedBox(height: 16),
                    _ReceiptLabel('CASH RECONCILIATION'),
                    const SizedBox(height: 10),
                    _ReceiptRow('Opening Cash', shift.openingCash),
                    _ReceiptRow('Cash Sales', shift.cashSales,
                        prefix: '+'),
                    if (shift.expenses > 0)
                      _ReceiptRow('Expenses', shift.expenses,
                          color: const Color(0xFFE94560), prefix: '−'),
                    const SizedBox(height: 8),
                    _ReceiptRow(
                        'Expected in Drawer',
                        shift.openingCash +
                            shift.cashSales -
                            shift.expenses,
                        bold: true),
                    _ReceiptRow(
                        'Actual Cash Count',
                        shift.actualCashCount ?? 0,
                        bold: true),
                    const SizedBox(height: 16),
                    _ReceiptDivider(),
                    const SizedBox(height: 16),

                    // ── Over/Short ───────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: overShortColor.withValues(alpha:0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: overShortColor.withValues(alpha:0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            diff == 0
                                ? 'Exact'
                                : diff > 0
                                    ? 'OVER'
                                    : 'SHORT',
                            style: TextStyle(
                                color: overShortColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5),
                          ),
                          Text(
                            '${diff >= 0 ? '+' : ''}₱${NumberFormat('#,##0.00').format(diff)}',
                            style: TextStyle(
                                color: overShortColor,
                                fontSize: 22,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),

                    if (shift.notes != null &&
                        shift.notes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _ReceiptDivider(),
                      const SizedBox(height: 12),
                      _ReceiptLabel('NOTES'),
                      const SizedBox(height: 6),
                      Text(shift.notes!,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha:0.5),
                              fontSize: 13)),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Done — Back to Login',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

// ── Expenses Card ─────────────────────────────────────────────────────────────

class _ExpensesCard extends ConsumerStatefulWidget {
  final String shiftId;
  const _ExpensesCard({required this.shiftId});

  @override
  ConsumerState<_ExpensesCard> createState() => _ExpensesCardState();
}

class _ExpensesCardState extends ConsumerState<_ExpensesCard> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  double _totalExpenses = 0;
  bool _adding = false;
  bool _saving = false;

  static const _surface = Color(0xFF1A1F35);
  static const _accent = Color(0xFFE94560);

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    final service = ref.read(shiftServiceProvider);
    final total = await service.getExpenses(widget.shiftId);
    if (mounted) {
      setState(() => _totalExpenses = total);
      ref.read(_liveExpensesProvider.notifier).state = total;
    }
  }

  Future<void> _save() async {
    final amount =
        double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(shiftServiceProvider).logExpense(
            shiftId: widget.shiftId,
            businessId: '',
            amount: amount,
            description: desc,
          );
      _amountCtrl.clear();
      _descCtrl.clear();
      await _loadExpenses();
      if (mounted) setState(() => _adding = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha:0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 16, color: Color(0xFFE94560)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Total Expenses: ₱${NumberFormat('#,##0.00').format(_totalExpenses)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _adding = !_adding),
                icon: Icon(
                    _adding ? Icons.close : Icons.add, size: 14),
                label: Text(_adding ? 'Cancel' : 'Add',
                    style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    padding: EdgeInsets.zero),
              ),
            ],
          ),
          if (_adding) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.]')),
                    ],
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha:0.2),
                          fontSize: 13),
                      prefixText: '₱ ',
                      prefixStyle: TextStyle(
                          color: Colors.white.withValues(alpha:0.4)),
                      filled: true,
                      fillColor: _surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _descCtrl,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Description (e.g. Ice, Supplies)',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha:0.2),
                          fontSize: 13),
                      filled: true,
                      fillColor: _surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 8),
                _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFE94560)))
                    : GestureDetector(
                        onTap: _save,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha:0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.check,
                              color: _accent, size: 18),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'This amount will be deducted from expected cash in drawer.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha:0.25),
                  fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: TextStyle(
            color: Colors.white.withValues(alpha:0.35),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2));
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool isBold;
  final String? prefix;
  final IconData? icon;
  final String? subtitle;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
    this.prefix,
    this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: color.withValues(alpha:0.6), size: 16),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: isBold
                          ? Colors.white
                          : Colors.white.withValues(alpha:0.55),
                      fontSize: isBold ? 14 : 13,
                      fontWeight: isBold
                          ? FontWeight.w700
                          : FontWeight.w500)),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha:0.2),
                        fontSize: 10)),
            ],
          ),
        ),
        Text(
          '${prefix ?? ''}₱${NumberFormat('#,##0.00').format(value)}',
          style: TextStyle(
              color: color,
              fontSize: isBold ? 15 : 13,
              fontWeight:
                  isBold ? FontWeight.w800 : FontWeight.w600),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(
            height: 1, color: Colors.white.withValues(alpha:0.06)),
      );
}

class _ReceiptDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
      height: 1,
      color: Colors.white.withValues(alpha:0.08),
      thickness: 1);
}

class _ReceiptLabel extends StatelessWidget {
  final String text;
  const _ReceiptLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: Colors.white.withValues(alpha:0.3),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5));
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final Color? color;
  final String? prefix;

  const _ReceiptRow(this.label, this.value,
      {this.bold = false, this.color, this.prefix});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white.withValues(alpha:bold ? 0.9 : 0.55);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: c,
                  fontSize: bold ? 14 : 13,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.normal)),
          Text(
            '${prefix ?? ''}₱${NumberFormat('#,##0.00').format(value)}',
            style: TextStyle(
                color: color ?? Colors.white.withValues(alpha:bold ? 1 : 0.7),
                fontSize: bold ? 14 : 13,
                fontWeight:
                    bold ? FontWeight.w800 : FontWeight.w500),
          ),
        ],
      ),
    );
  }
}