import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'dsp.dart';

class MediaMeta {
  final int rate;
  final double duration;
  MediaMeta(this.rate, this.duration);
}

/// Toàn bộ xử lý âm thanh chạy offline bằng FFmpeg.
class Engine {
  static const sr = 11025; // tần số lấy mẫu dùng cho phân tích / đồng hồ / dạng sóng
  late Directory tmp;

  Future<void> init() async => tmp = await getTemporaryDirectory();

  Future<MediaMeta> probe(String path) async {
    var rate = 44100;
    var dur = 0.0;
    try {
      final s = await FFprobeKit.getMediaInformation(path);
      final info = s.getMediaInformation();
      dur = double.tryParse(info?.getDuration() ?? '') ?? 0;
      for (final st in info?.getStreams() ?? []) {
        if (st.getType() == 'audio') {
          rate = int.tryParse(st.getSampleRate() ?? '') ?? 44100;
          break;
        }
      }
    } catch (_) {}
    return MediaMeta(rate, dur);
  }

  /// Giải mã về PCM float32 mono 11025 Hz.
  Future<Float32List?> decode(String path, String tag) async {
    final out = '${tmp.path}/pcm_$tag.raw';
    final s = await FFmpegKit.executeWithArguments(
        ['-y', '-i', path, '-vn', '-ac', '1', '-ar', '$sr', '-f', 'f32le', out]);
    if (!ReturnCode.isSuccess(await s.getReturnCode())) return null;
    final bytes = Uint8List.fromList(await File(out).readAsBytes());
    return Float32List.view(bytes.buffer, 0, bytes.lengthInBytes ~/ 4);
  }

  /// Render bản master: WAV PCM 24-bit, giữ nguyên tần số lấy mẫu gốc.
  Future<bool> render(String src, Params p, String out, int rate) async {
    final s = await FFmpegKit.executeWithArguments([
      '-y', '-i', src, '-vn',
      '-af', buildFilter(p, rate),
      '-c:a', 'pcm_s24le',
      out,
    ]);
    return ReturnCode.isSuccess(await s.getReturnCode());
  }
}
