// lib/features/pos/dialogs/split_bill_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/models/order.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/services/feature_manager.dart';
import '../../../shared/widgets/app_colors.dart';
import 'checkout_dialog.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _splitsProvider =
    StateNotifierProvider.autoDispose<_SplitsNotifier, List<List<CartItem>>>(
  (ref) {
    final items = ref.read(cartProvider);
    return _SplitsNotifier(items);
  },
);

class _SplitsNotifier extends StateNotifier<List<List<CartItem>>> {
  final List<CartItem> _allItems;

  _SplitsNotifier(this._allItems)
      : super([List.from(_allItems), <CartItem>[]]);

  void setSplitCount(int count) {
    final current = state.length;
    if (count == current) return;
    if (count < 2) return;

    final newSplits = List.generate(count, (i) {
      if (i < current) return List<CartItem>.from(state[i]);
      return <CartItem>[];
    });

    // Collect items that were in removed splits
    if (count < current) {
      final orphans = <CartItem>[];
      for (int i = count; i < current; i++) {
        orphans.addAll(state[i]);
      }
      // Return orphans to split 0
      for (final orphan in orphans) {
        final idx = newSplits[0]
            .indexWhere((c) => c.product.id == orphan.product.id);
        if (idx >= 0) {
          newSplits[0][idx] = CartItem(
            product: newSplits[0][idx].product,
            selectedVariant: newSplits[0][idx].selectedVariant,
            quantity: newSplits[0][idx].quantity + orphan.quantity,
            discountAmount: newSplits[0][idx].discountAmount,
            discountType: newSplits[0][idx].discountType,
            costAtSale: newSplits[0][idx].costAtSale,
            notes: newSplits[0][idx].notes,
          );
        } else {
          newSplits[0].add(orphan);
        }
      }
    }

    state = newSplits;
  }

  /// Move one unit of [item] from split [from] to split [to]
  void moveItem(CartItem item, int from, int to) {
    if (from == to) return;
    final splits = List.generate(state.length, (i) => List<CartItem>.from(state[i]));

    // Remove one from source
    final srcIdx = splits[from].indexWhere((c) => c.product.id == item.product.id);
    if (srcIdx < 0) return;
    final src = splits[from][srcIdx];
    if (src.quantity <= 1) {
      splits[from].removeAt(srcIdx);
    } else {
      splits[from][srcIdx] = CartItem(
        product: src.product,
        selectedVariant: src.selectedVariant,
        quantity: src.quantity - 1,
        discountAmount: src.discountAmount,
        discountType: src.discountType,
        costAtSale: src.costAtSale,
        notes: src.notes,
      );
    }

    // Add one to destination
    final dstIdx = splits[to].indexWhere((c) => c.product.id == item.product.id);
    if (dstIdx >= 0) {
      final dst = splits[to][dstIdx];
      splits[to][dstIdx] = CartItem(
        product: dst.product,
        selectedVariant: dst.selectedVariant,
        quantity: dst.quantity + 1,
        discountAmount: dst.discountAmount,
        discountType: dst.discountType,
        costAtSale: dst.costAtSale,
        notes: dst.notes,
      );
    } else {
      splits[to].add(CartItem(
        product: item.product,
        selectedVariant: item.selectedVariant,
        quantity: 1,
        discountAmount: item.discountAmount,
        discountType: item.discountType,
        costAtSale: item.costAtSale,
        notes: item.notes,
      ));
    }

    state = splits;
  }

  double totalForSplit(int index) {
    return state[index].fold(0, (s, i) => s + i.total);
  }

  bool get isValid {
    final assigned = state.fold<int>(0, (s, split) =>
        s + split.fold(0, (ss, i) => ss + i.quantity));
    final total = _allItems.fold<int>(0, (s, i) => s + i.quantity);
    return assigned == total &&
        state.every((split) => split.isNotEmpty);
  }
}

// ── SplitBillDialog ───────────────────────────────────────────────────────────

class SplitBillDialog extends ConsumerStatefulWidget {
  final FeatureManager featureManager;

  const SplitBillDialog({super.key, required this.featureManager});

  @override
  ConsumerState<SplitBillDialog> createState() => _SplitBillDialogState();
}

class _SplitBillDialogState extends ConsumerState<SplitBillDialog> {
  int _splitCount = 2;
  int _currentSplit = 0;
  bool _paying = false;
  final List<Order?> _completedOrders = [];

  @override
  Widget build(BuildContext context) {
    final splits = ref.watch(_splitsProvider);
    final notifier = ref.read(_splitsProvider.notifier);
    final isValid = notifier.isValid;
    final allDone = _completedOrders.length == _splitCount &&
        _completedOrders.every((o) => o != null);

    if (allDone) return _AllDoneView(orders: _completedOrders.cast<Order>(),
        onDone: () => Navigator.of(context).pop());

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF2A2A3E)),
        ),
        child: Column(
          children: [
            _SplitHeader(
              splitCount: _splitCount,
              onCountChanged: (n) {
                setState(() {
                  _splitCount = n;
                  if (_currentSplit >= n) _currentSplit = 0;
                });
                ref.read(_splitsProvider.notifier).setSplitCount(n);
              },
              onCancel: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Split tabs
                  _SplitTabs(
                    splitCount: _splitCount,
                    currentSplit: _currentSplit,
                    splits: splits,
                    completedOrders: _completedOrders,
                    notifier: notifier,
                    onSelect: (i) => setState(() => _currentSplit = i),
                  ),
                  // Item assignment panel
                  Expanded(
                    child: _ItemAssignPanel(
                      splits: splits,
                      currentSplit: _currentSplit,
                      splitCount: _splitCount,
                      onMove: (item, from, to) =>
                          ref.read(_splitsProvider.notifier).moveItem(item, from, to),
                    ),
                  ),
                ],
              ),
            ),
            _SplitFooter(
              currentSplit: _currentSplit,
              splitCount: _splitCount,
              splits: splits,
              isValid: isValid,
              paying: _paying,
              completedOrders: _completedOrders,
              onPay: isValid ? () => _paySplit(_currentSplit, splits) : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _paySplit(int index, List<List<CartItem>> splits) async {
    if (_completedOrders.length > index && _completedOrders[index] != null) return;
    final items = splits[index];
    if (items.isEmpty) return;

    setState(() => _paying = true);

    // Save discount/tip before overriding cart
    final savedDiscount = ref.read(cartProvider.notifier).orderDiscountAmount;
    final savedDiscountType = ref.read(cartProvider.notifier).orderDiscountType;
    final savedTip = ref.read(cartProvider.notifier).tipAmount;

    // Override cart with this split's items, then open checkout
    ref.read(cartProvider.notifier).loadItems(items);

    if (!mounted) return;
    setState(() => _paying = false);

    final result = await showDialog<Order>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutDialog(featureManager: widget.featureManager),
    );

    if (!mounted) return;

    // Restore full cart with original discount/tip
    final allItems = ref.read(_splitsProvider.notifier)._allItems;
    ref.read(cartProvider.notifier).loadItems(
      allItems,
      orderDiscountAmount: savedDiscount,
      orderDiscountType: savedDiscountType,
      tipAmount: savedTip,
    );

    if (result != null) {
      setState(() {
        while (_completedOrders.length <= index) _completedOrders.add(null);
        _completedOrders[index] = result;
        // Advance to next unpaid split
        for (int i = 0; i < _splitCount; i++) {
          if (i >= _completedOrders.length || _completedOrders[i] == null) {
            _currentSplit = i;
            break;
          }
        }
      });
    }
  }
}

// ── _SplitHeader ──────────────────────────────────────────────────────────────

class _SplitHeader extends StatelessWidget {
  final int splitCount;
  final ValueChanged<int> onCountChanged;
  final VoidCallback onCancel;

  const _SplitHeader({
    required this.splitCount,
    required this.onCountChanged,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF2A2A3E)))),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Icon(Icons.call_split_outlined,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Split Bill',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Text('Assign items to each guest',
                  style: TextStyle(color: Color(0xFF888899), fontSize: 11)),
            ],
          ),
          const Spacer(),
          // Split count stepper
          Row(
            children: [
              const Text('Splits:',
                  style: TextStyle(color: Color(0xFF888899), fontSize: 12)),
              const SizedBox(width: 8),
              _CountBtn(
                icon: Icons.remove,
                onTap: splitCount > 2 ? () => onCountChanged(splitCount - 1) : null,
              ),
              SizedBox(
                width: 28,
                child: Text('$splitCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              _CountBtn(
                icon: Icons.add,
                onTap: splitCount < 8 ? () => onCountChanged(splitCount + 1) : null,
              ),
            ],
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onCancel,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close, color: Color(0xFF888899), size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _CountBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A3E),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 14,
            color: onTap != null ? Colors.white : const Color(0xFF444455)),
      ),
    );
  }
}

// ── _SplitTabs ────────────────────────────────────────────────────────────────

class _SplitTabs extends StatelessWidget {
  final int splitCount;
  final int currentSplit;
  final List<List<CartItem>> splits;
  final List<Order?> completedOrders;
  final _SplitsNotifier notifier;
  final ValueChanged<int> onSelect;

  const _SplitTabs({
    required this.splitCount,
    required this.currentSplit,
    required this.splits,
    required this.completedOrders,
    required this.notifier,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFF2A2A3E)))),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: splitCount,
        itemBuilder: (context, i) {
          final isSelected = i == currentSplit;
          final isPaid = i < completedOrders.length && completedOrders[i] != null;
          final total = i < splits.length ? notifier.totalForSplit(i) : 0.0;
          final isEmpty = i >= splits.length || splits[i].isEmpty;

          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.15)
                    : const Color(0xFF1E1E30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isPaid
                      ? AppColors.success.withOpacity(0.5)
                      : isSelected
                          ? AppColors.primary.withOpacity(0.5)
                          : const Color(0xFF2A2A3E),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  if (isPaid)
                    const Icon(Icons.check_circle,
                        size: 16, color: AppColors.success)
                  else
                    Icon(Icons.person_outline,
                        size: 16,
                        color: isSelected
                            ? AppColors.primary
                            : const Color(0xFF888899)),
                  const SizedBox(height: 4),
                  Text('Guest ${i + 1}',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? AppColors.primary : const Color(0xFF888899))),
                  const SizedBox(height: 2),
                  Text(
                    isPaid
                        ? 'Paid'
                        : isEmpty
                            ? 'Empty'
                            : '₱${total.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 9,
                        color: isPaid
                            ? AppColors.success
                            : isEmpty
                                ? AppColors.danger
                                : const Color(0xFF666677)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── _ItemAssignPanel ──────────────────────────────────────────────────────────

class _ItemAssignPanel extends StatelessWidget {
  final List<List<CartItem>> splits;
  final int currentSplit;
  final int splitCount;
  final void Function(CartItem item, int from, int to) onMove;

  const _ItemAssignPanel({
    required this.splits,
    required this.currentSplit,
    required this.splitCount,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final items = currentSplit < splits.length ? splits[currentSplit] : <CartItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'Guest ${currentSplit + 1} — tap × to move item to another guest',
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF888899)),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('No items assigned',
                      style: TextStyle(
                          color: Color(0xFF555566), fontSize: 12)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _AssignRow(
                      item: item,
                      currentSplit: currentSplit,
                      splitCount: splitCount,
                      onMove: onMove,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AssignRow extends StatelessWidget {
  final CartItem item;
  final int currentSplit;
  final int splitCount;
  final void Function(CartItem, int, int) onMove;

  const _AssignRow({
    required this.item,
    required this.currentSplit,
    required this.splitCount,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text('${item.quantity}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Text(item.notes!,
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.warning,
                          fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          Text('₱${item.total.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(width: 8),
          // Move button — cycles to next split
          if (splitCount > 1)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                final next = (currentSplit + 1) % splitCount;
                onMove(item, currentSplit, next);
              },
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A3E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '→${(currentSplit + 1) % splitCount + 1}',
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF888899)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── _SplitFooter ──────────────────────────────────────────────────────────────

class _SplitFooter extends StatelessWidget {
  final int currentSplit;
  final int splitCount;
  final List<List<CartItem>> splits;
  final bool isValid;
  final bool paying;
  final List<Order?> completedOrders;
  final VoidCallback? onPay;

  const _SplitFooter({
    required this.currentSplit,
    required this.splitCount,
    required this.splits,
    required this.isValid,
    required this.paying,
    required this.completedOrders,
    required this.onPay,
  });

  bool get _isPaid =>
      currentSplit < completedOrders.length &&
      completedOrders[currentSplit] != null;

  @override
  Widget build(BuildContext context) {
    final paidCount =
        completedOrders.where((o) => o != null).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2A2A3E)))),
      child: Column(
        children: [
          Row(
            children: [
              Text('$paidCount / $splitCount paid',
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 12)),
              const Spacer(),
              if (!isValid)
                const Text('All items must be assigned',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 11,
                        fontStyle: FontStyle.italic)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: _isPaid
                ? Container(
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.success.withOpacity(0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            color: AppColors.success, size: 16),
                        SizedBox(width: 8),
                        Text('Paid',
                            style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: onPay,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: (isValid && !paying)
                            ? AppColors.primary
                            : const Color(0xFF2A2A3E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: paying
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : Text(
                              'Pay Guest ${currentSplit + 1}',
                              style: TextStyle(
                                  color: isValid
                                      ? Colors.white
                                      : const Color(0xFF444455),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── _AllDoneView ──────────────────────────────────────────────────────────────

class _AllDoneView extends StatelessWidget {
  final List<Order> orders;
  final VoidCallback onDone;

  const _AllDoneView({required this.orders, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 48),
            const SizedBox(height: 12),
            const Text('All splits paid!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            ...orders.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text('Guest ${e.key + 1}',
                          style: const TextStyle(
                              color: Color(0xFF888899), fontSize: 13)),
                      const Spacer(),
                      Text(
                          '₱${e.value.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ],
                  ),
                )),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Done',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}