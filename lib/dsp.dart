import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

double clampD(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double toDb(double x) => 20 * log(x) / ln10;
String sg(double v) => '${v > 0 ? '+' : v < 0 ? '−' : ''}${v.abs().toStringAsFixed(1)} dB';
String fmt(double s) => '${s ~/ 60}:${(s.floor() % 60).toString().padLeft(2, '0')}';

class ParamDef {
  final String label, sub;
  final double min, max;
  const ParamDef(this.label, this.min, this.max, this.sub);
}

const kDefs = [
  ParamDef('INPUT', -12, 12, 'Trim'),
  ParamDef('EQ HIGH', -12, 12, '12 kHz'),
  ParamDef('EQ MID', -12, 12, '1 kHz'),
  ParamDef('COMP', -40, 0, '3:1 · 10 ms'),
  ParamDef('OUTPUT', -12, 6, 'Limiter −1 dB'),
];

/// Thứ tự: input, eqHigh, eqMid, compThreshold, output (dB)
const kDefault = [-2.1, 1.5, -1.8, -4.0, -0.3];
const kPresets = <String, List<double>>{
  'Default': kDefault,
  'Punchy': [0, 2.5, 1.5, -14, -0.5],
  'Warm': [-1, -2.5, 1.0, -8, -0.3],
  'Clean': [0, 1, -1, -2, -0.1],
};

class Params {
  List<double> v;
  Params(this.v);
  factory Params.defaults() => Params(List.of(kDefault));
  double get inp => v[0];
  double get hi => v[1];
  double get mid => v[2];
  double get comp => v[3];
  double get out => v[4];
}

class AutoResult {
  final Params params;
  final double rmsDb, crestDb;
  AutoResult(this.params, this.rmsDb, this.crestDb);
}

/// Phân tích PCM mono (11025 Hz) và đề xuất thông số mastering.
AutoResult autoMaster(Float32List a) {
  double s = 0, ds = 0, pk = 0, pv = 0;
  for (final x in a) {
    s += x * x;
    final d = x - pv;
    ds += d * d;
    pv = x;
    if (x.abs() > pk) pk = x.abs();
  }
  final n = max(1, a.length);
  final rms = max(sqrt(s / n), 1e-6);
  // Hiệu chỉnh r cho tần số lấy mẫu thấp (11025 Hz) so với bản web (44.1 kHz).
  final r = sqrt(ds / n) / rms / 2;
  final rdb = toDb(rms), crest = toDb(max(pk, 1e-6) / rms);
  final inp = clampD((-18 - rdb) * .6, -12, 12);
  final lvl = rdb + inp;
  final v = <double>[
    inp,
    clampD((.3 - r) * 20, -4, 4),
    crest > 14 ? 1.0 : -1.5,
    clampD(lvl + 3, -30, 0),
    -0.3,
  ];
  for (var i = 0; i < 5; i++) {
    v[i] = (clampD(v[i], kDefs[i].min, kDefs[i].max) * 10).round() / 10;
  }
  return AutoResult(Params(v), rdb, crest);
}

List<double> makePeaks(Float32List pcm, [int cols = 600]) {
  final sz = max(1, pcm.length ~/ cols);
  final p = List<double>.filled(cols, 0);
  var mx = 1e-6;
  for (var i = 0; i < cols; i++) {
    double m = 0;
    for (var j = i * sz; j < min(pcm.length, (i + 1) * sz); j += max(1, sz >> 6)) {
      m = max(m, pcm[j].abs());
    }
    p[i] = m;
    mx = max(mx, m);
  }
  return p.map((e) => e / mx).toList();
}

/// Mức RMS (dB) quanh vị trí [sec] cho đồng hồ VU.
double levelAt(Float32List? pcm, double sec, [int sr = 11025]) {
  if (pcm == null || pcm.isEmpty) return -60;
  final i = (sec * sr).floor();
  final a = max(0, i - 1024), b = min(pcm.length, i + 1024);
  if (b <= a) return -60;
  double s = 0;
  for (var k = a; k < b; k++) {
    s += pcm[k] * pcm[k];
  }
  return max(-60, toDb(sqrt(s / (b - a)) + 1e-6));
}

String _f(double x) => x.toStringAsFixed(5);

/// Chuỗi filter FFmpeg tương đương chuỗi xử lý của bản web.
String buildFilter(Params p, int sampleRate) {
  final thr = clampD(pow(10, p.comp / 20).toDouble(), 0.00098, 1.0);
  final makeup = clampD(pow(10, (-p.comp / 3) / 20).toDouble(), 1.0, 64.0);
  final hf = min(12000.0, sampleRate * 0.4);
  return [
    'aformat=sample_fmts=fltp',
    'volume=${_f(p.inp)}dB',
    'highshelf=f=${hf.round()}:g=${_f(p.hi)}',
    'equalizer=f=1000:t=q:w=0.8:g=${_f(p.mid)}',
    'acompressor=threshold=${_f(thr)}:ratio=3:attack=10:release=250:knee=2:makeup=${_f(makeup)}',
    'volume=${_f(p.out)}dB',
    'alimiter=limit=0.891:attack=3:release=100:level=disabled',
  ].join(',');
}

/// Tạo file WAV demo (mono, 16-bit, 14 giây).
Future<void> writeDemoWav(String path) async {
  const sr = 44100;
  const n = sr * 14;
  final b = ByteData(44 + n * 2);
  void ws(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  ws(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  ws(8, 'WAVEfmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, sr, Endian.little);
  b.setUint32(28, sr * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  ws(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  final rnd = Random(1);
  const beat = 0.6;
  for (var i = 0; i < n; i++) {
    final t = i / sr, bt = t % beat, hh = t % (beat / 2);
    final kick = sin(2 * pi * (50 + 90 * exp(-bt * 30)) * bt) * exp(-bt * 7) * .9;
    final hat = hh < .05 ? (rnd.nextDouble() * 2 - 1) * exp(-hh * 90) * .25 : 0.0;
    final bass = sin(2 * pi * 55 * ((t / beat / 2).floor() % 2 == 1 ? 1.335 : 1) * t) * .25;
    final pad = (sin(2 * pi * 220 * t) + sin(2 * pi * 277.2 * t) + sin(2 * pi * 329.6 * t)) * .07;
    final s = (kick + hat + bass + pad) * .5;
    b.setInt16(44 + i * 2, (s * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  await File(path).writeAsBytes(b.buffer.asUint8List());
}
