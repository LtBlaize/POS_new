import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings_provider.dart';
import '../../../core/models/business.dart';
import '../../../shared/widgets/app_colors.dart';

class GeneralSettingsSection extends ConsumerStatefulWidget {
  final Business business;
  const GeneralSettingsSection({super.key, required this.business});

  @override
  ConsumerState<GeneralSettingsSection> createState() =>
      _GeneralSettingsSectionState();
}

class _GeneralSettingsSectionState
    extends ConsumerState<GeneralSettingsSection> {
  final _taxController = TextEditingController();
  final _footerController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _taxController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  void _initFromConfig(BusinessConfig config) {
    if (_initialized) return;
    _taxController.text = config.taxRate.toString();
    _footerController.text = config.receiptFooter ?? '';
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsProvider);
    final config = settingsState.config;

    if (config == null) {
      return const Center(child: CircularProgressIndicator());
    }

    _initFromConfig(config);

    final isRestaurant = widget.business.businessType.isRestaurant;
    final isRetail = widget.business.businessType.isRetail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Business info (read-only) ───────────────────────────────────
        _SettingGroup(
          title: 'Business',
          icon: Icons.store_outlined,
          children: [
            _InfoRow(label: 'Name', value: widget.business.name),
            _InfoRow(
                label: 'Type',
                value: widget.business.businessType.displayName),
            _InfoRow(label: 'Currency', value: widget.business.currency),
            _InfoRow(
                label: 'Plan',
                value: widget.business.subscriptionPlan.displayName),
          ],
        ),
        const SizedBox(height: 16),

        // ── Pricing ─────────────────────────────────────────────────────
        _SettingGroup(
          title: 'Pricing',
          icon: Icons.percent_rounded,
          children: [
            _TextFieldRow(
              label: 'Tax rate (%)',
              controller: _taxController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              hint: '0.00',
            ),
            _SwitchRow(
              label: 'Allow discounts',
              value: config.allowDiscounts,
              onChanged: (v) => _save(config.copyWith(allowDiscounts: v)),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Receipt ─────────────────────────────────────────────────────
        _SettingGroup(
          title: 'Receipt',
          icon: Icons.receipt_outlined,
          children: [
            _TextFieldRow(
              label: 'Footer text',
              controller: _footerController,
              hint: 'e.g. Thank you for dining with us!',
              maxLines: 2,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Restaurant settings ──────────────────────────────────────────
        if (isRestaurant) ...[
          _SettingGroup(
            title: 'Service',
            icon: Icons.room_service_outlined,
            children: [
              _SwitchRow(
                label: 'Require table on every order',
                sublabel: 'Order cannot be placed without a table selected',
                value: config.requireTableOnOrder,
                onChanged: (v) =>
                    _save(config.copyWith(requireTableOnOrder: v)),
              ),
              _SwitchRow(
                label: 'Enable kitchen display',
                sublabel: 'Send orders to KDS screen',
                value: config.enableKitchenDisplay,
                onChanged: (v) =>
                    _save(config.copyWith(enableKitchenDisplay: v)),
              ),
              _SwitchRow(
                label: 'Enable table management',
                sublabel: 'Show table selector in POS',
                value: config.enableTableManagement,
                onChanged: (v) =>
                    _save(config.copyWith(enableTableManagement: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // ── Retail settings ──────────────────────────────────────────────
        if (isRetail) ...[
          _SettingGroup(
            title: 'Inventory',
            icon: Icons.inventory_2_outlined,
            children: [
              _SwitchRow(
                label: 'Enable barcode scanner',
                value: config.enableBarcodeScanner,
                onChanged: (v) =>
                    _save(config.copyWith(enableBarcodeScanner: v)),
              ),
              _SwitchRow(
                label: 'Enable low stock alerts',
                value: config.enableInventoryAlerts,
                onChanged: (v) =>
                    _save(config.copyWith(enableInventoryAlerts: v)),
              ),
              if (config.enableInventoryAlerts)
                _TextFieldRow(
                  label: 'Low stock threshold',
                  controller: TextEditingController(
                      text: config.lowStockThreshold.toString()),
                  keyboardType: TextInputType.number,
                  hint: '5',
                  onSubmitted: (v) {
                    final n = int.tryParse(v);
                    if (n != null) _save(config.copyWith(lowStockThreshold: n));
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // ── Save button ──────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: settingsState.isSaving ? null : () => _saveAll(config),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: settingsState.isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save changes',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  void _save(BusinessConfig config) {
    ref.read(settingsProvider.notifier).saveConfig(config);
  }

  void _saveAll(BusinessConfig config) {
    final taxRate =
        double.tryParse(_taxController.text.trim()) ?? config.taxRate;
    final footer = _footerController.text.trim();

    _save(config.copyWith(
      taxRate: taxRate,
      receiptFooter: footer.isEmpty ? null : footer,
    ));
  }
}

// ── Small shared widgets ──────────────────────────────────────────────────────

class _SettingGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingGroup({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: children
                .map((child) => Column(
                      children: [
                        child,
                        if (child != children.last)
                          Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: AppColors.divider),
                      ],
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    this.sublabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                if (sublabel != null) ...[
                  const SizedBox(height: 2),
                  Text(sublabel!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ]
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _TextFieldRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;

  const _TextFieldRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: maxLines,
              onSubmitted: onSubmitted,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}