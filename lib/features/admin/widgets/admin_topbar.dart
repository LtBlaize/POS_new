// lib/features/admin/widgets/admin_topbar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/auth/auth_provider.dart';
import 'admin_colors.dart';

class AdminTopBar extends ConsumerWidget implements PreferredSizeWidget {
  final String currentRoute;
  final bool showMenuButton;
  final VoidCallback? onMenuTap;

  const AdminTopBar({
    super.key,
    required this.currentRoute,
    this.showMenuButton = false,
    this.onMenuTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(72);

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AdminColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final authService = ref.read(authServiceProvider);
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
    authService.logout().catchError((e) {
      debugPrint('[AdminTopBar] logout error (ignored): $e');
    });
  }

  // "View as business" — Phase 3's spec note: admins land on /admin by
  // default, with an EXPLICIT affordance to leave, rather than the router
  // silently reusing normal POS session logic. Most admin accounts won't
  // have a linked business profile at all, so this only works if one exists.
  void _viewAsBusiness(BuildContext context, WidgetRef ref) {
    final profile = ref.read(profileProvider).value;
    if (profile == null || profile.businessId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No business profile is linked to this admin account.')),
      );
      return;
    }
    Navigator.pushNamedAndRemoveUntil(context, '/pos', (_) => false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AdminColors.surface,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: AdminColors.textPrimary),
              onPressed: onMenuTap ?? () => Scaffold.of(context).openDrawer(),
            ),

          // Search — decorative for now. TODO(Phase 6): wire to the
          // server-side filtered business list once it exists; premature to
          // build a global search before there's a single searchable list.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TextField(
                enabled: false,
                decoration: InputDecoration(
                  hintText: 'Search businesses, payments...',
                  hintStyle: const TextStyle(color: AdminColors.textMuted, fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search, size: 20, color: AdminColors.textMuted),
                  filled: true,
                  fillColor: AdminColors.background,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AdminColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AdminColors.border),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AdminColors.border),
                  ),
                ),
              ),
            ),
          ),

          const Spacer(),

          // Notifications — decorative only. No notifications feature exists
          // in the phase plan (0-14); showing a fake unread count would be
          // exactly the kind of fabricated data the plan explicitly warns
          // against for the dashboard KPIs, so it's left empty here too.
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded, color: AdminColors.textSecondary),
            onPressed: () {},
          ),

          const SizedBox(width: 8),

          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (value) {
              switch (value) {
                case 'view_as_business':
                  _viewAsBusiness(context, ref);
                case 'settings':
                  Navigator.pushReplacementNamed(context, '/admin/settings');
                case 'sign_out':
                  _signOut(context, ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'view_as_business', child: Text('View as business')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'sign_out', child: Text('Sign out')),
            ],
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AdminColors.neutralBg,
                  child: Icon(Icons.person, color: AdminColors.textSecondary, size: 20),
                ),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Admin Profile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Administrator (Platform Admin)',
                        style: TextStyle(fontSize: 11, color: AdminColors.textMuted)),
                  ],
                ),
                SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AdminColors.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}