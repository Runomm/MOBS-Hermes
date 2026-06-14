/// Konferans arşivi/detayı için küçük tarih biçimleyiciler. `intl` bağımlılığı
/// eklemeden, Mehmet'in istediği `GG-AA-YYYY` formatı (örn. "21-12-2020").
class ConferenceFormat {
  ConferenceFormat._();

  static String _p(int n) => n.toString().padLeft(2, '0');

  /// `GG-AA-YYYY` — yerel saate çevrilir.
  static String date(DateTime dt) {
    final t = dt.toLocal();
    return '${_p(t.day)}-${_p(t.month)}-${t.year}';
  }

  /// `GG-AA-YYYY HH:MM` — detay alt başlığı için.
  static String dateTime(DateTime dt) {
    final t = dt.toLocal();
    return '${date(dt)} ${_p(t.hour)}:${_p(t.minute)}';
  }
}
