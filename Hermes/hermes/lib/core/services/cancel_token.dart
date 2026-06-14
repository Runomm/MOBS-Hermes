/// İndirme iptal jetonu — akış-bazlı indirmelerin chunk döngüsüne geçilir.
/// İndirici her parçadan önce [throwIfCancelled]'i çağırır; iptal edilmişse
/// [DownloadCancelledException] fırlatır → `.part` dosyası temizlenip indirme durur.
///
/// Ayrı dosyada (managed_model ↔ download_manager döngüsel import'unu önler).
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const DownloadCancelledException();
  }
}

/// Kullanıcı indirmeyi iptal ettiğinde fırlatılır. Hata değil — UI bunu sessizce
/// (snackbar'sız) yutar; `.part` temizlenir.
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();
  @override
  String toString() => 'İndirme iptal edildi.';
}
