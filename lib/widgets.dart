import 'dart:math';
import 'package:flutter/material.dart';
import 'dsp.dart';

class C {
  static const bg = Color(0xFF0A1114);
  static const panel = Color(0xFF0E1A1F);
  static const edge = Color(0xFF1C2E35);
  static const cyan = Color(0xFF3FE0F0);
  static const amber = Color(0xFFF0C53A);
  static const text = Color(0xFFD6E6EA);
  static const muted = Color(0xFF7F979E);
}

/// Khung gỗ + thân thiết bị.
class WoodDevice extends StatelessWidget {
  final Widget child;
  const WoodDevice({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7A4D29), Color(0xFF4A2D17)]),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 10))],
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2A3B42), width: 2),
            gradient: const RadialGradient(center: Alignment(0, -1), radius: 1.3, colors: [Color(0xFF14262D), C.panel]),
          ),
          child: child,
        ),
      );
}

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool on, primary;
  const Btn(this.label, this.onTap, {super.key, this.on = false, this.primary = false});
  @override
  Widget build(BuildContext context) {
    final hot = on || primary;
    return Material(
      color: primary ? const Color(0xFF134A53) : const Color(0xFF16262C),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5), side: BorderSide(color: hot ? C.cyan : C.edge)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              widthFactor: 1,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14, color: onTap == null ? C.muted : (on ? C.cyan : C.text))),
            ),
          ),
        ),
      ),
    );
  }
}

class Switch2 extends StatelessWidget {
  final bool value;
  final VoidCallback onTap;
  const Switch2(this.value, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        label: 'Chế độ tự động',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            height: 26,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
                color: const Color(0xFF0A1417),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: value ? C.cyan : C.edge)),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? C.cyan : const Color(0xFF8B9AA0),
                  boxShadow: value ? const [BoxShadow(color: C.cyan, blurRadius: 8)] : null),
            ),
          ),
        ),
      );
}

/// Núm xoay: kéo dọc để chỉnh, chạm đúp để về mặc định.
class KnobCell extends StatelessWidget {
  final ParamDef d;
  final double value, def;
  final ValueChanged<double> onChanged;
  const KnobCell(this.d, this.value, this.def, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = (value - d.min) / (d.max - d.min);
    return Semantics(
      label: d.label,
      value: sg(value),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(d.label,
            style: const TextStyle(fontSize: 10, letterSpacing: .4, color: C.muted, fontWeight: FontWeight.w600)),
        GestureDetector(
          onVerticalDragUpdate: (g) {
            final v = clampD(value - g.delta.dy / 150 * (d.max - d.min), d.min, d.max);
            onChanged((v * 10).round() / 10);
          },
          onDoubleTap: () => onChanged(def),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(width: 56, height: 56, child: CustomPaint(painter: KnobPainter(p))),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
              color: const Color(0xFF070D10),
              border: Border.all(color: C.edge),
              borderRadius: BorderRadius.circular(3)),
          child: Text(sg(value),
              style: const TextStyle(fontSize: 10.5, color: C.cyan, fontFamily: 'monospace')),
        ),
        const SizedBox(height: 2),
        Text(d.sub, style: const TextStyle(fontSize: 9.5, color: C.muted)),
      ]),
    );
  }
}

class KnobPainter extends CustomPainter {
  final double p;
  KnobPainter(this.p);
  @override
  void paint(Canvas c, Size s) {
    final ctr = s.center(Offset.zero);
    final r = s.shortestSide / 2;
    final ring = Rect.fromCircle(center: ctr, radius: r - 3);
    const start = -5 * pi / 4, total = 3 * pi / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1B2A30);
    c.drawArc(ring, start, total, false, track);
    if (p > 0.001) {
      c.drawArc(
          ring,
          start,
          total * p,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..color = C.cyan.withAlpha(140)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      c.drawArc(ring, start, total * p, false, track..color = C.cyan);
    }
    final cr = r * .72, a = start + total * p;
    c.drawCircle(ctr + const Offset(0, 3), cr,
        Paint()..color = Colors.black54..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    final shader = SweepGradient(
      colors: const [Color(0xFFE6EEF0), Color(0xFF7D8B90), Color(0xFFDFE8EA), Color(0xFF6F7C81), Color(0xFFE6EEF0)],
      transform: GradientRotation(a),
    ).createShader(Rect.fromCircle(center: ctr, radius: cr));
    c.drawCircle(ctr, cr, Paint()..shader = shader);
    c.drawCircle(ctr, cr, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.black38);
    final dir = Offset(cos(a), sin(a));
    c.drawLine(ctr + dir * (cr * .45), ctr + dir * (cr * .88),
        Paint()..strokeWidth = 3..strokeCap = StrokeCap.round..color = const Color(0xFF102127));
  }

  @override
  bool shouldRepaint(KnobPainter o) => o.p != p;
}

void _text(Canvas c, String s, Offset o, {double size = 11, Color color = Colors.black, FontWeight w = FontWeight.w500}) {
  final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: w)),
      textDirection: TextDirection.ltr)
    ..layout();
  tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
}

/// Đồng hồ VU kim.
class VuPainter extends CustomPainter {
  final double db;
  final Color col, bg;
  final String label;
  VuPainter(this.db, this.col, this.bg, this.label);
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height, box = Offset.zero & s;
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)));
    c.drawRect(
        box,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [col, bg])
              .createShader(box));
    final cx = w / 2, cy = h * 1.15, R = h * .95;
    double ang(double t) => (-52 + 104 * t) * pi / 180 - pi / 2;
    const ticks = [(-30.0, '−30'), (-20.0, '20'), (-10.0, '10'), (-5.0, '5'), (0.0, '0'), (3.0, '+3')];
    for (final (d, t) in ticks) {
      final a = ang((d + 30) / 33), red = d >= 0;
      final col = red ? const Color(0xFFBB0000) : Colors.black;
      c.drawLine(Offset(cx + cos(a) * R, cy + sin(a) * R), Offset(cx + cos(a) * (R - 8), cy + sin(a) * (R - 8)),
          Paint()..color = col..strokeWidth = 1.5);
      _text(c, t, Offset(cx + cos(a) * (R - 18), cy + sin(a) * (R - 18)), size: 10, color: col);
    }
    _text(c, '$label · VU', Offset(cx, h - 8), size: 11, w: FontWeight.w700);
    final a = ang(clampD((db + 30) / 33, 0, 1));
    c.drawLine(Offset(cx, cy), Offset(cx + cos(a) * (R - 4), cy + sin(a) * (R - 4)),
        Paint()..color = const Color(0xFF111111)..strokeWidth = 2);
    c.restore();
  }

  @override
  bool shouldRepaint(VuPainter o) => o.db != db;
}

class WavePainter extends CustomPainter {
  final List<double> peaks;
  final double prog;
  WavePainter(this.peaks, this.prog);
  @override
  void paint(Canvas c, Size s) {
    if (peaks.isEmpty) return;
    final w = s.width, h = s.height, n = peaks.length;
    final on = Paint()..color = C.cyan, off = Paint()..color = const Color(0xFF2A6670);
    for (var x = 0.0; x < w; x++) {
      final v = peaks[(x / w * n).floor().clamp(0, n - 1)] * h * .46;
      c.drawRect(Rect.fromLTWH(x, h / 2 - v, 1, max(1.0, v * 2)), x / w < prog ? on : off);
    }
    c.drawRect(Rect.fromLTWH(prog * w, 0, 1.5, h), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(WavePainter o) => o.prog != prog || o.peaks != peaks;
}
