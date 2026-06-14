import 'package:flutter/material.dart';

import 'hg_tokens.dart';
import 'hg_typography.dart';

/// Hermes'in uygulama geneli açık/beyaz tasarım dili.
///
/// Köken: Konferans Modu'nun "temiz sade açık beyaz tonların olduğu şık
/// tasarım"ı (Mehmet 2026-06-04). Faz 4'te (2026-06-09) tüm uygulamaya yayıldı —
/// salt renk değil, genel dizayn (kart, boşluk, aksan, başlık dili).
///
/// Tek kaynak: tüm kullanıcı ekranları bu paleti + [hermesLightTheme]'i kullanır.
/// (Eski `ConferenceColors` bu sınıfa delege eder — geriye uyum.)
class HermesColors {
  HermesColors._();

  /// Sayfa arka planı — kırık beyaz, göz yormayan.
  static const bg = Color(0xFFF7F7FB);

  /// Kart / yüzey — saf beyaz.
  static const surface = Color(0xFFFFFFFF);

  /// İnce kenarlık / ayraç.
  static const border = Color(0xFFE6E6EF);

  /// Marka aksanı (Hermes moru, açık zeminde de okunur).
  static const accent = Color(0xFF6C5CE7);
  static const accentSoft = Color(0xFFEDEAFB);

  /// Birincil metin — koyu lacivert-gri.
  static const textPrimary = Color(0xFF1B1B2A);

  /// İkincil metin.
  static const textSecondary = Color(0xFF6B6B7B);

  /// Soluk / placeholder.
  static const textFaint = Color(0xFF9A9AAB);

  /// Crunch aksanı (mor) ve "hazır" yeşili.
  static const crunch = Color(0xFF8E44E8);
  static const success = Color(0xFF2E9E6B);

  /// Hata / uyarı (kırmızı tonu, açık zeminde okunur).
  static const danger = Color(0xFFD64545);
}

/// Uygulama geneli açık tema. `MaterialApp.theme` buna ayarlanır; ekranlar
/// per-widget renk vermeden açık/temiz görünür.
ThemeData get hermesLightTheme {
  final scheme = ColorScheme.fromSeed(
    seedColor: HermesColors.accent,
    brightness: Brightness.light,
    surface: HermesColors.surface,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: HermesColors.bg,
    colorScheme: scheme,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: HermesColors.surface,
      foregroundColor: HermesColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: HermesColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HermesColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: HermesColors.border),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HermesColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HermesColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HermesColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HermesColors.accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: HermesColors.textSecondary),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: HermesColors.textPrimary,
      displayColor: HermesColors.textPrimary,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Karanlık tema — **Hermes Noir** (liquid-glass hand-off: obsidyen + altın).
/// Yeni HG ekranları renklerini [HgPalette.noirGold]'dan alır; bu ThemeData
/// brightness + scaffold zemini + temel scheme'i sağlar. Eski (henüz restyle
/// edilmemiş) ekranlar Noir'da kusurlu görünebilir — geçiş dönemi kabulü,
/// toggle varsayılanı açık mod.
ThemeData get hermesNoirTheme {
  const noir = HgPalette.noirGold;
  final scheme = ColorScheme.fromSeed(
    seedColor: noir.accent,
    brightness: Brightness.dark,
    surface: const Color(0xFF14121A),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF100E14),
    colorScheme: scheme,
    fontFamily: HgType.sansFamily,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF14121A),
      foregroundColor: Color(0xFFF2ECDC),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: noir.text,
      displayColor: noir.text,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
