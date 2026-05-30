# LAB 5 — Teknoloji Seçimi ve Gerekçelendirme

**Proje Adı:** Hermes — Çevrimdışı Akıllı Çeviri ve Not Asistanı  
**Öğrenci Adı:** Mehmet Onur Boyraz  
**Öğrenci No:** 245541023

---

## 2.1 Mobil Geliştirme Teknolojisi

**Seçim:** Cross-platform (Flutter)

Uygulamanın kullanıcı arayüzü, tek bir kod tabanıyla hem iOS hem de Android platformlarına çıktı verebilen Flutter çerçevesi kullanılarak geliştirilecektir.

---

## 2.2 Veri Kaynağı

**Seçim:** Hibrit — Yerel Depolama (birincil) + Bulut API (ikincil, isteğe bağlı)

- **Yerel Veritabanı (SQLite):** Tüm oturum transkriptleri, çeviri geçmişi ve kullanıcı tercihleri cihazda saklanır. İnternet gerektirmez.
- **Bulut API (Gemini Flash):** Yalnızca özet ve analiz özelliği için, yalnızca internet bağlantısı mevcut olduğunda çağrılır. Temel işlevler bu bağlantıya bağımlı değildir.

---

## 2.3 Ek Araçlar ve Kütüphaneler

| Araç | Görev | Çalışma Ortamı | Lisans |
|------|-------|----------------|--------|
| **whisper.cpp** | Konuşmayı metne dönüştürme (STT) | Yerel CPU/GPU | MIT |
| **Google ML Kit Translation** | Metin çevirisi (100+ dil) | Yerel (offline) | Ücretsiz |
| **Native OS TTS** | Çeviriyi sesli okuma | Yerel (built-in) | — |
| **SQLite / Drift** | Oturum ve transkript depolama | Yerel | MIT |
| **Gemini Flash API** | Özet ve analiz oluşturma | Bulut (online) | Ücretsiz katman |
| **flutter_map** | Harita görünümü (ileride) | Yerel + OSM | MIT |

**Mimari Desen:** Strategy Pattern — STT, çeviri ve TTS motorlarının her biri değiştirilebilir bir arayüz üzerinden kullanılır. Motor değişikliği uygulamanın geri kalanını etkilemez.

---

## 2.4 Gerekçelendirme

**Problemin yapısına göre:**  
Uygulamanın temel değeri internet bağlantısı olmayan ortamlarda (roaming, yurt dışı, zayıf sinyal) çalışabilmesidir. Bu nedenle çeviri ve konuşma tanıma işlemlerinin tamamı cihazda çalışmak zorundadır. Bulut bağımlı bir mimari bu temel gereksinimi karşılayamaz.

**Kullanıcı sayısı beklentisine göre:**  
Uygulama eş zamanlı milyonlarca kullanıcı hedeflememektedir. Her işlem bireysel kullanıcının kendi cihazında gerçekleştiğinden sunucu maliyeti ve ölçekleme sorunu yoktur.

**Geliştirme süresine göre:**  
iOS (Swift) ve Android (Kotlin) için ayrı ayrı geliştirme yapmak akademik takvim içinde sürdürülemez. Flutter ile tek kod tabanı yeterli olup geliştirme süresi optimize edilmiştir.

**Değiştirilebilirlik için:**  
Google ML Kit ve whisper.cpp, Strategy Pattern aracılığıyla soyutlanmıştır. İleride daha iyi bir model mevcut olduğunda (örn. SeamlessM4T) yalnızca ilgili motor sınıfı değiştirilir; uygulamanın geri kalanı hiç değişmez.
