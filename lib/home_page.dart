import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dsp.dart';
import 'engine.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  final Engine eng;
  const HomePage(this.eng, {super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Engine get eng => widget.eng;
  final player = AudioPlayer();
  Params cur = Params.defaults();
  bool auto = true, bypass = false, busy = false, playing = false;
  String preset = 'Default', name = 'Chưa chọn file';
  String status = 'Mở file hoặc dùng Demo. Auto sẽ tự chỉnh thông số.';
  String? src, master, loaded;
  int rate = 44100;
  double dur = 0;
  Float32List? pcmIn, pcmMaster;
  List<double> peaks = [];
  final pos = ValueNotifier<double>(0);
  final lvIn = ValueNotifier<double>(-60), lvOut = ValueNotifier<double>(-60);
  Timer? tick;
  StreamSubscription<PlayerState>? sub;

  @override
  void initState() {
    super.initState();
    sub = player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        player.pause();
        player.seek(Duration.zero);
      }
      if (mounted) setState(() => playing = s.playing && s.processingState != ProcessingState.completed);
    });
    tick = Timer.periodic(const Duration(milliseconds: 40), _onTick);
  }

  @override
  void dispose() {
    tick?.cancel();
    sub?.cancel();
    player.dispose();
    super.dispose();
  }

  void _onTick(Timer _) {
    final p = player.position.inMilliseconds / 1000.0;
    pos.value = p;
    double ti = -60, to = -60;
    if (player.playing) {
      ti = levelAt(pcmIn, p);
      to = levelAt(master != null && loaded == master ? pcmMaster : pcmIn, p);
    }
    lvIn.value += (ti - lvIn.value) * .25;
    lvOut.value += (to - lvOut.value) * .25;
  }

  void say(String t) => setState(() => status = t);

  // ---------- tải file ----------
  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio);
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    await _load(f.path!, f.name);
  }

  Future<void> _demo() async {
    final p = '${eng.tmp.path}/demo_track_100bpm.wav';
    await writeDemoWav(p);
    await _load(p, 'demo_track_100bpm.wav');
  }

  Future<void> _load(String path, String n) async {
    setState(() {
      busy = true;
      status = 'Đang đọc file…';
    });
    try {
      await player.stop();
      final meta = await eng.probe(path);
      final pcm = await eng.decode(path, 'in');
      if (pcm == null) throw 'decode';
      pcmIn = pcm;
      src = path;
      name = n;
      rate = meta.rate;
      dur = meta.duration > 0 ? meta.duration : pcm.length / Engine.sr;
      peaks = makePeaks(pcm);
      master = null;
      pcmMaster = null;
      bypass = false;
      await player.setFilePath(path);
      loaded = path;
      pos.value = 0;
      if (auto) {
        _runAuto();
      } else {
        status = 'Đã tải. Chỉnh tay hoặc bật Tự động.';
      }
    } catch (e) {
      status = 'Không đọc được file này. Thử MP3, WAV hoặc M4A.';
    }
    if (mounted) setState(() => busy = false);
  }

  void _runAuto() {
    final r = autoMaster(pcmIn!);
    cur = r.params;
    preset = '';
    status = 'Auto: mức trung bình ${r.rmsDb.toStringAsFixed(1)} dB, độ động ${r.crestDb.toStringAsFixed(0)} dB → đã đặt thông số. Bấm Render để nghe.';
  }

  // ---------- phát / so sánh ----------
  Future<void> _swap(String path) async {
    final was = player.playing;
    final p = player.position;
    await player.setFilePath(path);
    await player.seek(p);
    loaded = path;
    if (was) player.play();
  }

  Future<void> _invalidate() async {
    if (master == null) return;
    final wasMaster = loaded == master;
    master = null;
    pcmMaster = null;
    if (wasMaster && src != null) await _swap(src!);
    if (mounted) say('Thông số đã đổi. Bấm "Render & nghe thử" để tạo lại bản master.');
  }

  void _setParam(int i, double v) {
    _invalidate();
    setState(() {
      cur.v[i] = v;
      auto = false;
      preset = '';
    });
  }

  void _togglePlay() {
    if (src == null) return;
    player.playing ? player.pause() : player.play();
  }

  Future<void> _toggleAB() async {
    if (master == null) {
      say('Chưa có bản master. Bấm "Render & nghe thử" trước.');
      return;
    }
    bypass = !bypass;
    await _swap(bypass ? src! : master!);
    say(bypass ? 'Đang nghe bản gốc.' : 'Đang nghe bản master đã render.');
  }

  void _toggleAuto() {
    setState(() => auto = !auto);
    if (auto && pcmIn != null) {
      _invalidate();
      setState(_runAuto);
    } else if (!auto) {
      say('Chế độ thủ công: kéo núm để chỉnh, chạm đúp để về mặc định.');
    }
  }

  // ---------- render & xuất ----------
  Future<void> _render() async {
    if (src == null || busy) return;
    setState(() {
      busy = true;
      status = 'Đang render bản master bằng FFmpeg…';
    });
    try {
      final out = '${eng.tmp.path}/master_${DateTime.now().millisecondsSinceEpoch}.wav';
      if (!await eng.render(src!, cur, out, rate)) throw 'ffmpeg';
      final pcm = await eng.decode(out, 'out');
      final old = master;
      master = out;
      pcmMaster = pcm;
      bypass = false;
      await _swap(out);
      if (!player.playing) player.play();
      if (old != null) File(old).delete().ignore();
      status = 'Đang phát đúng bản sẽ xuất. Bấm "Bản gốc" để so sánh, hài lòng thì Lưu WAV 24-bit.';
    } catch (e) {
      status = 'Render thất bại. Kiểm tra file nguồn rồi thử lại.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _export() async {
    if (master == null) return;
    setState(() {
      busy = true;
      status = 'Đang chuẩn bị file…';
    });
    try {
      final bytes = await File(master!).readAsBytes();
      final base = '${name.replaceAll(RegExp(r'\.[^.]+$'), '')}_master_24bit';
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Lưu file master',
          fileName: '$base.wav',
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['wav']);
      status = path == null ? 'Đã huỷ lưu file.' : 'Đã lưu $base.wav (WAV 24-bit).';
    } catch (e) {
      status = 'Không lưu được file: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  // ---------- giao diện ----------
  @override
  Widget build(BuildContext context) {
    final hasSrc = src != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: WoodDevice(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _header(),
                  const SizedBox(height: 8),
                  _fileRow(),
                  const SizedBox(height: 8),
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < 5; i++)
                          Expanded(child: KnobCell(kDefs[i], cur.v[i], kDefault[i], (v) => _setParam(i, v)))
                      ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _vu(lvIn, C.cyan, const Color(0xFF0B2A30), 'IN')),
                    const SizedBox(width: 6),
                    Expanded(child: _vu(lvOut, C.amber, const Color(0xFF3A3010), 'OUT')),
                  ]),
                  const SizedBox(height: 6),
                  _wave(),
                  ValueListenableBuilder<double>(
                    valueListenable: pos,
                    builder: (_, p, __) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(fmt(p), style: const TextStyle(fontSize: 11, color: C.muted, fontFamily: 'monospace')),
                      Text(fmt(dur), style: const TextStyle(fontSize: 11, color: C.muted, fontFamily: 'monospace')),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Row(children: [
                      Btn(playing ? '❚❚ Dừng' : '▶ Phát', hasSrc ? _togglePlay : null),
                      const SizedBox(width: 6),
                      Btn('■', hasSrc ? () { player.pause(); player.seek(Duration.zero); } : null),
                      const SizedBox(width: 6),
                      Btn('Bản gốc', hasSrc ? _toggleAB : null, on: bypass && master != null),
                    ]),
                    Row(children: [
                      Text(auto ? 'Tự động' : 'Thủ công', style: const TextStyle(color: C.text)),
                      const SizedBox(width: 8),
                      Switch2(auto, _toggleAuto),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                      height: 34,
                      child: Text(status, style: const TextStyle(fontSize: 12, height: 1.3, color: C.muted))),
                  if (busy) const LinearProgressIndicator(minHeight: 2, color: C.cyan, backgroundColor: C.edge),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Btn('Render & nghe thử', hasSrc && !busy ? _render : null, primary: true),
                    Btn('Lưu WAV 24-bit', master != null && !busy ? _export : null, primary: true),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 6,
        children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('M.A.P',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: C.cyan,
                    shadows: [Shadow(color: Color(0x803FE0F0), blurRadius: 12)])),
            Text('MASTERING AUDIO PRO', style: TextStyle(fontSize: 9, letterSpacing: 1.4, color: C.muted)),
          ]),
          Wrap(spacing: 4, children: [
            for (final n in kPresets.keys)
              Btn(n, () {
                _invalidate();
                setState(() {
                  cur = Params(List.of(kPresets[n]!));
                  auto = false;
                  preset = n;
                  status = 'Preset $n';
                });
              }, on: preset == n)
          ]),
        ],
      );

  Widget _fileRow() => Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _pick,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: const Color(0xFF070D10),
                  border: Border.all(color: C.edge),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9FD5DD), fontFamily: 'monospace')),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Btn('Mở file', _pick),
        const SizedBox(width: 6),
        Btn('Demo', _demo),
      ]);

  Widget _vu(ValueNotifier<double> n, Color col, Color bg, String label) => SizedBox(
        height: 58,
        child: ValueListenableBuilder<double>(
          valueListenable: n,
          builder: (_, v, __) => CustomPaint(painter: VuPainter(v, col, bg, label), size: Size.infinite),
        ),
      );

  Widget _wave() => LayoutBuilder(
        builder: (_, box) {
          void seek(double dx) {
            if (src == null || dur <= 0) return;
            final f = (dx / box.maxWidth).clamp(0.0, 1.0);
            player.seek(Duration(milliseconds: (f * dur * 1000).round()));
          }

          return GestureDetector(
            onTapDown: (d) => seek(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                  color: const Color(0xFF070D10),
                  border: Border.all(color: C.edge),
                  borderRadius: BorderRadius.circular(4)),
              child: peaks.isEmpty
                  ? const Center(
                      child: Text('Mở file nhạc hoặc dùng Demo để bắt đầu',
                          style: TextStyle(fontSize: 12, color: C.muted)))
                  : ValueListenableBuilder<double>(
                      valueListenable: pos,
                      builder: (_, p, __) => CustomPaint(
                          painter: WavePainter(peaks, dur > 0 ? (p / dur).clamp(0.0, 1.0) : 0), size: Size.infinite),
                    ),
            ),
          );
        },
      );
}
