// lib/features/settings/widgets/staff_settings_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/staff.dart';
import '../../../core/providers/staff_provider.dart';
import '../../../core/providers/role_permissions_provider.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../shared/widgets/app_colors.dart';

class StaffSettingsSection extends ConsumerWidget {
  const StaffSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);
    final businessType = ref.watch(businessTypeProvider);
    final isRestaurant = businessType?.isRestaurant ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Staff Members',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () =>
                  _showAddStaffDialog(context, ref, isRestaurant),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Staff'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Role Permissions Card ──────────────────────────────────────
        _RolePermissionsCard(isRestaurant: isRestaurant),
        const SizedBox(height: 16),

        // ── Staff list (owners excluded) ───────────────────────────────
        staffAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (staff) {
            final nonOwners = staff
                .where((s) => s.role != StaffRole.owner)
                .toList();
            return nonOwners.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Center(
                      child: Text(
                        'No staff yet. Add your first staff member.',
                        style: TextStyle(
                            color: AppColors.textSecondary),
                      ),
                    ),
                  )
                : Column(
                    children: nonOwners
                        .map((s) => _StaffTile(
                              staff: s,
                              onEdit: () => _showEditStaffDialog(
                                  context, ref, s, isRestaurant),
                              onDelete: () =>
                                  _confirmDelete(context, ref, s),
                            ))
                        .toList(),
                  );
          },
        ),
      ],
    );
  }

  void _showAddStaffDialog(
      BuildContext context, WidgetRef ref, bool isRestaurant) {
    showDialog(
      context: context,
      builder: (ctx) => _StaffDialog(
        isRestaurant: isRestaurant,
        onSave: (name, role, pin) async {
          await ref
              .read(staffListProvider.notifier)
              .addStaff(name: name, role: role, pin: pin);
        },
      ),
    );
  }

  void _showEditStaffDialog(BuildContext context, WidgetRef ref,
      StaffMember staff, bool isRestaurant) {
    showDialog(
      context: context,
      builder: (ctx) => _StaffDialog(
        existing: staff,
        isRestaurant: isRestaurant,
        onSave: (name, role, pin) async {
          await ref.read(staffListProvider.notifier).updateStaff(
                id: staff.id,
                name: name,
                role: role,
                newPin: pin.isEmpty ? null : pin,
              );
        },
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, StaffMember staff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text('Remove ${staff.name} from staff?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(staffListProvider.notifier)
                  .deleteStaff(staff.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ── Role Permissions Card ─────────────────────────────────────────────────────

class _RolePermissionsCard extends ConsumerWidget {
  final bool isRestaurant;

  const _RolePermissionsCard({required this.isRestaurant});

  static const _tabLabels = <String, (String, IconData)>{
    'pos': ('POS', Icons.point_of_sale_rounded),
    'orders': ('Orders', Icons.receipt_long_rounded),
    'kitchen': ('Kitchen', Icons.kitchen_rounded),
    'inventory': ('Inventory', Icons.inventory_2_rounded),
    'utang': ('Utang', Icons.account_balance_wallet_outlined),
    'reports': ('Reports', Icons.bar_chart_rounded),
    'settings': ('Settings', Icons.settings_outlined),
  };

  static const _roleColors = {
    StaffRole.manager: Color(0xFF4CAF50),
    StaffRole.cashier: Color(0xFF2196F3),
    StaffRole.kitchen: Color(0xFFFF9800),
  };

  List<StaffRole> get _roles =>
      StaffRoleAvailability.forBusinessType(isRestaurant);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permsAsync = ref.watch(rolePermissionsProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Text('Tab Access by Role',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Spacer(),
                if (permsAsync.isLoading)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Owner always has full access.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          const Divider(height: 1),

          permsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading permissions: $e',
                  style: const TextStyle(color: Colors.red)),
            ),
            data: (perms) => Column(
              children: _roles.map((role) {
                final roleKey = role.key;
                final color = _roleColors[role] ?? Colors.grey;
                final roleTabs = perms[roleKey] ?? {};

                return ExpansionTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: color.withOpacity(0.15),
                    child: Text(
                      role.label[0],
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12),
                    ),
                  ),
                  title: Text(role.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    '${roleTabs.length} tab${roleTabs.length == 1 ? '' : 's'} enabled',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary),
                  ),
                  children: tabsForBusinessType(isRestaurant).map((tab) {
                    final info = _tabLabels[tab];
                    if (info == null) return const SizedBox.shrink();
                    final (label, icon) = info;
                    final enabled = roleTabs.contains(tab);

                    return SwitchListTile(
                      dense: true,
                      secondary: Icon(icon,
                          size: 18, color: AppColors.textSecondary),
                      title: Text(label,
                          style: const TextStyle(fontSize: 13)),
                      value: enabled,
                      activeColor: color,
                      onChanged: (_) => ref
                          .read(rolePermissionsProvider.notifier)
                          .toggle(roleKey, tab),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Staff tile ────────────────────────────────────────────────────────────────

class _StaffTile extends StatelessWidget {
  final StaffMember staff;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StaffTile({
    required this.staff,
    required this.onEdit,
    required this.onDelete,
  });

  static const _roleColors = {
    StaffRole.owner: Color(0xFFE94560),
    StaffRole.manager: Color(0xFF4CAF50),
    StaffRole.cashier: Color(0xFF2196F3),
    StaffRole.kitchen: Color(0xFFFF9800),
  };

  @override
  Widget build(BuildContext context) {
    final color = _roleColors[staff.role] ?? Colors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(0.15),
            child: Text(
              staff.name[0].toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(staff.role.label,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: AppColors.textSecondary,
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}

// ── Add/Edit dialog ───────────────────────────────────────────────────────────

class _StaffDialog extends StatefulWidget {
  final StaffMember? existing;
  final bool isRestaurant;
  final Future<void> Function(String name, StaffRole role, String pin)
      onSave;

  const _StaffDialog({
    this.existing,
    required this.isRestaurant,
    required this.onSave,
  });

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  late StaffRole _role;
  bool _saving = false;
  bool _showPin = false;

  @override
  void initState() {
    super.initState();
    final available =
        StaffRoleAvailability.forBusinessType(widget.isRestaurant);
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      // Clamp to a valid role for this business type
      _role = available.contains(widget.existing!.role)
          ? widget.existing!.role
          : available.first;
    } else {
      _role = available.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();
    if (name.isEmpty) return;
    if (!_isEdit && pin.length != 4) return;
    if (_isEdit && pin.isNotEmpty && pin.length != 4) return;

    setState(() => _saving = true);
    try {
      await widget.onSave(name, _role, pin);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableRoles =
        StaffRoleAvailability.forBusinessType(widget.isRestaurant);

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEdit ? 'Edit Staff' : 'Add Staff',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),

              const Text('Name',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'e.g. Juan dela Cruz',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              const Text('Role',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<StaffRole>(
                value: _role,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                items: availableRoles
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _role = v);
                },
              ),
              const SizedBox(height: 16),

              Text(
                _isEdit
                    ? 'New PIN (leave blank to keep)'
                    : '4-digit PIN',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _pinController,
                obscureText: !_showPin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  hintText: '••••',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(_showPin
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _showPin = !_showPin),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(_isEdit ? 'Save' : 'Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}