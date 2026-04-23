import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/models/staff.dart';
import '../../core/providers/staff_provider.dart';
import '../../shared/widgets/app_colors.dart';
import 'widgets/general_settings_section.dart';
import 'widgets/table_settings_section.dart';
import 'widgets/room_settings_section.dart';
import 'widgets/staff_settings_section.dart';


class SettingsScreen extends ConsumerWidget {
  final featureManager;
  const SettingsScreen({super.key, required this.featureManager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (profile) {
        final businessAsync = ref.watch(profileProvider);

        return businessAsync.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
          data: (profile) {
            final business = profile?.business;
            if (business == null) {
              return const Scaffold(body: Center(child: Text('No business found')));
            }

            final isRestaurant = business.businessType.isRestaurant;
            final activeStaff = ref.watch(activeStaffProvider);
            final isOwner = activeStaff?.role == StaffRole.owner;

            return Scaffold(
              backgroundColor: const Color(0xFFF4F5F7),
              appBar: AppBar(
                title: const Text('Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                backgroundColor: Colors.white,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Divider(height: 1, color: AppColors.divider),
                ),
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GeneralSettingsSection(business: business),
                  if (isRestaurant) ...[
                    const SizedBox(height: 16),
                    _SectionCard(child: const RoomSettingsSection()),
                    const SizedBox(height: 12),
                    _SectionCard(child: const TableSettingsSection()),
                  ],
                  if (isOwner) ...[
                    const SizedBox(height: 16),
                    _SectionCard(child: const StaffSettingsSection()),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );              
      },
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