import 'package:flutter/foundation.dart';

import '../models/managed_model.dart';
import 'cancel_token.dart';
import 'download_stats.dart';

export 'cancel_token.dart';

/// Tek bir aktif indirmenin durumu (ilerleme + istatistik + iptal jetonu).
class DownloadTask {
  DownloadTask(this.model, this.cancelToken)
      : progress = model.supportsProgress ? 0 : -1;

  final ManagedModel model;
  final CancelToken cancelToken;

  /// 0.0–1.0; -1 = belirsiz (ilerleme desteklenmiyor).
  double progress;
  DownloadStats? stats;
}

/// **Ekran-üstü indirme yöneticisi (singleton).** İndirmeler artık Ayarlar
/// ekranının State'ine bağlı DEĞİL → kullanıcı Ayarlar'dan çıksa da arka planda
/// sürer; geri dönünce ilerleme aynen görünür (Mehmet 2026-06-14). Ayrıca her
/// indirme **iptal** edilebilir ([cancel]).
///
/// Durum [model.id] (kararlı string) ile anahtarlanır — Ayarlar her açılışta
/// yeni [ManagedModel] örnekleri üretir; örnek kimliğine güvenilemez.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final Map<String, DownloadTask> _active = {};

  /// Şu an indirilen tüm görevler.
  Iterable<DownloadTask> get active => _active.values;

  /// Aktif indirme kimlikleri (Ayarlar tamamlanma geçişini yakalamak için).
  Set<String> get activeIds => _active.keys.toSet();

  bool isDownloading(String id) => _active.containsKey(id);
  DownloadTask? taskFor(String id) => _active[id];

  /// [m]'i indir (zaten iniyorsa yok say). Hata olursa [onError] ile bildirilir
  /// (UI snackbar); iptal sessizce yutulur. Future beklenmez — arka planda sürer.
  Future<void> start(
    ManagedModel m, {
    void Function(Object error)? onError,
  }) async {
    if (_active.containsKey(m.id)) return;
    final task = DownloadTask(m, CancelToken());
    _active[m.id] = task;
    notifyListeners();

    final sw = Stopwatch()..start();
    try {
      await m.download(
        cancelToken: task.cancelToken,
        onProgress: m.supportsProgress
            ? (p) {
                task.progress = p;
                final size = m.sizeMb;
                if (size != null) {
                  task.stats =
                      DownloadStats.from(p, sw.elapsedMilliseconds, size);
                }
                notifyListeners();
              }
            : null,
      );
      _active.remove(m.id);
      notifyListeners();
    } on DownloadCancelledException {
      _active.remove(m.id);
      notifyListeners();
    } catch (e) {
      _active.remove(m.id);
      notifyListeners();
      onError?.call(e);
    }
  }

  /// [m]'in indirmesini iptal et. Akış döngüsü bir sonraki parçada durur,
  /// `.part` temizlenir; görev [start]'taki yakalayıcıda listeden düşer.
  void cancel(String id) => _active[id]?.cancelToken.cancel();
}
