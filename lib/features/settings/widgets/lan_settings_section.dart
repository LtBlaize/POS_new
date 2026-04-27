import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/lan_client_service.dart';
import '../../../core/services/lan_config_service.dart';
import '../../../core/services/lan_server_service.dart';
import '../../../shared/widgets/app_colors.dart';

class LanSettingsSection extends ConsumerStatefulWidget {
  const LanSettingsSection({super.key});

  @override
  ConsumerState<LanSettingsSection> createState() => _LanSettingsSectionState();
}

class _LanSettingsSectionState extends ConsumerState<LanSettingsSection> {
  late TextEditingController _ipController;
  bool _saved = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: ref.read(savedPosIpProvider));
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ip = _ipController.text.trim();
    await ref.read(lanConfigServiceProvider).savePosIp(ip);
    ref.read(savedPosIpProvider.notifier).state = ip;
    ref.read(cashierIpProvider.notifier).state = ip;
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  Future<void> _clear() async {
    await ref.read(lanConfigServiceProvider).clearPosIp();
    ref.read(savedPosIpProvider.notifier).state = '';
    ref.read(cashierIpProvider.notifier).state = '';
    _ipController.clear();
  }

  Future<void> _testConnection() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    setState(() => _testing = true);
    ref.read(cashierIpProvider.notifier).state = ip;
    final ok = await ref.read(lanClientServiceProvider).ping();
    setState(() => _testing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '✓ Connected to POS at $ip'
          : '✗ Cannot reach POS at $ip — check IP and WiFi'),
      backgroundColor: ok ? AppColors.success : Colors.red,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final localIpAsync = ref.watch(localIpProvider);
    final serverRunning = ref.watch(lanServerServiceProvider).isRunning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ───────────────────────────────────────────────
        const Text(
          'LAN Connection',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'For kitchen display communication over local WiFi.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),

        // ── This device's IP (shown so kitchen can copy it) ──────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'This device IP: ',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              localIpAsync.when(
                data: (ip) => SelectableText(
                  ip,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
                loading: () => const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) => const Text('Unavailable',
                    style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              // POS server status dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: serverRunning ? AppColors.success : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                serverRunning ? 'Server running' : 'Server off',
                style: TextStyle(
                  fontSize: 11,
                  color: serverRunning
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── POS IP input (used by kitchen device) ────────────────────────
        const Text(
          'POS IP Address',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        const Text(
          'On the kitchen device, enter the IP shown above from the POS device.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ipController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: '192.168.1.100',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: _clear,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _save,
              icon: Icon(
                  _saved ? Icons.check : Icons.save_outlined,
                  size: 16),
              label: Text(_saved ? 'Saved!' : 'Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _saved ? AppColors.success : AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check, size: 16),
            label: Text(_testing ? 'Testing...' : 'Test connection'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}