# Hermes — Yol Haritası

**Canlı statü dokümanı.** Her implementasyon adımı sonrası güncellenir. Tasarım kararları için: `HERMES_KONUSMA_MODU_TASARIM.md`. Teknoloji seçimleri için: `HERMES_TEKNIK_REFERANS.md`.

**Son güncelleme:** 2026-05-17 akşam (Step 6 yarıda — 6a/6b/6c/6d kod tarafı bitti 61/61 test ✅, ama 6d sonunda **tasarım kararı çıktı**: Mehmet "donanım ayrımı" mimarisi önerdi — kulaklık+telefon dual stream Headset Mode + push-to-talk Handset Mode. Önce **Headset Mode'un teknik niyeti netleştirilmeli** (Yorum X paralel dual mic mi, Yorum Y tek mic + audio routing mi?). Detay: `new_session_starter_kit/punch_board.md` 2026-05-17 akşam entry'si. Refactor başlamadı.)

---

## Mevcut Durum (Checkpoint)

**Cihaz:** Poco X3 Pro (Android 13, ID: cd61ba57)
**Son cihaz testi:** ✅ Drift + SQLite — oturum/mesaj yazma + sıralama + cold-start kalıcılık doğrulandı (6/6 senaryo)
**Build ortamı:** NDK 29.0.13113456 pinli (`android/app/build.gradle.kts`), `record: ^6.0.0`, `whisper_ggml`, `google_mlkit_translation`, `flutter_lints`, `drift: ^2.21.0` + `sqlite3_flutter_libs: ^0.5.24` + `drift_dev` & `build_runner` (dev)
**`flutter analyze`:** clean (28/28 unit test geçiyor)

---

## Faz 1 — Çekirdek Çeviri & Konuşma Asistanı

### Tamamlanan

- [x] **Proje iskeleti** — Flutter app, Material 3 dark tema, Hermes brand renkleri
- [x] **TranslationEngine interface** — Strategy Pattern abstract sınıf
- [x] **GoogleMLKitEngine** — `google_mlkit_translation` ile offline çeviri, model indirme yönetimi
- [x] **Test ekranı (Translation)** — Dil dropdown'ları, manuel metin girişi, çevir butonu (USB cihaz testi geçti)
- [x] **SttEngine interface** — Strategy Pattern abstract sınıf
- [x] **WhisperCppEngine** — `whisper_ggml`, tiny modeli APK asset, small Hugging Face indirme
- [x] **Mikrofon kayıt + Whisper transkript akışı** — `record` paketi, otomatik transkripsiyon sonrası ML Kit çevirisi (USB cihaz testi geçti)
- [x] **NDK 29 pin + record 6.x upgrade** — `whisper_ggml` NDK 29 gereksinimi karşılandı, record_linux 0.7→1.3 uyumsuzluğu çözüldü
- [x] **Konuşma Modu tasarımı** — VAD + auto-dil + chat akışı + filler temizleme, 6 açık soru kararlaştırıldı
- [x] **Step 1 — TtsEngine + Native flutter_tts** — `flutter_tts: ^4.2.5`, BCP-47 locale eşlemesi, auto-speak toggle, manuel Seslendir/Stop butonu (cihaz testi geçti; 6 senaryo ✅, robotic ses sistem TTS engine'iyle ilgili — Coqui Faz 2'ye işaretli)
- [x] **Step 2 — Dil paketi indirme UI** — TranslationEngine interface'e `isLanguageReady`/`downloadLanguage`/`deleteLanguage`/`estimatedDownloadSizeMb` eklendi, GoogleMLKitEngine bunları implement etti, dropdown indirilmiş (✓ beyaz) / indirilmemiş (⬇ gri + ~30MB) ayrımı, confirm dialog + indirme akışı, bottom overflow (Switch tap target) düzeltildi (cihaz testi geçti)
- [x] **Step 2 fix — Dropdown baseline assertion** — `selectedItemBuilder` ile inline seçili görüntü düz `Text`'e indirgendi; `_LanguageRow` açık menüde kaldı. InputDecorator+RenderIndexedStack baseline döngüsü kırıldı (log'da `ASSERTION_COUNT=0`)
- [x] **Step 3 — VadController (Silero v4)** — `vad: ^0.0.7+1`, `silero_vad_legacy.onnx` (1.8MB) APK asset, MODIFY_AUDIO_SETTINGS izni, VadController interface + sealed VadUtteranceEvent, SileroVadController, standalone VadTestScreen + AppBar entry. Cihaz testi: 5 cümleden 4'ü tespit (kısa/hızlı "iki kahve lütfen" kaçırıldı — bilinen min frame trade-off, Step 9 polish'inde tunable), uzaktaki gerçek konuşma misfire olarak doğru sınıflandı, sessizlikte sayaç artmadı, gürültü filtresi başarılı
- [x] **Step 4 — FillerCleaner (saf Dart)** — `FillerLevel.off/conservative/aggressive`, jenerik dolgu sesleri (mmm, aaa), TR conservative (ee, uhh), TR aggressive (yani, işte, hani, falan, şey), EN conservative (um, uh), EN aggressive (you know, i mean, kinda, sorta, sentence-initial like). 16/16 unit test geçti. Bilgi notu: Dart `caseSensitive: false` Türkçe `İ` ↔ `i` eşlemiyor; TR pattern'lerde açık character class `[İi]şte`. `\b` Unicode-aware olmadığı için `(?<![\p{L}])...(?![\p{L}])` kullanıldı.
- [x] **Step 5 — Drift schema + ConversationRepository** — `lib/core/database/app_database.dart` (sessions + messages tabloları, cascade delete, `PRAGMA foreign_keys=ON` `beforeOpen` migration), `lib/core/repositories/conversation_repository.dart` (`SessionMode.fast/full` enum + 7 metot: create/end Session, appendMessage, getSession, listMessages, listAllSessions (`startedAt` desc + id desc tiebreak), countMessages). 11 unit test (in-memory `NativeDatabase.memory()`). Cihaz doğrulaması için `lib/features/db_test/db_test_screen.dart` eklendi (AppBar `Icons.storage` butonundan). Bağımlılıklar: `drift: ^2.21.0`, `sqlite3_flutter_libs: ^0.5.24`, `path: ^1.9.0` + dev: `drift_dev`, `build_runner`. Cihaz testi 6/6 ✅ — kalıcılık dahil.

### Aktif İş

**Step 6 yarıda — tasarım kararı bekliyor.** Kod tarafı 6a-6d bitti (61/61 unit test ✅, `flutter analyze` clean), AMA mimariyi etkileyen büyük bir tasarım pivotu Mehmet'ten geldi:

Mevcut "sürekli VAD + auto dil tespit + side detection" mimarisi yerine **donanım ayrımı** önerildi:
- **Headset Mode** (kulaklık takılı) — Yorum X paralel dual mic mi / Yorum Y tek mic + audio routing mi belirsiz
- **Handset Mode** (kulaklıksız) — push-to-talk, ekran ortadan ikiye bölünür, turn-based
- **Manuel Çeviri** — mevcut `TranslationTestScreen` korunur

Onaylı sub-kararlar: otomatik mod seçimi, ML Kit Language ID silinecek, `SessionMode.fast/full → headset/handset` revize.

### Sıradaki tur açılışında ne yapılır

1. **Önce Mehmet'e Headset Mode'un teknik niyetini sor**: Yorum X (paralel dual mic) mi, Yorum Y (tek mic + audio routing) mi? Tüm detay + 3 sahne (A/B/C) `punch_board.md` 2026-05-17 akşam entry'sinde.
2. Karar geldikten sonra:
   - Eğer X → önce ~3-5 saatlik POC (Flutter native Kotlin plugin, Poco X3 Pro'da dual `AudioRecord` paralel kayıt çalışıyor mu test). MIUI / cihaz limiti varsa pivot.
   - Eğer Y → daha sade refactor, 2 mod yeterli olabilir.
3. `HERMES_KONUSMA_MODU_TASARIM.md` revize.
4. Eski kodu temizle: `lib/core/engines/language_id/` + test'leri sil, pubspec'ten `google_mlkit_language_id` çıkar, `ConversationSessionManager` constructor'dan `languageDetector` + `_classifyParticipant` çıkar.
5. `SessionMode.fast/full → headset/handset` (Drift schema string column'una migration / `fromDbValue` mapping). **Mehmet'in cihazında Step 5 cihaz testinden 2 oturum var, korumak gerek.**
6. Yeni kod: Strategy `AudioInput` (Headset/Handset impl), Manager refactor, UI (3 mod kart + Handset bölünmüş ekran + Headset chat).
7. Test + cihaz testi.

### Sıradaki Adımlar (Faz 1 kalan)

- [~] **Step 6 — ConversationSessionManager** — kod tarafı 6a-6d bitti (`LanguageDetector`, `WavWriter`, `ConversationSessionManager`, TTS guard + mode davranışı), 61/61 test geçer ama **tasarım pivotu nedeniyle önemli kısmı silinecek/refactor edilecek**. 6e (debug ekranı) ve 6f (cihaz testi) yapılmadı.
- [ ] **Step 7 — ConversationScreen UI** (chat akışı, mod toggle, filler ayarları)
- [ ] **Step 8 — Ana ekran navigation + mod seçimi**
- [ ] **Step 9 — Polish** (TTS-mikrofon feedback guard, confidence drop, wakelock_plus, kalibrasyon)

---

## Faz 2 — Genişletmeler

- [ ] Android **foreground service** (cebe atıp konuşmaya devam)
- [ ] iOS **background audio mode** (App Store risk değerlendirmesi sonrası)
- [ ] **Gemini Flash online cleanup** (opsiyonel "Online dil cilalama" toggle'ı)
- [ ] **Belge Modu** (kamera OCR + görüntüden çeviri)
- [ ] **Coqui TTS** (Native OS yerine, daha doğal ses)
- [ ] **Offline harita tile cache**
- [ ] **Anki / PDF export** (oturum geçmişi)

## Faz 3 — Gelişmiş

- [ ] **SeamlessM4T** (ses→ses direkt, STT+Translate+TTS tek model)
- [ ] **GeoEngine entegrasyonu** (Belge Modu üzerinden)
- [ ] **Konuşmacı diarization** (3+ kişi)
- [ ] **Real-time partial transcript** (canlı altyazı)

---

## Risk & Borç Takibi

| Konu | Durum | Not |
|---|---|---|
| NDK r29-beta1 | Aktif risk | `whisper_ggml` strict istemiş; production release öncesi stable r29 çıkarsa upgrade |
| `flutter_lints: ^6.0.0` modern olmasına rağmen 13 paket outdated | İzlemde | `permission_handler`, `record`, `google_fonts` major bump'lar var; Faz 2'de toplu upgrade |
| TTS feedback loop (mikrofon kendi sesini duyar) | Bilinen risk | Step 9 polish'inde guard kodu yazılacak |
| Whisper small modeli (Faz 1'de seçilemiyor) | Beklemede | Cihazda küçük model varsayılan; Settings'te toggle Step 7+ |

---

## Polish Notları (Step 9 için biriken cihaz testi gözlemleri)

> Bu bölüm her cihaz testinin AYNEN raw geri bildirimini + analizini saklar.
> Step 9'a gelindiğinde tek tek elden geçirilir ve fix/feature olarak ele alınır.
> **İLKE: Kullanıcı testte ne söylediyse buraya birebir yazılır, parafraze edilmez.**

### Step 1 — TTS cihaz testi (2026-05-17)

**Kullanıcı geri bildirimi (birebir):**
> "6 maddenin her biri doğru şekilde çalışıyor ancak bazı sorunlar var:
> 1-) bahsettiğim indirilmiş olan ve olmayan diller mevcut değil.
> 2-) 'çevrilecek metin (yaz veya konuş)' alanına tıklandığında bottom overflowed by 2.3 pixels uyarısı veriyor.
> 3-) session mantığı implemente edilmemiş.
> 4-) sesler çok robotik ses paketlerini ilerde veya uygun görüyorsan şimdiden değiştirelim."

**Aksiyonlar:**
- 1 → Step 2'de yapıldı ✅
- 2 → Step 2'de Switch tap target ile düzeltildi ✅
- 3 → Step 6'ya planlandı (ConversationSessionManager)
- 4 → **Step 9 polish notu**: Native TTS robotic geliyor. İki yaklaşım: (a) Settings ekranında "Cihaz TTS engine'ini Google TTS yap" yönlendirmesi (Xiaomi cihazlarda varsayılan TTS robotic, Google TTS daha doğal), (b) `setSpeechRate` 0.5 → 0.55 ince ayar. Coqui/neural TTS Faz 2'ye işaretli.

### Step 3 — VAD (Silero v4) cihaz testi (2026-05-17)

**Kullanıcı geri bildirimi (birebir):**
> "1: her şey doğru.
> 2: her şey doğru her cümleyi tespit etti sadece 'iki kahve lütfen'de kısa olması ve benim biraz hızlı söylemem sebebiyle bazen algılayamadı.
> 3: her şey doğru çalıştı.
> 4: 'ee' veya öksürük gibi sesleri ekran yüzüme dönükse veya mikrofon ağzıma yakınsa sözce olarak algılandı, eğer ekran yüzüme dönük değilse veya mikrofon ağzıma yakın değilse hem sözce olarak hem de misfire olarak algılamadı yani direk duymazdan geldi ancak en sevdiğim özelliği yankılı bir koridordaydım ve uzakta birisi telefonla konuşuyordu onun sesini tespit etti ve misfire olarak değerlendirdi.
> 5: sessizlikte hiçbir sayaç artmadı uzakta birisi telefonla konuşuyor olmasına rağmen hiç bir sayaç artmadı."

**Analiz:**
> Mükemmel sonuçlar — özellikle 4. madde Silero VAD'in kalitesini doğruluyor: yakındaki "ee"/öksürük false positive bazen kaçıyor (mikrofon SNR yüksek olunca konuşma sanıyor, beklenen), ama uzaktaki gerçek başka konuşma misfire olarak sınıflandırıldı — yani konuşma tespit edildi ama min frame eşiğini geçemedi → kabul edilmedi. Sessizlikte sayaç artmadı = gürültü kalibrasyonu doğru.
>
> "İki kahve lütfen" kaçırılması bilinen trade-off: `minSpeechFrames=3` varsayılan eşik, hızlı/kısa cümlelerde feed yetmiyor.

**Step 9 polish'de değerlendirilecek aksiyonlar:**
- VAD: `minSpeechFrames: 3 → 2` veya v5 modeline geçiş (kısa "iki kahve lütfen" tipi cümleleri kurtarmak için)
- VAD: Yakın mikrofon false positive'i için ek filter — belki RealSpeechStart event'ini bekleyip SpeechStart'taki erken tetiklemeyi yutma; ya da `positiveSpeechThreshold: 0.5 → 0.55` ile sınırı yukarı çekme
- Cihazda v5 modelini de bundle'a ekle (silero_vad_v5.onnx), Settings'te `SileroVadController(modelVersion: 'v4' | 'v5')` toggle
- **Koruma altına alınmalı**: uzaktaki gerçek başka konuşma → misfire davranışı; bu Konuşma Modu'nda kritik (false trigger önler). Min frame ayarını düşürürken bu davranışı bozmamaya dikkat.

### Step 5 — Drift + ConversationRepository cihaz testi (2026-05-17)

**Kullanıcı geri bildirimi (birebir):**
> "bütün testler başarılı!"

Test senaryoları (Mehmet'in cihazda uyguladığı 6 adım):
1. AppBar → storage ikonu → DB Test ekranı açıldı, "(henüz oturum yok)" yazısı görüldü
2. `Oturum Aç` → `#1 tr ↔ en · fast` kartı + yeşil "açık" etiketi + `Oturum #1 açıldı.` status — ✅
3. `Mesaj Ekle` 3× → tr "Merhaba, nasılsın?", en "I am fine, thank you.", tr "İki kahve lütfen." sırasıyla düştü, sayaç 3'e çıktı — ✅
4. `Oturumu Kapat` → yeşil "açık" → gri "kapalı HH:MM:SS", status `Oturum #1 kapatıldı.` — ✅
5. Yeni `Oturum Aç` + mesaj → `#2` üstte, `#1` aşağıda (en yeni önce sıralama) — ✅
6. **Kalıcılık testi**: Recent apps'tan kill → tekrar aç → DB Test ekranında `#1` ve `#2` tüm mesajlarıyla yerinde — ✅

**Analiz / Aksiyonlar:**
- SQLite native lib (`sqlite3_flutter_libs`) Poco X3 Pro Android 13'te sorunsuz yüklendi.
- `getApplicationDocumentsDirectory()` altındaki `hermes.sqlite` dosyası cold-start sonrası persist ediyor.
- `PRAGMA foreign_keys=ON` `beforeOpen` migration cihazda da geçerli (cascade delete unit test'te doğrulandı, prod'da Step 6'da olası senaryolarda gözlenecek).
- `startedAt` desc + id desc tiebreak prod sıralamada doğru çalıştı (aynı saniyede iki oturum açıldı senaryosu).
- **Step 9'a not yok** — geri bildirim "her şey beklendiği gibi", polish gerektiren gözlem yok.
- **Korunmasını istediğimiz davranış**: cold-start kalıcılığı. Step 6 `ConversationSessionManager` yazılırken `AppDatabase` instance lifecycle'ı (singleton mı app-scope DI mı?) dikkat: birden fazla `AppDatabase()` aynı dosyayı locklayabilir → Step 6'da DI ile tek instance şart.

---

### Polish notu kaydetme ilkesi

Her cihaz testi sonrasında kullanıcı geri bildirimi bu bölüme **birebir, parafraze etmeden** eklenir. Format:
```
### Step N — [özellik adı] cihaz testi (YYYY-MM-DD)

**Kullanıcı geri bildirimi (birebir):**
> "...kullanıcının yazdığı her şey..."

**Analiz / Aksiyonlar:**
- Hemen düzeltilecek olanlar
- Step 9'a not edilenler
- Korunmasını istediğimiz davranışlar
```

---

## Süreç Notları

- Her step bitiminde: `flutter analyze` clean → USB cihaz testi → roadmap güncelle → sonraki step
- Tasarım/kararlarda değişiklik gerekirse önce `HERMES_KONUSMA_MODU_TASARIM.md` güncellenir, sonra roadmap'e yansıtılır
- Cihaz testi başarısız olursa step yarıda kalır, fix → re-test döngüsü ile bitirilir
