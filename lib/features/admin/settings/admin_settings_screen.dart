// lib/features/admin/settings/admin_settings_screen.dart
//
// Phase 12. /admin/settings — manage admin_users. Route-level gating
// (AppRouter._isPlatformAdmin) only checks "is any active admin" — same as
// every other /admin/* route. The platform_admin-only restriction for THIS
// screen is enforced server-side: list_admin_users() raises for
// non-platform_admin callers, and the Edge Function independently requires
// required_role: "platform_admin". If the RPC throws, show a restricted
// state instead of a generic error.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_colors.dart';
import 'admin_settings_providers.dart';

class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminUsersListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AdminColors.primary,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add admin'),
        onPressed: () => showDialog(context: context, builder: (_) => const _InviteAdminDialog()),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 40, color: AdminColors.textMuted),
                const SizedBox(height: 12),
                const Text('Restricted to platform administrators',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AdminColors.textPrimary)),
                const SizedBox(height: 6),
                Text(
                  'Your admin account doesn\'t have platform_admin access.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: AdminColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        data: (admins) => ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: admins.length,
          itemBuilder: (context, i) => _AdminRow(admin: admins[i]),
        ),
      ),
    );
  }
}

class _AdminRow extends ConsumerWidget {
  final AdminUserRow admin;
  const _AdminRow({required this.admin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAdminId = ref.watch(currentAdminIdProvider);
    final isSelf = admin.id == currentAdminId;
    final (bg, fg) = AdminColors.statusPillColors(admin.isActive ? 'active' : 'suspended');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: AdminColors.neutralBg,
            child: Icon(Icons.person, size: 18, color: AdminColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(admin.email,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminColors.textPrimary)),
                  if (isSelf) ...[
                    const SizedBox(width: 6),
                    const Text('(you)', style: TextStyle(fontSize: 11.5, color: AdminColors.textMuted)),
                  ],
                ]),
                const SizedBox(height: 2),
                Text('Added ${admin.createdAt.toLocal().toString().split(' ').first}',
                    style: const TextStyle(fontSize: 11.5, color: AdminColors.textMuted)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: DropdownButton<String>(
              value: admin.role,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'platform_admin', child: Text('Platform Admin')),
                DropdownMenuItem(value: 'platform_support', child: Text('Platform Support')),
                DropdownMenuItem(value: 'platform_viewer', child: Text('Platform Viewer')),
              ],
              onChanged: (newRole) async {
                if (newRole == null || newRole == admin.role) return;
                try {
                  await ref.read(adminSettingsServiceProvider).setRole(admin.id, newRole);
                  ref.invalidate(adminUsersListProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e'), backgroundColor: AdminColors.danger),
                    );
                  }
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(admin.isActive ? 'Active' : 'Inactive',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: isSelf
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('${admin.isActive ? "Deactivate" : "Reactivate"} ${admin.email}?'),
                        content: Text(admin.isActive
                            ? 'They will immediately lose access to /admin.'
                            : 'They will regain access to /admin.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(
                              foregroundColor: admin.isActive ? AdminColors.danger : AdminColors.primary,
                            ),
                            child: Text(admin.isActive ? 'Deactivate' : 'Reactivate'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;

                    try {
                      final service = ref.read(adminSettingsServiceProvider);
                      if (admin.isActive) {
                        await service.deactivate(admin.id);
                      } else {
                        await service.reactivate(admin.id);
                      }
                      ref.invalidate(adminUsersListProvider);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e'), backgroundColor: AdminColors.danger),
                        );
                      }
                    }
                  },
            style: TextButton.styleFrom(
              foregroundColor: admin.isActive ? AdminColors.danger : AdminColors.primary,
            ),
            child: Text(admin.isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
  }
}

class _InviteAdminDialog extends ConsumerStatefulWidget {
  const _InviteAdminDialog();

  @override
  ConsumerState<_InviteAdminDialog> createState() => _InviteAdminDialogState();
}

class _InviteAdminDialogState extends ConsumerState<_InviteAdminDialog> {
  final _emailCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(adminSettingsServiceProvider).invite(email);
      // Unreachable while invite() is server-stubbed to always throw — left
      // in so the dialog closes cleanly once the Edge Function is implemented.
      ref.invalidate(adminUsersListProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add admin'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AdminColors.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send invite'),
        ),
      ],
    );
  }
}