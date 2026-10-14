// Per-device kitchen alert preferences (SharedPreferences, like PrinterPrefsKeys).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KitchenSoundPrefsKeys {
  static const enabled = 'kitchen_sound_enabled'; // key absent = "auto"
  static const soundId = 'kitchen_sound_id';
  static const volume = 'kitchen_sound_volume';
  static const repeat = 'kitchen_sound_repeat';
  static const customPath = 'kitchen_sound_custom_path';
  static const customName = 'kitchen_sound_custom_name';
  static const seenKeys = 'kitchen_alert_seen_keys';
}

class BuiltInSound {
  final String id;
  final String label;
  const BuiltInSound(this.id, this.label);
  String get assetPath =>
      'sounds/$id.wav'; // AssetSource adds the "assets/" prefix
}

const kBuiltInSounds = <BuiltInSound>[
  BuiltInSound('kitchen_bell', 'Kitchen Bell'),
  BuiltInSound('loud_alarm', 'Loud Alarm'),
  BuiltInSound('service_bell', 'Restaurant Service Bell'),
  BuiltInSound('digital_beep', 'Digital Beep'),
  BuiltInSound('urgent_alert', 'Urgent Alert'),
  BuiltInSound('classic', 'Classic Notification'),
];
const kCustomSoundId = 'custom';
const kDefaultSoundId = 'kitchen_bell';

class KitchenSoundSettings {
  /// null = auto (ON for a dedicated kitchen device, OFF on a single device).
  final bool? enabledOverride;
  final String soundId;
  final double volume; // 0..1
  final int repeat; // 1..3
  final String? customPath;
  final String? customName;

  const KitchenSoundSettings({
    this.enabledOverride,
    this.soundId = kDefaultSoundId,
    this.volume = 1.0,
    this.repeat = 1,
    this.customPath,
    this.customName,
  });

  KitchenSoundSettings copyWith({
    bool? enabledOverride,
    String? soundId,
    double? volume,
    int? repeat,
    String? customPath,
    String? customName,
  }) => KitchenSoundSettings(
    enabledOverride: enabledOverride ?? this.enabledOverride,
    soundId: soundId ?? this.soundId,
    volume: volume ?? this.volume,
    repeat: repeat ?? this.repeat,
    customPath: customPath ?? this.customPath,
    customName: customName ?? this.customName,
  );
}

final kitchenSoundSettingsProvider =
    NotifierProvider<KitchenSoundSettingsNotifier, KitchenSoundSettings>(
      KitchenSoundSettingsNotifier.new,
    );

class KitchenSoundSettingsNotifier extends Notifier<KitchenSoundSettings> {
  Future<void>? _loading;
  bool _loaded = false;

  @override
  KitchenSoundSettings build() {
    ensureLoaded();
    return const KitchenSoundSettings();
  }

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      var customPath = p.getString(KitchenSoundPrefsKeys.customPath);
      if (customPath != null && !File(customPath).existsSync()) {
        debugPrint('[KitchenAlert] stored custom sound missing, ignoring');
        customPath = null;
      }
      var soundId =
          p.getString(KitchenSoundPrefsKeys.soundId) ?? kDefaultSoundId;
      final valid =
          kBuiltInSounds.any((b) => b.id == soundId) ||
          (soundId == kCustomSoundId && customPath != null);
      if (!valid) soundId = kDefaultSoundId;
      state = KitchenSoundSettings(
        enabledOverride: p.getBool(KitchenSoundPrefsKeys.enabled),
        soundId: soundId,
        volume:
            (p.getDouble(KitchenSoundPrefsKeys.volume) ?? 1.0)
                .clamp(0.0, 1.0)
                .toDouble(),
        repeat:
            (p.getInt(KitchenSoundPrefsKeys.repeat) ?? 1).clamp(1, 3).toInt(),
        customPath: customPath,
        customName: p.getString(KitchenSoundPrefsKeys.customName),
      );
    } catch (e) {
      debugPrint('[KitchenAlert] settings load failed, using defaults: $e');
    } finally {
      _loaded = true;
    }
  }

  Future<void> _update(
    KitchenSoundSettings next,
    Future<void> Function(SharedPreferences p) write,
  ) async {
    if (!_loaded) await ensureLoaded();
    state = next; // applied immediately, no restart needed
    try {
      await write(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('[KitchenAlert] settings save failed: $e');
    }
  }

  Future<void> setEnabled(bool v) async {
    if (!_loaded) await ensureLoaded();
    await _update(
      state.copyWith(enabledOverride: v),
      (p) => p.setBool(KitchenSoundPrefsKeys.enabled, v),
    );
  }

  Future<void> setSound(String id) async {
    if (!_loaded) await ensureLoaded();
    await _update(
      state.copyWith(soundId: id),
      (p) => p.setString(KitchenSoundPrefsKeys.soundId, id),
    );
  }

  Future<void> setVolume(double v) async {
    if (!_loaded) await ensureLoaded();
    final c = v.clamp(0.0, 1.0).toDouble();
    await _update(
      state.copyWith(volume: c),
      (p) => p.setDouble(KitchenSoundPrefsKeys.volume, c),
    );
  }

  Future<void> setRepeat(int n) async {
    if (!_loaded) await ensureLoaded();
    final c = n.clamp(1, 3).toInt();
    await _update(
      state.copyWith(repeat: c),
      (p) => p.setInt(KitchenSoundPrefsKeys.repeat, c),
    );
  }

  Future<void> setCustom(String path, String name) async {
    if (!_loaded) await ensureLoaded();
    await _update(
      state.copyWith(
        soundId: kCustomSoundId,
        customPath: path,
        customName: name,
      ),
      (p) async {
        await p.setString(KitchenSoundPrefsKeys.customPath, path);
        await p.setString(KitchenSoundPrefsKeys.customName, name);
        await p.setString(KitchenSoundPrefsKeys.soundId, kCustomSoundId);
      },
    );
  }

  /// Resets sound preferences only. Orders and the "seen alerts" list are untouched.
  Future<void> restoreDefaults() async {
    if (!_loaded) await ensureLoaded();
    final old = state.customPath;
    state = const KitchenSoundSettings();
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in [
        KitchenSoundPrefsKeys.enabled,
        KitchenSoundPrefsKeys.soundId,
        KitchenSoundPrefsKeys.volume,
        KitchenSoundPrefsKeys.repeat,
        KitchenSoundPrefsKeys.customPath,
        KitchenSoundPrefsKeys.customName,
      ]) {
        await p.remove(k);
      }
      if (old != null) {
        final f = File(old);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('[KitchenAlert] restore defaults error: $e');
    }
  }
}
