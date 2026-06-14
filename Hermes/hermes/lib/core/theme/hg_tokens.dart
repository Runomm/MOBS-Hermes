import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Liquid-glass tasarım dili token'ları (hand-off: Hermes-UI-claudeDesign,
/// 2026-06-12). Kaynak: `prototype/hermes-glass.jsx` — değerler birebir.
///
/// Açık mod = **Coral** paleti (Mehmet seçimi); karanlık mod = **Hermes Noir**
/// (obsidyen + altın, palet seçiminden bağımsız tek şık şema).
///
/// Eski `HermesColors` (app_theme.dart) eski ekranlar restyle edilene kadar
/// yaşar; yeni ekranlar yalnız bu token'ları kullanır.
class HgPalette {
  const HgPalette({
    required this.noir,
    required this.accent,
    required this.second,
    required this.conference,
    required this.smalltalk,
    required this.manual,
    required this.visual,
    required this.text,
    required this.sub,
    required this.faint,
    required this.hairline,
  });

  /// Karanlık (Noir) şema mı?
  final bool noir;

  /// Birincil marka aksanı.
  final Color accent;

  /// İkincil aksan (gradient'lerin diğer ucu).
  final Color second;

  // Mod aksanları — ikon, tint, CTA. `smalltalk` aynı zamanda global
  // "canlı/hazır/başarı" durumu rengidir (hand-off konvansiyonu).
  final Color conference;
  final Color smalltalk;
  final Color manual;
  final Color visual;

  // Metin mürekkepleri.
  final Color text;
  final Color sub;
  final Color faint;

  /// İnce satır ayracı (Mercury panel bölücüleri).
  final Color hairline;

  /// Mod anahtarından aksan rengi.
  Color mode(HgMode m) => switch (m) {
    HgMode.conference => conference,
    HgMode.smalltalk => smalltalk,
    HgMode.manual => manual,
    HgMode.visual => visual,
  };

  /// "Canlı / hazır / başarı" durum rengi.
  Color get live => smalltalk;

  /// Coral — sıcak terracotta × deniz (açık mod varsayılanı).
  static const coral = HgPalette(
    noir: false,
    accent: Color(0xFFE2674A),
    second: Color(0xFF1FA98F),
    conference: Color(0xFFE2674A),
    smalltalk: Color(0xFF1FA98F),
    manual: Color(0xFFE0A52E),
    visual: Color(0xFFC2566E),
    text: Color(0xFF16142A),
    sub: Color.fromRGBO(40, 38, 66, 0.62),
    faint: Color.fromRGBO(40, 38, 66, 0.40),
    hairline: Color.fromRGBO(40, 38, 66, 0.10),
  );

  /// Hermes Noir — obsidyen + altın; dar/sıcak aralık, tek metal hissi.
  static const noirGold = HgPalette(
    noir: true,
    accent: Color(0xFFCBA75A),
    second: Color(0xFF9AA2B4),
    conference: Color(0xFFD8BD7E),
    smalltalk: Color(0xFFCBA75A),
    manual: Color(0xFFC0934F),
    visual: Color(0xFFCBC4B2),
    text: Color(0xFFF2ECDC),
    sub: Color.fromRGBO(236, 228, 206, 0.60),
    faint: Color.fromRGBO(236, 228, 206, 0.36),
    hairline: Color.fromRGBO(255, 255, 255, 0.10),
  );

  /// Tema parlaklığına göre aktif palet.
  static HgPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? noirGold : coral;
}

/// 4 çeviri modu — `HgPalette.mode` + Home kart verisi anahtarı.
enum HgMode { conference, smalltalk, manual, visual }

/// Geometri/boşluk token'ları (hand-off "Spacing & geometry").
class Hg {
  Hg._();

  /// Ekran yatay padding'i.
  static const double pad = 22;

  /// Liste kart dikey aralığı.
  static const double cardGap = 13;

  /// Cam köşe yarıçapları.
  static const double rCard = 24;
  static const double rHero = 28;
  static const double rTile = 15;
  static const double rPill = 22;

  /// Dokunma hedefi — geri/ayarlar pill'leri.
  static const double hit = 46;
}

/// Uygulama tema modu (Home'daki güneş/ay toggle'ı kontrol eder). Varsayılan
/// açık. Seçim [setHgThemeMode] ile kalıcılaştırılır, açılışta [loadHgThemeMode]
/// ile geri yüklenir.
final ValueNotifier<ThemeMode> hgThemeMode = ValueNotifier(ThemeMode.light);

const String _kHgThemeModeKey = 'hg_theme_mode';

/// Açılışta kayıtlı tema modunu yükle (varsayılan açık). main()'de runApp öncesi.
Future<void> loadHgThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    hgThemeMode.value = prefs.getString(_kHgThemeModeKey) == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
  } catch (_) {
    hgThemeMode.value = ThemeMode.light; // prefs erişilemezse açık
  }
}

/// Tema modunu uygula + kalıcılaştır (toggle bunu çağırır).
Future<void> setHgThemeMode(ThemeMode mode) async {
  hgThemeMode.value = mode;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kHgThemeModeKey,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
  } catch (_) {
    // kalıcılaştırma başarısızsa sessiz geç — UI yine de güncellendi.
  }
}
