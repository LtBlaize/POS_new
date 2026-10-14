// Audio playback + custom-sound import + the dedupe engine that decides
// WHEN a kitchen alert should sound.
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/order.dart';
import 'kitchen_sound_settings.dart';

class SoundImportResult {
  final String? path;
  final String? name;
  final String? error;
  final bool cancelled;
  const SoundImportResult._(this.path, this.name, this.error, this.cancelled);
  const SoundImportResult.ok(String path, String name)
    : this._(path, name, null, false);
  const SoundImportResult.fail(String error) : this._(null, null, error, false);
  const SoundImportResult.cancelled() : this._(null, null, null, true);
}

// ── Audio ──────────────────────────────────────────────────────────────────

class KitchenAlertService {
  AudioPlayer? _player; // created lazily so tests never touch the plugin
  int _gen = 0;
  bool _busy = false;

  static const _maxBytes = 5 * 1024 * 1024;
  static const _allowedExt = {'wav', 'mp3', 'ogg'};

  Future<AudioPlayer> _ensurePlayer() async {
    var player = _player;
    if (player == null) {
      player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      _player = player;
    }
    return player;
  }

  Future<void> _resetPlayer() async {
    final old = _player;
    _player = null;
    try {
      await old?.dispose();
    } catch (_) {}
  }

  Source _sourceFor(KitchenSoundSettings s) {
    if (s.soundId == kCustomSoundId &&
        s.customPath != null &&
        File(s.customPath!).existsSync()) {
      return DeviceFileSource(s.customPath!);
    }
    final id =
        kBuiltInSounds.any((b) => b.id == s.soundId)
            ? s.soundId
            : kDefaultSoundId;
    return AssetSource('sounds/$id.wav');
  }

  Future<void> _playOnce(Source src, double volume) async {
    final player = await _ensurePlayer();
    final done = player.onPlayerComplete.first.catchError((_) {});
    await player.setVolume(volume);
    await player.play(src);
    await done.timeout(const Duration(seconds: 20), onTimeout: () {});
  }

  /// Plays the alert (honouring volume + repeat). Never throws.
  /// Returns a warning/error message for the UI, or null on success.
  /// A real alert is skipped while another is playing (no overlap);
  /// a preview pre-empts whatever is playing.
  Future<String?> play(KitchenSoundSettings s, {bool preview = false}) async {
    if (_busy && !preview) {
      debugPrint('[KitchenAlert] skipped: alert already playing');
      return null;
    }
    final gen = ++_gen;
    _busy = true;
    String? warning;
    try {
      try {
        await _player?.stop();
      } catch (_) {}

      var source = _sourceFor(s);
      if (s.soundId == kCustomSoundId && source is! DeviceFileSource) {
        warning = 'Custom sound file is missing. Using the default sound.';
      }
      for (var i = 0; i < s.repeat; i++) {
        if (gen != _gen) return warning;
        try {
          await _playOnce(source, s.volume);
        } catch (e) {
          debugPrint('[KitchenAlert] playback failed: $e');
          if (source is DeviceFileSource) {
            warning =
                'Custom sound could not be played. Using the default sound.';
            source = AssetSource('sounds/$kDefaultSoundId.wav');
            try {
              await _playOnce(source, s.volume);
            } catch (e2) {
              await _resetPlayer();
              return 'Audio playback failed: $e2';
            }
          } else {
            await _resetPlayer(); // recreate the player (e.g. after long idle)
            return 'Audio playback failed: $e';
          }
        }
        if (i < s.repeat - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    } catch (e) {
      debugPrint('[KitchenAlert] unexpected audio error: $e');
      return 'Audio playback failed: $e';
    } finally {
      if (gen == _gen) _busy = false;
    }
    return warning;
  }

  // ── Custom sound import ──────────────────────────────────────────────────

  /// Checks the file's magic bytes against its extension. Returns an error or null.
  @visibleForTesting
  static String? validateHeader(List<int> b, String ext) {
    if (b.length < 4) return 'File is empty or too small to be audio.';
    bool at(int o, String t) {
      if (b.length < o + t.length) return false;
      for (var i = 0; i < t.length; i++) {
        if (b[o + i] != t.codeUnitAt(i)) return false;
      }
      return true;
    }

    switch (ext) {
      case 'wav':
        return (at(0, 'RIFF') && at(8, 'WAVE'))
            ? null
            : 'Not a valid WAV file.';
      case 'mp3':
        return (at(0, 'ID3') || (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0))
            ? null
            : 'Not a valid MP3 file.';
      case 'ogg':
        return at(0, 'OggS') ? null : 'Not a valid OGG file.';
    }
    return 'Unsupported format .$ext. Use WAV, MP3 or OGG.';
  }

  Future<String?> _probe(String path) async {
    final probe = AudioPlayer();
    try {
      await probe
          .setSource(DeviceFileSource(path))
          .timeout(const Duration(seconds: 5));
      final d = await probe.getDuration();
      if (d != null && d > const Duration(seconds: 30)) {
        return 'Sound is longer than 30 seconds. Choose a shorter clip.';
      }
      return null;
    } catch (_) {
      return 'This file could not be decoded on this device (unsupported codec?).';
    } finally {
      try {
        await probe.dispose();
      } catch (_) {}
    }
  }

  /// Picks a file, validates it, copies it into the app-managed folder.
  /// The file is only ever handed to the audio decoder, never executed.
  Future<SoundImportResult> importCustom() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'ogg'],
      );
    } catch (e) {
      return SoundImportResult.fail('Could not open the file picker: $e');
    }
    final path = res?.files.single.path;
    if (path == null) return const SoundImportResult.cancelled();

    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!_allowedExt.contains(ext)) {
      return SoundImportResult.fail(
        'Unsupported format .$ext. Use WAV, MP3 or OGG.',
      );
    }
    try {
      final src = File(path);
      final len = await src.length();
      if (len == 0 || len > _maxBytes) {
        return const SoundImportResult.fail(
          'Audio file must be between 1 byte and 5 MB.',
        );
      }
      final head = await src.openRead(0, 12).expand((c) => c).toList();
      final bad = validateHeader(head, ext);
      if (bad != null) return SoundImportResult.fail(bad);

      final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'kitchen_sounds'),
      );
      await dir.create(recursive: true);
      final dest = p.join(
        dir.path,
        'custom_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await src.copy(dest);

      final loadErr = await _probe(dest);
      if (loadErr != null) {
        try {
          await File(dest).delete();
        } catch (_) {}
        return SoundImportResult.fail(loadErr);
      }
      await for (final f in dir.list()) {
        if (f is File && f.path != dest) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      return SoundImportResult.ok(dest, p.basename(path));
    } catch (e) {
      return SoundImportResult.fail('Could not import this file: $e');
    }
  }

  void dispose() {
    _gen++;
    _player?.dispose();
    _player = null;
  }
}

final kitchenAlertServiceProvider = Provider<KitchenAlertService>((ref) {
  final s = KitchenAlertService();
  ref.onDispose(s.dispose);
  return s;
});

// ── Dedupe engine ──────────────────────────────────────────────────────────

class KitchenAlertEngine {
  KitchenAlertEngine(this._ref);
  final Ref _ref;

  final LinkedHashSet<String> _seen = LinkedHashSet<String>();
  Future<void>? _seenLoading;
  DateTime? _baselineUntil;

  /// For the first [baselineWindow] after the kitchen screen mounts, orders
  /// older than [_recentOrder] are marked seen silently (restart protection).
  @visibleForTesting
  Duration baselineWindow = const Duration(seconds: 15);
  static const _recentOrder = Duration(minutes: 5);
  static const _maxSeen = 500;

  void resetSession() => _baselineUntil = DateTime.now().add(baselineWindow);

  static bool hasKitchenItems(Iterable<CartItem> items) => items.any(
    (i) =>
        i.isPromo
            ? (i.promoComponents?.any((c) => c.sendToKitchen) ?? false)
            : i.product.sendToKitchen,
  );

  Future<void> _ensureSeen() =>
      _seenLoading ??= () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          _seen.addAll(
            prefs.getStringList(KitchenSoundPrefsKeys.seenKeys) ?? const [],
          );
        } catch (e) {
          debugPrint('[KitchenAlert] seen-keys load failed: $e');
        }
      }();

  Future<void> _persistSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(KitchenSoundPrefsKeys.seenKeys, _seen.toList());
    } catch (e) {
      debugPrint('[KitchenAlert] seen-keys save failed: $e');
    }
  }

  void _remember(String key) {
    _seen.add(key);
    while (_seen.length > _maxSeen) {
      _seen.remove(_seen.first);
    }
  }

  /// Call with every order snapshot the kitchen device receives.
  /// [autoEnabled]: default ON/OFF when the user hasn't chosen.
  /// [allowed]: hard gate (false = never alert from this call site).
  /// Never throws; never blocks the caller's UI update.
  Future<void> handleSnapshot(
    List<Order> orders, {
    required String source,
    required bool autoEnabled,
    bool allowed = true,
  }) async {
    try {
      await _ensureSeen();
      await _ref.read(kitchenSoundSettingsProvider.notifier).ensureLoaded();
      final settings = _ref.read(kitchenSoundSettingsProvider);

      final now = DateTime.now();
      _baselineUntil ??= now.add(baselineWindow);
      final inBaseline = now.isBefore(_baselineUntil!);

      var fresh = 0;
      var dupes = 0;
      var changed = false;

      for (final o in orders) {
        final rounds = <int, List<CartItem>>{};
        for (final i in o.items) {
          rounds.putIfAbsent(i.round, () => []).add(i);
        }
        for (final e in rounds.entries) {
          final key = '${o.id}:r${e.key}';
          if (_seen.contains(key)) {
            dupes++;
            continue;
          }
          _remember(key);
          changed = true;

          final pending = e.value.any((i) => i.kitchenStatus == 'pending');
          if (!pending || !hasKitchenItems(e.value)) {
            debugPrint(
              '[KitchenAlert] [$source] no alert for $key (not pending / no kitchen items)',
            );
            continue;
          }
          if (inBaseline && now.difference(o.createdAt) > _recentOrder) {
            debugPrint(
              '[KitchenAlert] [$source] startup baseline, no alert for old $key',
            );
            continue;
          }
          fresh++;
        }
      }
      if (changed) unawaited(_persistSeen());

      if (fresh == 0) {
        if (dupes > 0)
          debugPrint(
            '[KitchenAlert] [$source] duplicate snapshot ignored ($dupes known rounds)',
          );
        return;
      }
      final enabled = allowed && (settings.enabledOverride ?? autoEnabled);
      if (!enabled) {
        debugPrint(
          '[KitchenAlert] [$source] $fresh new round(s), alerts disabled -> skipped',
        );
        return;
      }
      debugPrint(
        '[KitchenAlert] [$source] $fresh new kitchen round(s) -> playing alert',
      );
      final warn = await _ref.read(kitchenAlertServiceProvider).play(settings);
      if (warn != null) debugPrint('[KitchenAlert] $warn');
    } catch (e) {
      debugPrint('[KitchenAlert] engine error (ignored, order unaffected): $e');
    }
  }
}

final kitchenAlertEngineProvider = Provider<KitchenAlertEngine>(
  (ref) => KitchenAlertEngine(ref),
);
