// Run from project root:  dart run tool/generate_sounds.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sr = 44100;
const double twoPi = 2 * math.pi;

List<double> silence(double sec) =>
    List<double>.filled((sec * sr).round(), 0.0);

List<double> cat(List<List<double>> parts) => [for (final p in parts) ...p];

List<double> bell(double f, double sec, {double decay = 3.0}) {
  const ratios = [1.0, 2.76, 5.40, 8.93];
  const amps = [1.0, 0.6, 0.35, 0.2];
  final n = (sec * sr).round();
  return List.generate(n, (i) {
    final t = i / sr;
    var v = 0.0;
    for (var k = 0; k < ratios.length; k++) {
      v +=
          amps[k] *
          math.sin(twoPi * f * ratios[k] * t) *
          math.exp(-t * decay * (1 + k * 0.6));
    }
    return v;
  });
}

List<double> tone(
  double f,
  double sec, {
  bool square = false,
  double decay = 0,
}) {
  final n = (sec * sr).round();
  return List.generate(n, (i) {
    final t = i / sr;
    var v = math.sin(twoPi * f * t);
    if (square) v = v >= 0 ? 0.6 : -0.6;
    final att = math.min(1.0, t / 0.005);
    final rel = math.min(1.0, (sec - t) / 0.01);
    return v * att * rel * (decay > 0 ? math.exp(-t * decay) : 1.0);
  });
}

List<double> sweep(double f0, double f1, double sec) {
  final n = (sec * sr).round();
  var phase = 0.0;
  return List.generate(n, (i) {
    final f = f0 + (f1 - f0) * (i / n);
    phase += twoPi * f / sr;
    final v = math.sin(phase) >= 0 ? 0.6 : -0.6;
    final env = math.min(
      1.0,
      math.min(i / (0.005 * sr), (n - i) / (0.01 * sr)),
    );
    return v * env;
  });
}

void save(String name, List<double> s) {
  var peak = 0.0;
  for (final v in s) {
    if (v.abs() > peak) peak = v.abs();
  }
  final gain = peak == 0 ? 1.0 : 0.95 / peak;
  final fade = (0.015 * sr).round();
  final data = ByteData(44 + s.length * 2);
  void str(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      data.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + s.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sr, Endian.little);
  data.setUint32(28, sr * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, s.length * 2, Endian.little);
  for (var i = 0; i < s.length; i++) {
    var v = s[i] * gain;
    final fromEnd = s.length - i;
    if (fromEnd < fade) v *= fromEnd / fade;
    data.setInt16(
      44 + i * 2,
      (v.clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  File('assets/sounds/$name.wav').writeAsBytesSync(data.buffer.asUint8List());
  stdout.writeln('wrote assets/sounds/$name.wav');
}

void main() {
  Directory('assets/sounds').createSync(recursive: true);
  save('kitchen_bell', bell(880, 1.6, decay: 2.5));
  save(
    'service_bell',
    cat([
      bell(1568, 0.8, decay: 4),
      silence(0.12),
      bell(1568, 1.0, decay: 3.5),
    ]),
  );
  save(
    'loud_alarm',
    cat([
      for (var i = 0; i < 6; i++)
        tone(i.isEven ? 960 : 720, 0.25, square: true),
    ]),
  );
  save(
    'digital_beep',
    cat([
      for (var i = 0; i < 3; i++) ...[
        tone(1000, 0.12, square: true),
        silence(0.08),
      ],
    ]),
  );
  save(
    'urgent_alert',
    cat([
      for (var i = 0; i < 4; i++) ...[sweep(700, 1500, 0.22), silence(0.05)],
    ]),
  );
  save(
    'classic',
    cat([tone(659.25, 0.18, decay: 3), tone(523.25, 0.45, decay: 3)]),
  );
}
