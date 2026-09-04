// lib/features/settings/widgets/promo_settings_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/promo.dart';
import '../../../core/providers/promo_provider.dart';
import '../../../shared/widgets/app_colors.dart';
import 'promo_builder_dialog.dart';

class PromoSettingsSection extends ConsumerWidget {
  const PromoSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promosAsync = ref.watch(promoListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Promos & Packages',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const PromoBuilderDialog(),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Promo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Sell products together for a special price, or set up buy-and-get deals.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        promosAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (promos) {
            if (promos.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Center(
                  child: Text(
                    'No promos yet. Create your first package or deal.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }
            final active = promos.where((p) => p.isActive).toList();
            final inactive = promos.where((p) => !p.isActive).toList();
            return Column(
              children: [
                if (active.isNotEmpty) ...[
                  _GroupLabel('Active (${active.length})'),
                  ...active.map((p) => _PromoTile(promo: p)),
                ],
                if (inactive.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _GroupLabel('Inactive (${inactive.length})'),
                  ...inactive.map((p) => _PromoTile(promo: p)),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.3)),
      );
}

class _PromoTile extends ConsumerWidget {
  final Promo promo;
  const _PromoTile({required this.promo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expired = promo.isActive && !promo.isWithinDateRange;
    final typeLabel =
        promo.promoType == PromoType.bundle ? 'Bundle' : 'Buy X Get Y';
    final priceLabel = promo.promoType == PromoType.bundle
        ? '\u20b1${promo.effectivePrice.toStringAsFixed(2)}'
        : 'Buy ${promo.buyQuantity ?? 1} Get ${promo.getQuantity ?? 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              promo.promoType == PromoType.bundle
                  ? Icons.card_giftcard_rounded
                  : Icons.local_offer_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(promo.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    if (expired) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Expired',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$typeLabel \u00b7 $priceLabel \u00b7 ${promo.items.length} item${promo.items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 18, color: AppColors.textSecondary),
            onSelected: (action) => _handleAction(context, ref, action),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(
                  value: 'duplicate', child: Text('Duplicate')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(promo.isActive ? 'Deactivate' : 'Activate'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, String action) async {
    final repo = ref.read(promoRepositoryProvider);
    switch (action) {
      case 'edit':
        showDialog(
          context: context,
          builder: (_) => PromoBuilderDialog(existing: promo),
        );
        break;
      case 'duplicate':
        await repo.duplicate(promo);
        ref.invalidate(promoListProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Promo duplicated (inactive) — review and activate it.')),
          );
        }
        break;
      case 'toggle':
        await repo.setActive(promo.id, !promo.isActive);
        ref.invalidate(promoListProvider);
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Promo'),
            content: Text('Delete "${promo.name}"? This cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          try {
            await repo.delete(promo.id);
            ref.invalidate(promoListProvider);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('Could not delete: $e'),
                    backgroundColor: Colors.red),
              );
            }
          }
        }
        break;
    }
  }
}