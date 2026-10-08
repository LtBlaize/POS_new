// lib/features/auth/business_type_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'register_screen.dart';
import 'plan_picker_screen.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/business_type_card.dart';
import 'widgets/auth_theme.dart';
import 'widgets/auth_components.dart';// for DeviceRole + deviceRoleProvider

class BusinessTypeScreen extends ConsumerStatefulWidget {
  const BusinessTypeScreen({super.key});

  @override
  ConsumerState<BusinessTypeScreen> createState() => _BusinessTypeScreenState();
}

class _BusinessTypeScreenState extends ConsumerState<BusinessTypeScreen> {
  final _formKey          = GlobalKey<FormState>();
  final _fullNameCtrl     = TextEditingController();
  final _businessNameCtrl = TextEditingController();

  String? _selectedType;
  String? _error;

  static const _options = [
    _BusinessOption(
      type: 'restaurant',
      label: 'Restaurant / Food Service',
      description: 'Table management, kitchen display, dine-in & takeout orders.',
      icon: Icons.restaurant_rounded,
    ),
    _BusinessOption(
      type: 'retail',
      label: 'Retail Store',
      description: 'Barcode scanning, inventory tracking, walk-in sales.',
      icon: Icons.storefront_rounded,
    ),
  ];

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _businessNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a business type.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final userId = ref.read(pendingUserIdProvider);
    if (userId == null) {
      setState(() => _error = 'Session expired. Please register again.');
      return;
    }

    // Store everything the plan picker will need.
    ref.read(pendingFullNameProvider.notifier).state     = _fullNameCtrl.text.trim();
    ref.read(pendingBusinessNameProvider.notifier).state = _businessNameCtrl.text.trim();
    ref.read(pendingBusinessTypeProvider.notifier).state = _selectedType;

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlanPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      maxWidth: 520,
      onBack: () => Navigator.pop(context),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthStepper(current: 2, label: 'Business details'),
            const SizedBox(height: 24),
            const Text('Set up your business', style: AuthText.title),
            const SizedBox(height: 24),

            AuthTextField(
              label: 'YOUR FULL NAME',
              hint: 'Juan dela Cruz',
              controller: _fullNameCtrl,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.person_outline_rounded,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 16),
            AuthTextField(
              label: 'BUSINESS NAME',
              hint: "Juan's Eatery",
              controller: _businessNameCtrl,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.business_outlined,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter business name' : null,
            ),
            const SizedBox(height: 24),

            const Text('BUSINESS TYPE', style: AuthText.label),
            const SizedBox(height: 10),

            ..._options.map((opt) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BusinessTypeCard(
                    type: opt.type,
                    label: opt.label,
                    description: opt.description,
                    icon: opt.icon,
                    isSelected: _selectedType == opt.type,
                    onTap: () => setState(() => _selectedType = opt.type),
                  ),
                )),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AuthColors.field,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AuthColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded,
                      color: AuthColors.textMuted, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('More business types coming soon',
                        style: TextStyle(
                            fontSize: 13, color: AuthColors.textMuted)),
                  ),
                ],
              ),
            ),

            AuthErrorSlot(_error),
            const SizedBox(height: 24),

            AuthButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _BusinessOption {
  final String   type;
  final String   label;
  final String   description;
  final IconData icon;

  const _BusinessOption({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
  });
}

