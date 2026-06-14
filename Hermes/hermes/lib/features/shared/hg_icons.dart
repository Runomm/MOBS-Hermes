import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

/// Liquid-glass ikon seti (hand-off `HIcon`) — tek-ağırlık geometrik stroke
/// ikonlar. Path verileri `prototype/hermes-glass.jsx`'ten birebir port
/// (rect/circle elementleri eşdeğer path komutlarına çevrildi). ViewBox 24.
///
/// Material Icons yerine bunlar kullanılır çünkü tasarımın "ince tek çizgi"
/// karakteri Material'ın dolu/kalın setiyle eşleşmiyor. Şimdilik Home'un
/// ikonları portlandı; diğer ekranların ikonları kendi turlarında eklenecek.
class HgIcon extends StatelessWidget {
  const HgIcon(
    this.icon, {
    super.key,
    this.size = 26,
    required this.color,
    this.strokeWidth = 1.8,
  });

  final HgIconData icon;
  final double size;
  final Color color;

  /// 24-birimlik viewBox'ta çizgi kalınlığı (hand-off `sw`).
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HgIconPainter(icon, color, strokeWidth),
    );
  }
}

class _HgIconPainter extends CustomPainter {
  _HgIconPainter(this.icon, this.color, this.sw);

  final HgIconData icon;
  final Color color;
  final double sw;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    for (final shape in icon.shapes) {
      canvas.drawPath(
        parseSvgPathData(shape.data),
        shape.filled ? fill : stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_HgIconPainter old) =>
      old.icon != icon || old.color != color || old.sw != sw;
}

class HgIconShape {
  const HgIconShape(this.data, {this.filled = false});
  final String data;
  final bool filled;
}

class HgIconData {
  const HgIconData(this.shapes);
  final List<HgIconShape> shapes;
}

/// İkon kataloğu — adlar hand-off ile aynı.
class HgIcons {
  HgIcons._();

  static const conference = HgIconData([
    HgIconShape(
      'M5 4h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z',
    ),
    HgIconShape('M12 16v4M8 20h8'),
    HgIconShape('M7 11l2.5-2.5L12 11l3.5-3.5'),
  ]);

  static const smalltalk = HgIconData([
    HgIconShape(
      'M4 5h10a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2H8l-4 3V7a2 2 0 0 1 0 -2z',
    ),
    HgIconShape('M10 17h6l4 3v-8a2 2 0 0 0 -2 -2h-2'),
  ]);

  static const manual = HgIconData([
    HgIconShape('M4 6h8M8 4v2M6 6c0 4-1.5 6-3.5 8M7 9c1.2 2.4 3 4 5 5'),
    HgIconShape('M13 19l3.5-8 3.5 8M14.2 16h4.6'),
  ]);

  static const visual = HgIconData([
    HgIconShape(
      'M5.5 6h13A2.5 2.5 0 0 1 21 8.5v8a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 16.5v-8A2.5 2.5 0 0 1 5.5 6Z',
    ),
    HgIconShape('M8 6l1.5-2h5L16 6'),
    HgIconShape('M12 9.3a3.2 3.2 0 1 1 0 6.4a3.2 3.2 0 1 1 0-6.4Z'),
  ]);

  // Dişli: prototipin sıkıştırılmış arc-flag'li path'i path_drawing'de yamuk
  // parse oluyordu (cihazda doğrulandı, 2026-06-12) → açık parametreli temiz
  // gear (Lucide "settings" geometrisi, aynı tek-çizgi karakter).
  static const settings = HgIconData([
    HgIconShape('M12 9a3 3 0 1 1 0 6a3 3 0 1 1 0-6Z'),
    HgIconShape(
      'M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z',
    ),
  ]);

  static const folder = HgIconData([
    HgIconShape(
      'M3 7a2 2 0 0 1 2 -2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2H5a2 2 0 0 1 -2 -2V7z',
    ),
  ]);

  static const chevron = HgIconData([HgIconShape('M9 6l6 6-6 6')]);

  static const back = HgIconData([HgIconShape('M15 6l-6 6 6 6')]);

  static const download = HgIconData([
    HgIconShape('M12 4v11M7 11l5 5 5-5M5 20h14'),
  ]);

  /// Hermes amblemi — kanatlı asa (sadeleştirilmiş caduceus).
  static const wings = HgIconData([
    HgIconShape('M12 3v18'),
    HgIconShape(
      'M12 6C9 5 5.5 5.5 2.5 8c2.6 1 5 1.2 7.2.3M12 6c3-1 6.5-.5 9.5 2-2.6 1-5 1.2-7.2.3',
    ),
    HgIconShape('M12 2.3a1.1 1.1 0 1 1 0 2.2a1.1 1.1 0 1 1 0-2.2Z'),
  ]);

  static const mic = HgIconData([
    HgIconShape('M12 3a3 3 0 0 1 3 3v5a3 3 0 0 1 -6 0V6a3 3 0 0 1 3 -3Z'),
    HgIconShape('M5 11a7 7 0 0 0 14 0M12 18v3'),
  ]);

  static const sparkle = HgIconData([
    HgIconShape(
      'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z',
    ),
    HgIconShape('M19 15l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7.7-2z'),
  ]);

  static const play = HgIconData([
    HgIconShape('M7 4.5l12 7.5-12 7.5z', filled: true),
  ]);

  static const pause = HgIconData([
    HgIconShape('M7 5h3.5v14H7Z', filled: true),
    HgIconShape('M13.5 5h3.5v14h-3.5Z', filled: true),
  ]);

  static const stop = HgIconData([
    HgIconShape(
      'M9 6.5h6a2.5 2.5 0 0 1 2.5 2.5v6a2.5 2.5 0 0 1 -2.5 2.5H9A2.5 2.5 0 0 1 6.5 15V9A2.5 2.5 0 0 1 9 6.5Z',
      filled: true,
    ),
  ]);

  static const swap = HgIconData([HgIconShape('M7 7h11l-3-3M17 17H6l3 3')]);

  static const speaker = HgIconData([
    HgIconShape('M4 9v6h4l5 4V5L8 9H4z'),
    HgIconShape('M16 9c1.5 1.5 1.5 4.5 0 6M18.5 7c2.5 2.5 2.5 7.5 0 10'),
  ]);

  static const camera = HgIconData([
    HgIconShape(
      'M5.5 6h13A2.5 2.5 0 0 1 21 8.5v8a2.5 2.5 0 0 1 -2.5 2.5h-13A2.5 2.5 0 0 1 3 16.5v-8A2.5 2.5 0 0 1 5.5 6Z',
    ),
    HgIconShape('M12 9.1a3.4 3.4 0 1 1 0 6.8a3.4 3.4 0 1 1 0 -6.8Z'),
    HgIconShape('M8 6l1.5-2h5L16 6'),
  ]);

  static const image = HgIconData([
    HgIconShape(
      'M5.5 5h13A2.5 2.5 0 0 1 21 7.5v9a2.5 2.5 0 0 1 -2.5 2.5h-13A2.5 2.5 0 0 1 3 16.5v-9A2.5 2.5 0 0 1 5.5 5Z',
    ),
    HgIconShape('M8.5 8.4a1.6 1.6 0 1 1 0 3.2a1.6 1.6 0 1 1 0 -3.2Z'),
    HgIconShape('M5 17l4.5-4 3 2.5L16 12l3 3.5'),
  ]);

  static const copy = HgIconData([
    HgIconShape(
      'M10.5 8h6a2.5 2.5 0 0 1 2.5 2.5v6a2.5 2.5 0 0 1 -2.5 2.5h-6A2.5 2.5 0 0 1 8 16.5v-6A2.5 2.5 0 0 1 10.5 8Z',
    ),
    HgIconShape('M5 15V6a2 2 0 0 1 2 -2h8'),
  ]);

  static const check = HgIconData([HgIconShape('M5 12.5l4.5 4.5L19 7')]);

  static const warning = HgIconData([
    HgIconShape('M12 3.5l9.2 16.5H2.8L12 3.5z'),
    HgIconShape('M12 10v4.2'),
    HgIconShape(
      'M12 16.8a0.6 0.6 0 1 1 0 1.2a0.6 0.6 0 1 1 0 -1.2Z',
      filled: true,
    ),
  ]);

  static const refresh = HgIconData([
    HgIconShape('M20 11a8 8 0 1 0 -2 6.3'),
    HgIconShape('M20 4v5h-5'),
  ]);

  static const arrows = HgIconData([
    HgIconShape('M8 4v16M8 20l-3-3M8 20l3-3M16 20V4M16 4l-3 3M16 4l3 3'),
  ]);

  static const headphone = HgIconData([
    HgIconShape('M4 14v-2a8 8 0 0 1 16 0v2'),
    HgIconShape(
      'M5.2 13h0.1a2.2 2.2 0 0 1 2.2 2.2v2.6a2.2 2.2 0 0 1 -2.2 2.2h-0.1A2.2 2.2 0 0 1 3 17.8v-2.6A2.2 2.2 0 0 1 5.2 13Z',
    ),
    HgIconShape(
      'M18.7 13h0.1a2.2 2.2 0 0 1 2.2 2.2v2.6a2.2 2.2 0 0 1 -2.2 2.2h-0.1a2.2 2.2 0 0 1 -2.2 -2.2v-2.6a2.2 2.2 0 0 1 2.2 -2.2Z',
    ),
  ]);

  static const screen = HgIconData([
    HgIconShape(
      'M8.6 3h6.8A2.6 2.6 0 0 1 18 5.6v12.8a2.6 2.6 0 0 1 -2.6 2.6H8.6A2.6 2.6 0 0 1 6 18.4V5.6A2.6 2.6 0 0 1 8.6 3Z',
    ),
    HgIconShape('M9.5 8h5M9.5 12h5M9.5 16h3'),
  ]);

  static const bolt = HgIconData([
    HgIconShape('M13 3L5 13h5.5L10 21l8-10h-5.5L13 3z'),
  ]);

  static const target = HgIconData([
    HgIconShape('M12 3.8a8.2 8.2 0 1 1 0 16.4a8.2 8.2 0 1 1 0 -16.4Z'),
    HgIconShape('M12 8.6a3.4 3.4 0 1 1 0 6.8a3.4 3.4 0 1 1 0 -6.8Z'),
    HgIconShape('M12 1.8v3M12 19.2v3M22.2 12h-3M4.8 12h-3'),
  ]);

  static const layers = HgIconData([
    HgIconShape('M12 3l9 5-9 5-9-5 9-5z'),
    HgIconShape('M3 12l9 5 9-5M3 16.5l9 5 9-5'),
  ]);
}
