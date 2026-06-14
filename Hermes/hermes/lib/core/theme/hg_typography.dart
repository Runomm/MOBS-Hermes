import 'package:flutter/material.dart';

/// Liquid-glass tipografisi (hand-off "Typography").
///
/// İki aile: **Manrope** (tüm UI/sans) + **Cormorant Garamond** (Mercury serif
/// başlıklar, marka, büyük istatistik sayıları). İkisi de *variable font*
/// asset'i — ağırlık `fontVariations` ile seçilir (`fontWeight` tek başına
/// variable TTF'te statik instance seçmez); `fontWeight` da set edilir ki
/// fallback/semantik doğru kalsın.
///
/// Konvansiyon (hand-off): bir kaynak/çeviri çiftinde **çeviri her zaman en
/// büyük ve kalın satırdır**; orijinal üstte küçük ve soluk durur.
class HgType {
  HgType._();

  static const sansFamily = 'Manrope';
  static const serifFamily = 'CormorantGaramond';

  /// Manrope — gövde, etiket, sans başlık.
  static TextStyle sans(
    double size, {
    double weight = 500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: sansFamily,
      fontSize: size,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontWeight: _nearest(weight),
      fontVariations: [FontVariation('wght', weight)],
    );
  }

  /// Cormorant Garamond — serif başlık/marka; [italic] taglineler için.
  static TextStyle serif(
    double size, {
    double weight = 600,
    Color? color,
    double? letterSpacing,
    double? height,
    bool italic = false,
  }) {
    return TextStyle(
      fontFamily: serifFamily,
      fontSize: size,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: _nearest(weight),
      fontVariations: [FontVariation('wght', weight)],
    );
  }

  /// Eyebrow — 11px/600, letter-spacing 3, uppercase (caller upcase eder).
  static TextStyle eyebrow(Color color) =>
      sans(11, weight: 600, color: color, letterSpacing: 3);

  static FontWeight _nearest(double w) {
    final idx = ((w / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[idx];
  }
}
