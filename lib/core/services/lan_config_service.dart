import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final lanConfigServiceProvider = Provider<LanConfigService>((ref) {
  return LanConfigService();
});

final savedPosIpProvider = StateProvider<String>((ref) => '');

final localIpProvider = FutureProvider<String>((ref) async {
  try {
    final ip = await NetworkInfo().getWifiIP();
    return ip ?? 'Unavailable';
  } catch (_) {
    return 'Unavailable';
  }
});

class LanConfigService {
  static const _key = 'pos_ip';

  Future<String> loadPosIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? '';
  }

  Future<void> savePosIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, ip);
    debugPrint('[LanConfig] Saved POS IP: $ip');
  }

  Future<void> clearPosIp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}