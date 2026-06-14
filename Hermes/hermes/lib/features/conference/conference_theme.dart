import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Konferans Modu'nun paleti — artık uygulama geneli [HermesColors]'a delege eder
/// (Faz 4, 2026-06-09: açık tasarım dili tüm uygulamaya yayıldı). Eski Konferans
/// dosyaları `ConferenceColors.x` çağrılarını kırmadan yeni tek-kaynağı kullanır.
class ConferenceColors {
  ConferenceColors._();

  static const bg = HermesColors.bg;
  static const surface = HermesColors.surface;
  static const border = HermesColors.border;
  static const accent = HermesColors.accent;
  static const accentSoft = HermesColors.accentSoft;
  static const textPrimary = HermesColors.textPrimary;
  static const textSecondary = HermesColors.textSecondary;
  static const textFaint = HermesColors.textFaint;
  static const crunch = HermesColors.crunch;
  static const success = HermesColors.success;
}

/// Konferans ekranlarını açık temaya saran yardımcı.
///
/// Faz 4'ten sonra uygulama zaten global [hermesLightTheme] kullanıyor; bu
/// sarmal artık no-op'a yakın (geriye uyum için bırakıldı, mevcut Konferans
/// ekranlarını bozmamak için).
class ConferenceTheme extends StatelessWidget {
  const ConferenceTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: hermesLightTheme, child: child);
  }
}
