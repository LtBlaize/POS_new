// lib/features/admin/admin_shell.dart
//
// Phase 4. Structurally separate from the POS Sidebar/layout on purpose (see
// admin_sidebar.dart, admin_colors.dart) — this is its own widget tree, not
// a variant bolted onto the existing one.
//
// Breakpoints are my defaults, NOT confirmed against your actual spec
// section 26 (wasn't available when this was written):
//   desktop >= 1100px : fixed sidebar, labels + icons
//   tablet  700-1099px: collapsed icon-only rail (mirrors POS sidebar width)
//   mobile  < 700px   : sidebar becomes a Drawer, topbar gets a menu button
import 'package:flutter/material.dart';
import 'widgets/admin_colors.dart';
import 'widgets/admin_sidebar.dart';
import 'widgets/admin_topbar.dart';

const double kAdminTabletBreakpoint = 700;
const double kAdminDesktopBreakpoint = 1100;

class AdminShell extends StatelessWidget {
  final String currentRoute;
  final Widget child;

  const AdminShell({super.key, required this.currentRoute, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width < kAdminTabletBreakpoint;
        final isTablet = width >= kAdminTabletBreakpoint && width < kAdminDesktopBreakpoint;

        if (isMobile) {
          return Scaffold(
            backgroundColor: AdminColors.background,
            appBar: AdminTopBar(currentRoute: currentRoute, showMenuButton: true),
            drawer: Drawer(
              child: AdminSidebar(currentRoute: currentRoute, collapsed: false),
            ),
            body: child,
          );
        }

        return Scaffold(
          backgroundColor: AdminColors.background,
          body: Row(
            children: [
              AdminSidebar(currentRoute: currentRoute, collapsed: isTablet),
              Expanded(
                child: Column(
                  children: [
                    AdminTopBar(currentRoute: currentRoute),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}