// lib/features/admin/widgets/admin_sidebar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/auth/auth_provider.dart';
import 'admin_colors.dart';

class _AdminNavItem {
  final IconData icon;
  final String label;
  final String route;
  const _AdminNavItem(this.icon, this.label, this.route);
}

class _AdminNavGroup {
  final String label;
  final List<_AdminNavItem> items;
  const _AdminNavGroup(this.label, this.items);
}

const _navGroups = <_AdminNavGroup>[
  _AdminNavGroup('OVERVIEW', [
    _AdminNavItem(Icons.home_rounded, 'Dashboard', '/admin/dashboard'),
  ]),
  _AdminNavGroup('MANAGEMENT', [
    _AdminNavItem(Icons.store_rounded, 'Businesses', '/admin/businesses'),
    _AdminNavItem(Icons.calendar_month_rounded, 'Subscriptions', '/admin/subscriptions'),
    _AdminNavItem(Icons.credit_card_rounded, 'Payments', '/admin/payments'),
    _AdminNavItem(Icons.workspaces_rounded, 'Plans', '/admin/plans'),
  ]),
  _AdminNavGroup('MONITORING', [
    _AdminNavItem(Icons.description_outlined, 'Activity Logs', '/admin/activity'),
    _AdminNavItem(Icons.favorite_border_rounded, 'System Health', '/admin/system'),
  ]),
  _AdminNavGroup('SYSTEM', [
    _AdminNavItem(Icons.settings_outlined, 'Settings', '/admin/settings'),
  ]),
];

/// Business-detail routes (/admin/businesses/:id) should still highlight
/// "Businesses" in the sidebar. Anything under /admin or /admin/dashboard
/// highlights "Dashboard".
String _normalizeForHighlight(String route) {
  if (route == '/admin') return '/admin/dashboard';
  if (route.startsWith('/admin/businesses/')) return '/admin/businesses';
  return route;
}

class AdminSidebar extends ConsumerWidget {
  final String currentRoute;
  final bool collapsed;

  const AdminSidebar({
    super.key,
    required this.currentRoute,
    this.collapsed = false,
  });

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
      debugPrint('[AdminSidebar] logout error (ignored): $e');
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlighted = _normalizeForHighlight(currentRoute);
    final width = collapsed ? 80.0 : 260.0;

    return Container(
      width: width,
      color: AdminColors.sidebarBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Logo ──────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 20, vertical: 20),
              child: collapsed
                  ? const Center(child: _LogoMark())
                  : const Row(
                      children: [
                        _LogoMark(),
                        SizedBox(width: 10),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: 'FluxPoint ',
                              style: TextStyle(
                                color: AdminColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            TextSpan(
                              text: 'Admin',
                              style: TextStyle(
                                color: AdminColors.textSecondary,
                                fontWeight: FontWeight.w400,
                                fontSize: 18,
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
            ),

            // ── Nav groups ────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 12),
                children: [
                  for (final group in _navGroups) ...[
                    if (!collapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
                        child: Text(
                          group.label,
                          style: const TextStyle(
                            color: AdminColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    for (final item in group.items)
                      _NavTile(
                        item: item,
                        isActive: highlighted == item.route,
                        collapsed: collapsed,
                      ),
                  ],
                ],
              ),
            ),

            // ── Bottom profile card ──────────────────────────────────────
            Padding(
              padding: EdgeInsets.all(collapsed ? 8 : 12),
              child: collapsed
                  ? IconButton(
                      tooltip: 'Sign out',
                      icon: const Icon(Icons.logout_rounded, color: AdminColors.textSecondary),
                      onPressed: () => _signOut(context, ref),
                    )
                  : Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AdminColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 16,
                                backgroundColor: AdminColors.neutralBg,
                                child: Icon(Icons.person, size: 18, color: AdminColors.textSecondary),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Admin', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    Text('(Platform Administrator)',
                                        style: TextStyle(color: AdminColors.textMuted, fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _MiniLink(
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            onTap: () => Navigator.pushReplacementNamed(context, '/admin/settings'),
                          ),
                          _MiniLink(
                            icon: Icons.logout_rounded,
                            label: 'Sign out',
                            color: AdminColors.danger,
                            onTap: () => _signOut(context, ref),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AdminColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.bolt, color: Colors.white, size: 20),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _AdminNavItem item;
  final bool isActive;
  final bool collapsed;

  const _NavTile({required this.item, required this.isActive, required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? AdminColors.sidebarActiveBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 20,
            color: isActive ? AdminColors.primary : AdminColors.textSecondary,
          ),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                color: isActive ? AdminColors.primary : AdminColors.textPrimary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );

    final tappable = GestureDetector(
      onTap: () {
        if (isActive) return;
        Navigator.pushReplacementNamed(context, item.route);
      },
      child: content,
    );

    return collapsed ? Tooltip(message: item.label, preferBelow: false, child: tappable) : tappable;
  }
}

class _MiniLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _MiniLink({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color ?? AdminColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12.5, color: color ?? AdminColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}