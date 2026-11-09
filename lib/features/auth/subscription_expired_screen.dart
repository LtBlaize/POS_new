// lib/features/auth/subscription_expired_screen.dart
//
// Shown in place of the entire POS shell when a business fails
// hasCoreAccess — i.e. no active trial and no valid paid subscription.
// This is a business-wide lockout, distinct from feature_manager's
// per-feature hasFeature() checks (which still govern individual tabs
// like Kitchen/Inventory/Utang for businesses that DO have core access).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/app_colors.dart';
import 'auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/providers/staff_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/config/access_enforcement_flag.dart';
import '../pos/widgets/layout/top_bar.dart' show posRequestedTabProvider;

const _supportPhone = '09065790889';
const _supportEmail = 'noblezaravenblair@gmail.com';
const _supportMessenger = 'https://m.me/YOUR_PAGE_NAME'; // TODO: your page

Future<void> _open(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open that app')));
  }
}

class SubscriptionExpiredScreen extends ConsumerWidget {
  const SubscriptionExpiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biz = ref.watch(businessProvider);
    final suspended = biz != null && !biz.isActive;
    final onTrial = biz != null && biz.isOnActiveTrial && !suspended;
    final fm = ref.watch(featureManagerProvider);
    final locked = kEnforceCoreAccess && fm.hasBusiness && !fm.hasCoreAccess;
    final showRecords = locked && fm.canViewHistory;
    final neverPaid = biz != null && biz.subscriptionExpiresAt == null;
    final title =
        suspended
            ? 'Account suspended'
            : onTrial
            ? 'Choose a plan'
            : neverPaid
            ? 'Your Free Trial Has Ended'
            : 'Subscription expired';
    final message =
        suspended
            ? 'Your account is suspended. Contact support to restore access.'
            : onTrial
            ? 'Your free trial is still active. Contact us to subscribe before it ends.'
            : neverPaid
            ? 'Your 7-day free trial has expired. Choose a subscription plan to continue using your POS system.'
            : 'Your subscription has expired. Renew to continue using your POS system.';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar:
          Navigator.of(context).canPop()
              ? AppBar(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
              )
              : null,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 34,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!suspended) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Your business data and historical records are preserved. '
                    'Subscribe to restore access to your POS features.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                const _RefreshStatusButton(),
                if (!suspended) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.workspace_premium_outlined,
                      size: 16,
                    ),
                    label: const Text('View Subscription Plans'),
                    onPressed: () => _showPlans(context),
                  ),
                ],
                if (showRecords) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: const Text('View Business Records'),
                    onPressed:
                        () =>
                            ref.read(posRequestedTabProvider.notifier).state =
                                'Orders',
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (!_supportMessenger.contains('YOUR_PAGE_NAME'))
                      OutlinedButton.icon(
                        icon: const Icon(Icons.call_rounded, size: 16),
                        label: const Text('Call'),
                        onPressed:
                            () => _open(
                              context,
                              Uri(scheme: 'tel', path: _supportPhone),
                            ),
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.sms_outlined, size: 16),
                      label: const Text('Text'),
                      onPressed:
                          () => _open(
                            context,
                            Uri(scheme: 'sms', path: _supportPhone),
                          ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.email_outlined, size: 16),
                      label: const Text('Email'),
                      onPressed:
                          () => _open(
                            context,
                            Uri(scheme: 'mailto', path: _supportEmail),
                          ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Messenger'),
                      onPressed:
                          () => _open(context, Uri.parse(_supportMessenger)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () async {
                    if (ref.read(cartProvider).isNotEmpty) {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder:
                            (ctx) => AlertDialog(
                              title: const Text('Log out?'),
                              content: const Text(
                                'Your current cart has not been paid and will be discarded.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Log out'),
                                ),
                              ],
                            ),
                      );
                      if (ok != true) return;
                    }
                    ref.read(cartProvider.notifier).clear();
                    ref.read(activeStaffProvider.notifier).logout();
                    try {
                      await ref.read(authServiceProvider).logout();
                    } catch (_) {
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/login',
                          (_) => false,
                        );
                      }
                    }
                  },
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshStatusButton extends ConsumerStatefulWidget {
  const _RefreshStatusButton();
  @override
  ConsumerState<_RefreshStatusButton> createState() =>
      _RefreshStatusButtonState();
}

class _RefreshStatusButtonState extends ConsumerState<_RefreshStatusButton> {
  bool _busy = false;

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _refresh() async {
    final biz = ref.read(businessProvider);
    if (biz == null) return;
    setState(() => _busy = true);
    try {
      // Direct server read: proves we reached the server. The cached profile
      // alone could not tell "still expired" apart from "offline".
      await ref
          .read(supabaseClientProvider)
          .from('businesses')
          .select('id')
          .eq('id', biz.id)
          .single()
          .timeout(const Duration(seconds: 6));
      ref.invalidate(profileProvider);
      await ref.read(profileProvider.future);
      if (!mounted) return; // access restored: this screen was replaced
      final fm = ref.read(featureManagerProvider);
      _msg(
        fm.hasCoreAccess
            ? 'Subscription confirmed.'
            : 'No active subscription found yet.',
      );
    } catch (_) {
      _msg(
        ref.read(isOnlineProvider)
            ? 'Could not reach the server. Please try again.'
            : 'You are offline. Connect to the internet and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy ? null : _refresh,
      icon:
          _busy
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.refresh_rounded, size: 16),
      label: const Text('Refresh subscription status'),
    );
  }
}

void _showPlans(BuildContext context) {
  const plans = [
    (
      'Starter',
      '₱499 / month',
      '1 terminal, up to 2 staff, up to 5 active promos, credits (utang), shifts.',
    ),
    (
      'Growth',
      '₱799 / month',
      'Up to 3 terminals, unlimited staff and promos, reports and Excel export, '
          'kitchen display (1 station), up to 6 tables.',
    ),
    (
      'Pro',
      '₱1,299 / month',
      'Everything in Growth, plus unlimited terminals, tables and rooms, '
          'multi-station kitchen and custom roles.',
    ),
  ];
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder:
        (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Subscription plans',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  for (final p in plans) ...[
                    Text(
                      '${p.$1}  ·  ${p.$2}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.$3,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'To subscribe or renew, contact support using the buttons on '
                    'the previous screen. Your plan is activated once we confirm '
                    'your payment. Your data and records stay safe in the meantime.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}
