// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/staff.dart';
import '../../core/providers/staff_provider.dart';
import '../../core/services/feature_manager.dart';
import '../../features/auth/auth_provider.dart';
import '../../main.dart';
import '../../shared/widgets/app_colors.dart';

import 'widgets/general_settings_section.dart';
import 'widgets/lan_settings_section.dart';
import 'widgets/printer_settings_section.dart';
import 'widgets/staff_settings_section.dart';
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

              // ── Staff management — owners only ────────────────────────
              if (isOwner) ...[
                const SizedBox(height: 16),
                _SectionCard(child: const StaffSettingsSection()),
              ],

              // ── Device role — always at the bottom ───────────────────
              const SizedBox(height: 16),
              _SectionCard(child: _ChangeRoleSection()),

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

// ── Section card wrapper ──────────────────────────────────────────────────────

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