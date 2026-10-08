// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/store_build_flag.dart';

import '../../core/models/business.dart' show SubscriptionPlan;

import '../../core/models/staff.dart';
import '../../core/providers/staff_provider.dart';
import '../../core/services/feature_manager.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/providers/cart_provider.dart';
import '../../features/auth/pin_lock_overlay.dart';
import '../../main.dart';
import '../../shared/widgets/app_colors.dart';

import 'widgets/general_settings_section.dart';
import 'widgets/lan_settings_section.dart';
import 'widgets/printer_settings_section.dart';
import 'widgets/staff_settings_section.dart' show StaffSettingsSection, OwnerPinSection;
import 'widgets/sync_issues_section.dart';
import 'widgets/table_settings_section.dart';

class SettingsScreen extends ConsumerWidget {
  final FeatureManager featureManager;
  const SettingsScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceRole = ref.watch(deviceRoleProvider);
    final isKitchenDevice = deviceRole == DeviceRole.kitchen;

    // Kitchen device only needs LAN + printer setup
    if (isKitchenDevice) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        appBar: _appBar(),
        body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(child: const LanSettingsSection()),
          const SizedBox(height: 16),
          _SectionCard(child: const PrinterSettingsSection()),
          const SizedBox(height: 16),
          _SectionCard(child: _ChangeRoleSection()),
          const SizedBox(height: 16),
          _LogoutSection(),
          const SizedBox(height: 32),
        ], 
      ),
      );
    }

    // POS device — load profile to determine staff role
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (profile) {
        final business = profile?.business;
        if (business == null) {
          return const Scaffold(
              body: Center(child: Text('No business found')));
        }

        final isRestaurant = business.businessType.isRestaurant;
        final activeStaff = ref.watch(activeStaffProvider);
        final staffRole = activeStaff?.role;
        final isOwner = staffRole == StaffRole.owner;
        final isManager = staffRole == StaffRole.manager || isOwner;

        return Scaffold(
          backgroundColor: const Color(0xFFF4F5F7),
          appBar: _appBar(),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── General — all POS roles ───────────────────────────────
              GeneralSettingsSection(business: business),

              // ── LAN — restaurant only ─────────────────────────────────
              if (isRestaurant) ...[
                const SizedBox(height: 16),
                _SectionCard(child: const LanSettingsSection()),
              ],

              if (isRestaurant && isManager) ...[
                const SizedBox(height: 16),
                _SectionCard(child: const TableSettingsSection()),
              ],

              // ── Printer — all POS roles ───────────────────────────────
              const SizedBox(height: 16),
              _SectionCard(child: const PrinterSettingsSection()),

              // ── PIN change — owners only ──────────────────────────────
              if (isOwner) ...[
                const SizedBox(height: 16),
                _SectionCard(child: const OwnerPinSection()),
              ],

              // ── Staff management — owners only ────────────────────────
              if (isOwner) ...[
                const SizedBox(height: 16),
                _SectionCard(child: const StaffSettingsSection()),
              ],


              // ── Sync issues — managers+ only, POS device only ─────────
              if (isManager) ...[
                const SizedBox(height: 16),
                _SectionCard(child: const SyncIssuesSection()),
              ],

              // ── Subscription — owners only ────────────────────────────
              if (isOwner) ...[
                const SizedBox(height: 16),
                const _SubscriptionSection(),
              ],

              // ── Device role — always at the bottom ───────────────────
              const SizedBox(height: 16),
              _SectionCard(child: _ChangeRoleSection()),

              // ── Logout ────────────────────────────────────────────────
              const SizedBox(height: 16),
              _LogoutSection(),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      title: const Text('Settings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: AppColors.divider),
      ),
    );
  }
}

// ── Change device role section ────────────────────────────────────────────────

class _ChangeRoleSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRole = ref.watch(deviceRoleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.devices_rounded,
                size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            const Text(
              'DEVICE ROLE',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  currentRole == DeviceRole.pos
                      ? Icons.point_of_sale_rounded
                      : Icons.kitchen_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentRole == DeviceRole.pos
                            ? 'POS / Cashier'
                            : 'Kitchen Display',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Tap to change this device\'s role',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _confirmRoleChange(context, ref),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade600),
                  child: const Text('Change',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRoleChange(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change device role?'),
        content: const Text(
            'This will restart the app setup. You will need to choose POS or Kitchen again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: Colors.red.shade600),
            child: const Text('Change role'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_role');

    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
          context, '/role-select', (_) => false);
    }
  }
}

// ── Logout section ────────────────────────────────────────────────────────────

class _LogoutSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Log out?'),
              content:
                  const Text('You will be returned to the login screen.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red),
                  child: const Text('Log out'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;

          ref.read(cartProvider.notifier).clear();
          ref.read(activeStaffProvider.notifier).logout();
          ref.read(appLockedProvider.notifier).state = true;

          try {
            await ref.read(authServiceProvider).logout();
          } catch (e) {
            debugPrint('[Settings logout] error: $e');
            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false);
            }
          }
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.logout_rounded,
                    size: 18, color: Colors.red.shade600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Log out',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: Colors.red.shade300),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Subscription section ──────────────────────────────────────────────────────
//
// Rewritten for the starter/growth/pro model (2026-09). The previous
// version assumed a single-tier Basic/Premium/Enterprise trial: it only
// showed an upgrade CTA when `!plan.isPaid`, which meant Starter and
// Growth — both paid tiers with a real plan above them — never showed
// any way to upgrade at all. There's still no self-serve payment
// integration (Phase 8 is manual-payments-only), so "upgrade" opens a
// contact dialog (call/SMS/email) with the business id and current plan
// pre-filled, rather than a stubbed "coming soon" snackbar.

const _upgradePhone = '09065790889';
const _upgradeEmail = 'noblezaravenblair@gmail.com';

// What each plan unlocks beyond the one below it — shown under "Upgrade
// to X includes" so the CTA is specific to the business's actual next
// step, not a generic Pro feature list.
const _growthIncludes = [
  'Up to 3 terminals',
  'Unlimited staff',
  'Unlimited active promos',
  'Reports & Excel export',
  '1 kitchen station',
  'Up to 6 tables / 1 room',
];
const _proIncludes = [
  'Unlimited terminals',
  'Unlimited tables & rooms',
  'Multi-station kitchen',
  'Custom role permissions',
];

class _SubscriptionSection extends ConsumerWidget {
  const _SubscriptionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fm = ref.watch(featureManagerProvider);
    final plan = fm.currentPlan;
    final isOnTrial = fm.isOnActiveTrial;
    final trialExpired = !plan.isPaid && !isOnTrial;
    final daysLeft = fm.trialDaysLeft;

    final Color statusColor;
    final String statusLabel;
    final String statusSub;

    if (isOnTrial) {
      statusColor = daysLeft <= 2
          ? Colors.orange.shade700
          : Colors.blue.shade700;
      statusLabel = '${plan.displayName} Trial';
      statusSub = daysLeft == 0
          ? 'Expires today'
          : '$daysLeft day${daysLeft == 1 ? '' : 's'} remaining';
    } else if (plan.isPaid) {
      statusColor = Colors.green.shade600;
      statusLabel = plan.displayName;
      statusSub = 'Full access active';
    } else {
      statusColor = AppColors.textSecondary;
      statusLabel = '${plan.displayName} — Trial Ended';
      statusSub = 'Contact us to reactivate';
    }

    // Plans are Starter → Growth → Pro. Pro has nothing above it.
    final nextPlanLabel = kStoreBuild ? null : switch (plan) {   
      SubscriptionPlan.starter => 'Growth',
      SubscriptionPlan.growth => 'Pro',
      SubscriptionPlan.pro => null,
    };
    final nextPlanIncludes = switch (plan) {
      SubscriptionPlan.starter => _growthIncludes,
      SubscriptionPlan.growth => _proIncludes,
      SubscriptionPlan.pro => const <String>[],
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'SUBSCRIPTION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  trialExpired
                      ? Icons.lock_outline_rounded
                      : isOnTrial
                          ? Icons.hourglass_top_rounded
                          : Icons.verified_rounded,
                  size: 20,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusSub,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (kStoreBuild) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.support_agent_rounded, size: 16),
                label: const Text('Contact support'),
                onPressed: () => _showContactDialog(
                  context,
                  ref,
                  currentPlan: plan.displayName,
                  targetPlan: plan.displayName,
                ),
              ),
            ),
          ],
          // Show an upgrade path whenever there's a plan above the current
          // one — regardless of paid/trial/expired status. Pro has none.
          if (nextPlanLabel != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Text(
              'Upgrade to $nextPlanLabel includes',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...nextPlanIncludes.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 14, color: Colors.green.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _showContactDialog(
                  context,
                  ref,
                  currentPlan: plan.displayName,
                  targetPlan: nextPlanLabel,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  trialExpired
                      ? 'Contact Us to Reactivate'
                      : 'Upgrade to $nextPlanLabel',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showContactDialog(
    BuildContext context,
    WidgetRef ref, {
    required String currentPlan,
    required String targetPlan,
  }) {
    final business = ref.read(profileProvider).asData?.value?.business;
    final businessName = business?.name ?? 'your business';
    final businessId = business?.id ?? '';

    showDialog(
      context: context,
      builder: (_) => _ContactUpgradeDialog(
        businessName: businessName,
        businessId: businessId,
        currentPlan: currentPlan,
        targetPlan: targetPlan,
      ),
    );
  }
}

class _ContactUpgradeDialog extends StatelessWidget {
  final String businessName;
  final String businessId;
  final String currentPlan;
  final String targetPlan;

  const _ContactUpgradeDialog({
    required this.businessName,
    required this.businessId,
    required this.currentPlan,
    required this.targetPlan,
  });

  String get _message =>
      'Hi, I\'d like to upgrade "$businessName" from $currentPlan to '
      '$targetPlan.\nBusiness ID: $businessId';

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.scheme}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(kStoreBuild ? 'Contact support' : 'Upgrade to $targetPlan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kStoreBuild
                ? 'Reach out to our support team about "$businessName".'
                : 'We don\'t have automatic billing yet — reach out and we\'ll '
                    'get "$businessName" upgraded manually.',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.call_rounded, color: AppColors.primary),
            title: const Text('Call or text',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(_upgradePhone),
            onTap: () =>
                _launch(context, Uri(scheme: 'tel', path: _upgradePhone)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                const Icon(Icons.email_outlined, color: AppColors.primary),
            title: const Text('Email',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(_upgradeEmail),
            onTap: () => _launch(
              context,
              Uri(
                scheme: 'mailto',
                path: _upgradeEmail,
                query:
                    'subject=${Uri.encodeComponent('Upgrade request — $businessName')}'
                    '&body=${Uri.encodeComponent(_message)}',
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}