import 'package:flutter/material.dart';

/// Small, scalable version of the selected Pennant brand mark.
class GhinBrandMark extends StatelessWidget {
  final double size;

  const GhinBrandMark({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _PennantPainter()),
    ),
  );
}

class _PennantPainter extends CustomPainter {
  const _PennantPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas
      ..save()
      ..scale(size.width / 100, size.height / 100);

    void fill(List<Offset> points, Color color) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    fill(const [
      Offset(17, 30),
      Offset(82, 30),
      Offset(61, 50),
      Offset(17, 50),
    ], const Color(0xFFDCEBE0));
    fill(const [
      Offset(24, 47),
      Offset(88, 47),
      Offset(66, 68),
      Offset(24, 68),
    ], const Color(0xFF7BB88A));
    fill(const [
      Offset(38, 64),
      Offset(70, 64),
      Offset(51, 84),
      Offset(38, 84),
    ], const Color(0xFF2F8A5B));

    final polePaint = Paint()
      ..color = const Color(0xFF173F32)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(52, 70), const Offset(52, 11), polePaint);
    fill(const [
      Offset(55, 13),
      Offset(85, 13),
      Offset(73, 25),
      Offset(55, 25),
    ], const Color(0xFFD83A2E));

    final ballPaint = Paint()
      ..color = const Color(0xFFFFFDF5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(32, 71), 14.5, ballPaint);
    canvas.drawCircle(
      const Offset(32, 71),
      14.5,
      Paint()
        ..color = const Color(0xFFD0DBD3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final dimplePaint = Paint()..color = const Color(0xFFB8C7BC);
    for (final point in const [
      Offset(27.5, 67),
      Offset(35, 66),
      Offset(31, 73),
      Offset(36.8, 75),
    ]) {
      canvas.drawCircle(point, 1.8, dimplePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PennantPainter oldDelegate) => false;
}
