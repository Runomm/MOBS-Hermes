import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/download_stats.dart';

void main() {
  group('DownloadStats.from (kümülatif ortalama)', () {
    test('%50 inmiş, 1000ms geçmiş, 1334MB → ~667MB, ~667 MB/s, ETA ~1s', () {
      final s = DownloadStats.from(0.5, 1000, 1334);
      expect(s.downloadedMb, closeTo(667, 1));
      expect(s.totalMb, 1334);
      expect(s.mbPerSec, closeTo(667, 1)); // 667MB / 1s
      expect(s.etaSeconds, 1); // kalan 667MB / 667MB/s ≈ 1s
    });

    test('boyut null → tüm sayısal alanlar null', () {
      final s = DownloadStats.from(0.5, 1000, null);
      expect(s.downloadedMb, isNull);
      expect(s.totalMb, isNull);
      expect(s.mbPerSec, isNull);
      expect(s.etaSeconds, isNull);
    });

    test('süre min eşiğin altında → hız/ETA null ama inen/toplam dolu', () {
      final s = DownloadStats.from(0.5, 100, 1000); // 100ms < 600ms eşiği
      expect(s.downloadedMb, 500);
      expect(s.totalMb, 1000);
      expect(s.mbPerSec, isNull);
      expect(s.etaSeconds, isNull);
    });

    test('%100 tamamlanınca ETA 0', () {
      final s = DownloadStats.from(1.0, 1000, 1000);
      expect(s.downloadedMb, 1000);
      expect(s.etaSeconds, 0); // kalan 0
    });

    test('ortalama hız: %25 inmiş 2000ms, 400MB → 50MB/s, ETA 6s', () {
      final s = DownloadStats.from(0.25, 2000, 400);
      expect(s.downloadedMb, 100); // 0.25*400
      expect(s.mbPerSec, closeTo(50, 0.1)); // 100MB / 2s
      expect(s.etaSeconds, 6); // kalan 300MB / 50MB/s = 6s
    });
  });

  group('etaLabel formatı', () {
    test('<60sn → "Nsn"', () {
      // %90 inmiş 9000ms, 100MB → 90MB/10MB/s, kalan 10MB → 1s
      final s = DownloadStats.from(0.9, 9000, 100);
      expect(s.etaLabel, '1sn');
    });

    test('>=60sn → "Mdk Ssn"', () {
      // 466MB, %5 inmiş 5000ms → 23.3MB/4.66MB/s; kalan ~442.7MB/4.66 ≈ 95s
      final s = DownloadStats.from(0.05, 5000, 466);
      expect(s.etaSeconds, 95);
      expect(s.etaLabel, '1dk 35sn');
    });

    test('tam dakika → "Mdk"', () {
      // ETA tam 120s olacak şekilde: %50 inmiş, kalan 50% aynı sürede → eta=elapsed(sn)
      // 100MB, %50 inmiş 60000ms → 50MB/0.833MB/s, kalan 50MB → 60s
      final s = DownloadStats.from(0.5, 60000, 100);
      expect(s.etaSeconds, 60);
      expect(s.etaLabel, '1dk');
    });

    test('boyut null → etaLabel null', () {
      final s = DownloadStats.from(0.5, 1000, null);
      expect(s.etaLabel, isNull);
    });
  });
}
