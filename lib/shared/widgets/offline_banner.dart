// lib/shared/widgets/offline_banner.dart
//
// Slim banner shown at the top of every screen.
// Reads ConnectivityStatus which combines internet + LAN probes.
//
// States:
//   full         → hidden (no banner)
//   lanOnly      → amber  "No internet — orders still flowing locally"
//   internetOnly → blue   "POS not found on local network"
//   none         → red    "No internet and POS unreachable"

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_queue_service.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityStatusProvider);
    final pendingCount = ref.watch(pendingQueueCountProvider);
    final isSyncing = ref.watch(isSyncingProvider);

    if (status == ConnectivityStatus.full && pendingCount == 0) {
      return const SizedBox.shrink();
    }

    // When back online and syncing
    if (status == ConnectivityStatus.full && pendingCount > 0) {
      return _BannerContainer(
        color: Colors.blue.shade700,
        icon: Icons.sync,
        spin: isSyncing,
        message: isSyncing
            ? 'Syncing $pendingCount item${pendingCount == 1 ? '' : 's'} to cloud...'
            : '$pendingCount item${pendingCount == 1 ? '' : 's'} pending sync',
      );
    }

    final (color, icon, message) = switch (status) {
      ConnectivityStatus.lanOnly => (
          Colors.orange.shade700,
          Icons.cloud_off_outlined,
          pendingCount > 0
              ? 'No internet — $pendingCount item${pendingCount == 1 ? '' : 's'} will sync when reconnected'
              : 'No internet — orders flowing locally only',
        ),
      ConnectivityStatus.internetOnly => (
          Colors.blue.shade600,
          Icons.wifi_off_outlined,
          'POS not found on local network — check both devices are on the same WiFi',
        ),
      ConnectivityStatus.none => (
          Colors.red.shade700,
          Icons.signal_wifi_statusbar_connected_no_internet_4_outlined,
          'No internet and POS unreachable — orders cannot be sent to kitchen',
        ),
      ConnectivityStatus.full => (Colors.transparent, Icons.check, ''),
    };

    return _BannerContainer(
      color: color,
      icon: icon,
      message: message,
    );
  }
}

class _BannerContainer extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String message;
  final bool spin;

  const _BannerContainer({
    required this.color,
    required this.icon,
    required this.message,
    this.spin = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
      child: Row(
        children: [
          spin
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}