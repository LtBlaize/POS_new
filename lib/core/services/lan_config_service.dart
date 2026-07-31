
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';

final localIpProvider = FutureProvider<String>((ref) async {
  try {
    final ip = await NetworkInfo().getWifiIP();
    return ip ?? 'Unavailable';
  } catch (_) {
    return 'Unavailable';
  }
});

