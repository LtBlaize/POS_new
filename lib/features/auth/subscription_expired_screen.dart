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

const _supportPhone = '09065790889';
const _supportEmail = 'noblezaravenblair@gmail.com';
const _supportMessenger = 'https://m.me/YOUR_PAGE_NAME'; // TODO: your page

Future<void> _open(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open that app')),
    );
  }
}

class SubscriptionExpiredScreen extends ConsumerWidget {
  const SubscriptionExpiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                  child: const Icon(Icons.lock_outline_rounded,
                      size: 34, color: AppColors.danger),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Subscription expired',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contact support to reactivate your account.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.call_rounded, size: 16),
                      label: const Text('Call'),
                      onPressed: () => _open(
                          context, Uri(scheme: 'tel', path: _supportPhone)),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.sms_outlined, size: 16),
                      label: const Text('Text'),
                      onPressed: () => _open(
                          context, Uri(scheme: 'sms', path: _supportPhone)),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.email_outlined, size: 16),
                      label: const Text('Email'),
                      onPressed: () => _open(
                          context, Uri(scheme: 'mailto', path: _supportEmail)),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Messenger'),
                      onPressed: () =>
                          _open(context, Uri.parse(_supportMessenger)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () async {
                    ref.read(cartProvider.notifier).clear();
                    ref.read(activeStaffProvider.notifier).logout();
                    try {
                      await ref.read(authServiceProvider).logout();
                    } catch (_) {
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                            context, '/login', (_) => false);
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