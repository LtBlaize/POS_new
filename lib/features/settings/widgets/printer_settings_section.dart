// lib/features/settings/widgets/printer_settings_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/app_colors.dart';

// ── Prefs keys ────────────────────────────────────────────────────────────────
const _kIs58mm        = 'printer_is_58mm';
const _kPrinterName   = 'printer_selected_name';
const _kPrinterUrl    = 'printer_selected_url';

// ── Provider ──────────────────────────────────────────────────────────────────
final printerSettingsProvider =
    StateNotifierProvider<PrinterSettingsNotifier, PrinterSettingsState>((ref) {
  return PrinterSettingsNotifier();
});

// ── State ─────────────────────────────────────────────────────────────────────
class PrinterSettingsState {
  final bool is58mm;
  final String? selectedPrinterName;
  final String? selectedPrinterUrl;
  final List<Printer> availablePrinters;
  final bool isLoadingPrinters;

  const PrinterSettingsState({
    this.is58mm = false,
    this.selectedPrinterName,
    this.selectedPrinterUrl,
    this.availablePrinters = const [],
    this.isLoadingPrinters = false,
  });

  PrinterSettingsState copyWith({
    bool? is58mm,
    String? selectedPrinterName,
    String? selectedPrinterUrl,
    List<Printer>? availablePrinters,
    bool? isLoadingPrinters,
  }) =>
      PrinterSettingsState(
        is58mm: is58mm ?? this.is58mm,
        selectedPrinterName: selectedPrinterName ?? this.selectedPrinterName,
        selectedPrinterUrl: selectedPrinterUrl ?? this.selectedPrinterUrl,
        availablePrinters: availablePrinters ?? this.availablePrinters,
        isLoadingPrinters: isLoadingPrinters ?? this.isLoadingPrinters,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────
class PrinterSettingsNotifier extends StateNotifier<PrinterSettingsState> {
  PrinterSettingsNotifier() : super(const PrinterSettingsState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      is58mm: prefs.getBool(_kIs58mm) ?? false,
      selectedPrinterName: prefs.getString(_kPrinterName),
      selectedPrinterUrl: prefs.getString(_kPrinterUrl),
    );
  }

  Future<void> setIs58mm(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIs58mm, value);
    state = state.copyWith(is58mm: value);
  }

  Future<void> selectPrinter(Printer printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrinterName, printer.name);
    await prefs.setString(_kPrinterUrl, printer.url.toString());
    state = state.copyWith(
      selectedPrinterName: printer.name,
      selectedPrinterUrl: printer.url.toString(),
    );
  }

  Future<void> clearPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrinterName);
    await prefs.remove(_kPrinterUrl);
    state = PrinterSettingsState(
      is58mm: state.is58mm,
      availablePrinters: state.availablePrinters,
    );
  }

  Future<void> refreshPrinters() async {
    state = state.copyWith(isLoadingPrinters: true);
    try {
      final printers = await Printing.listPrinters();
      state = state.copyWith(
        availablePrinters: printers,
        isLoadingPrinters: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingPrinters: false);
    }
  }
}

// ── Widget ────────────────────────────────────────────────────────────────────
class PrinterSettingsSection extends ConsumerStatefulWidget {
  const PrinterSettingsSection({super.key});

  @override
  ConsumerState<PrinterSettingsSection> createState() =>
      _PrinterSettingsSectionState();
}

class _PrinterSettingsSectionState
    extends ConsumerState<PrinterSettingsSection> {
  @override
  void initState() {
    super.initState();
    // Load printer list on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(printerSettingsProvider.notifier).refreshPrinters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(printerSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────────────────
        _SettingGroup(
          title: 'Printer',
          icon: Icons.print_outlined,
          children: [
            // Paper width toggle
            _SwitchRow(
              label: 'Use 58mm paper roll',
              sublabel: 'Default is 80mm. Enable only for narrower rolls.',
              value: settings.is58mm,
              onChanged: (v) =>
                  ref.read(printerSettingsProvider.notifier).setIs58mm(v),
            ),

            // Selected printer display
            _PrinterRow(
              selectedName: settings.selectedPrinterName,
              onClear: () =>
                  ref.read(printerSettingsProvider.notifier).clearPrinter(),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Printer list ───────────────────────────────────────────────
        _SettingGroup(
          title: 'Available Printers',
          icon: Icons.devices_rounded,
          trailing: IconButton(
            icon: settings.isLoadingPrinters
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded,
                    size: 18, color: AppColors.primary),
            onPressed: settings.isLoadingPrinters
                ? null
                : () => ref
                    .read(printerSettingsProvider.notifier)
                    .refreshPrinters(),
            tooltip: 'Refresh printers',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          children: settings.isLoadingPrinters
              ? [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                ]
              : settings.availablePrinters.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        child: Text(
                          'No printers found. Make sure your printer is on and connected.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                      )
                    ]
                  : settings.availablePrinters.map((printer) {
                      final isSelected =
                          printer.name == settings.selectedPrinterName;
                      return _PrinterListTile(
                        printer: printer,
                        isSelected: isSelected,
                        onTap: () => ref
                            .read(printerSettingsProvider.notifier)
                            .selectPrinter(printer),
                      );
                    }).toList(),
        ),
      ],
    );
  }
}

// ── Selected printer row ──────────────────────────────────────────────────────
class _PrinterRow extends StatelessWidget {
  final String? selectedName;
  final VoidCallback onClear;

  const _PrinterRow({required this.selectedName, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.print_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Selected printer',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  selectedName ?? 'None — tap a printer below to select',
                  style: TextStyle(
                      fontSize: 11,
                      color: selectedName != null
                          ? AppColors.primary
                          : AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (selectedName != null)
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

// ── Printer list tile ─────────────────────────────────────────────────────────
class _PrinterListTile extends StatelessWidget {
  final Printer printer;
  final bool isSelected;
  final VoidCallback onTap;

  const _PrinterListTile({
    required this.printer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color:
                  isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(printer.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textPrimary)),
                  if (printer.url.toString().isNotEmpty)
                    Text(printer.url.toString(),
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded,
                  size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// ── Reusable sub-widgets (mirrors general_settings_section style) ─────────────
class _SettingGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  const _SettingGroup({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
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
            if (trailing != null) ...[
              const Spacer(),
              trailing!,
            ],
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
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}