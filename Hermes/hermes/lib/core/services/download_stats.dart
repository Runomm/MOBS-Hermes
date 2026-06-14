/// İndirme anlık istatistikleri — Ayarlar indirme kartında hız/boyut/%/ETA
/// göstermek için. İlerleme callback'i yalnız 0–1 kesir verdiğinden, toplam
/// boyut ([sizeMb]) ile birleştirip hız ve ETA hesaplar.
///
/// **Hız = kümülatif ortalama** (o ana kadar inen / o ana kadar geçen süre),
/// anlık delta DEĞİL. Anlık hız her HTTP chunk'ında zıpladığından ekranda
/// "titriyordu" (Mehmet 2026-06-09); ortalama hız pürüzsüz ve istikrarlıdır.
/// Saf — test edilebilir.
class DownloadStats {
  const DownloadStats({
    required this.downloadedMb,
    required this.totalMb,
    required this.mbPerSec,
    required this.etaSeconds,
  });

  /// O ana kadar inen MB (≈ fraction × sizeMb). Boyut bilinmiyorsa null.
  final double? downloadedMb;

  /// Toplam boyut (MB). Bilinmiyorsa null.
  final double? totalMb;

  /// Ortalama hız (MB/s). Boyut bilinmiyor / süre çok kısa → null.
  final double? mbPerSec;

  /// Tahmini kalan süre (sn). Hız 0 / boyut yok → null.
  final int? etaSeconds;

  /// İlk istikrarlı okuma için gereken minimum geçen süre — altında hız/ETA
  /// gösterilmez (ilk birkaç yüz ms'de ortalama henüz oturmaz, çılgın değer çıkar).
  static const int _minElapsedMs = 600;

  /// İndirme başından beri [elapsedMs] ms geçti, ilerleme [fraction] (0–1),
  /// toplam boyut [sizeMb]. Boyut null ise tüm sayısal alanlar null (yalnız %).
  factory DownloadStats.from(
    double fraction,
    int elapsedMs,
    int? sizeMb,
  ) {
    if (sizeMb == null || sizeMb <= 0) {
      return const DownloadStats(
          downloadedMb: null, totalMb: null, mbPerSec: null, etaSeconds: null);
    }
    final total = sizeMb.toDouble();
    final frac = fraction.clamp(0.0, 1.0);
    final downloaded = frac * total;
    double? speed;
    int? eta;
    // Kümülatif ortalama: toplam inen / toplam süre → pürüzsüz, titremez.
    if (elapsedMs >= _minElapsedMs && downloaded > 0) {
      speed = downloaded / (elapsedMs / 1000.0); // MB/s
      if (speed > 0) {
        final remainingMb = (1.0 - frac) * total;
        eta = (remainingMb / speed).round();
      }
    }
    return DownloadStats(
      downloadedMb: downloaded,
      totalMb: total,
      mbPerSec: speed,
      etaSeconds: eta,
    );
  }

  /// ETA'yı okunur etikete çevirir: <60sn → "45sn", aksi → "2dk 5sn".
  /// ETA null → null.
  String? get etaLabel {
    final s = etaSeconds;
    if (s == null) return null;
    if (s < 60) return '${s}sn';
    final m = s ~/ 60;
    final ss = s % 60;
    return ss == 0 ? '${m}dk' : '${m}dk ${ss}sn';
  }
}
