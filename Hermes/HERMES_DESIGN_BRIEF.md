# Hermes — Tasarım Brief'i (Design Tool Girdisi)

> **Amaç:** Bu doküman, Hermes uygulamasının görsel/UX tasarımını bir tasarım aracı (Anthropic design tool) ile üretmek için **tek başına yeterli** bir girdidir. Proje tanımı + tasarım dili + ekran envanteri + klasör yapısı içerir. Mevcut koddan türetilmiştir (2026-06-10).
>
> **Dil:** Uygulama arayüz dili **Türkçe**. Üretilecek tüm metin/etiketler Türkçe olmalı.
> **Platform:** Flutter, **Android öncelikli** (test cihazı Poco X3 Pro). iOS demo hedefi ama Faz 1'de test edilmiyor.
> **Oryantasyon:** Tüm ekranlar **portrait (dikey) kilitli**.

---

## 1. Proje Tanımı

**Hermes**, Erasmus öğrencileri ve turistler için tasarlanmış, **tamamen çevrimdışı çalışabilen akıllı çeviri + konuşma asistanı**dır. İnternet olmadan konuşmaları gerçek zamanlı dinler, yazıya döker, çevirir ve (opsiyonel, internet varsa) yapay zekâ ile özetler.

### 1.1 Kullanıcı
- **Kim:** Yabancı ülkede yaşayan/gezen kişi (Erasmus öğrencisi, turist).
- **İhtiyaç:** Ders/konferans dinlerken anında altyazı; yerel halkla yüz yüze karşılıklı konuşma; menü/tabela çevirisi.
- **Kısıt:** İnternet her zaman yok → uygulamanın çekirdek değeri **offline** çalışmasıdır. Bulut özellikleri (Gemini özet) yalnız bonus.

### 1.2 Temel Tasarım İlkeleri
1. **Offline-first:** Çeviri/STT modelleri cihazda. İnternet sadece opsiyonel özet için.
2. **Sade & açık (light) tasarım:** Kırık beyaz zemin, beyaz kartlar, mor marka aksanı. Göz yormayan, "şık ve temiz".
3. **Modlar net ayrılmış:** Ana ekran 4 büyük kart → her kart bir kullanım senaryosu.
4. **Tüm indirmeler tek yerde (Ayarlar):** Modların içinde inline model indirme YOK. Model eksikse kullanıcı bir "kapı" ekranıyla Ayarlar'a yönlendirilir.
5. **Ses kaydı yok, transkript var:** Gizlilik — yalnız metin saklanır.

### 1.3 Teknik Mimari Özeti (tasarımı etkileyen kısım)
- **Strategy Pattern:** STT (konuşma→metin), Translation (çeviri), TTS (metin→ses), VAD (ses aktivite tespiti), AudioInput hepsi değiştirilebilir motor.
- **Kalite katmanları (kullanıcıya gösterilir):**
  - **Hızlı (fast):** Vosk/ML Kit — hafif, hızlı, daha düşük doğruluk.
  - **Akıllı (full):** Whisper + NLLB — ağır, doğru, daha fazla RAM ister.
  - **Akıllı+ (full+):** yalnız hands-free SmallTalk'ta — Whisper + NLLB.
- **Düşük-RAM uyarısı:** Ağır katman seçilince düşük bellekli cihazda "Yine de kullan / İptal" uyarısı.
- **Özet (crunch):** Oturum bitince transkript yapay zekâ ile çevrilip özetlenir. İki yol: (a) cihazda **Gemma3-1B**, (b) internet varsa kullanıcının kendi **Gemini API anahtarı**.

---

## 2. Tasarım Dili (mevcut koddan — `app_theme.dart`)

Bu palet **kanonik**tir; tasarım bunu temel almalı.

### 2.1 Renkler (`HermesColors`)
| Rol | Hex | Kullanım |
|---|---|---|
| `bg` (sayfa arka planı) | `#F7F7FB` | kırık beyaz, scaffold zemini |
| `surface` (kart/yüzey) | `#FFFFFF` | saf beyaz kartlar, appbar, input |
| `border` (kenarlık/ayraç) | `#E6E6EF` | ince çizgiler, kart kenarı |
| `accent` (marka moru) | `#6C5CE7` | birincil aksan, vurgular, odak |
| `accentSoft` | `#EDEAFB` | mor aksanın açık zemini (chip/badge) |
| `textPrimary` | `#1B1B2A` | birincil metin (koyu lacivert-gri) |
| `textSecondary` | `#6B6B7B` | ikincil/açıklama metni |
| `textFaint` | `#9A9AAB` | placeholder/soluk |
| `crunch` (özet moru) | `#8E44E8` | yapay zekâ özet aksanı |
| `success` (hazır yeşili) | `#2E9E6B` | "hazır/indirildi" durumları, SmallTalk aksanı |
| `danger` (hata) | `#D64545` | hata/uyarı metinleri |

Mod-bazlı ek aksanlar (ana ekran kartlarında):
- Konferans → `accent` (`#6C5CE7`)
- SmallTalk → `success` (`#2E9E6B`)
- Manuel Çeviri → amber `#CB8A2E`
- Görsel Çeviri → mavi `#2E8DB0`

### 2.2 Bileşen Stili
- **Tema:** Material 3, açık (light), `seedColor = accent`.
- **AppBar:** beyaz zemin, koyu metin, gölgesiz (elevation 0), başlık sola yaslı.
- **Kart (`HermesCard`):** beyaz zemin, 12px köşe yarıçapı, 1px `border` kenarlık, gölge yok. İçerik: sol ikon (mod aksan rengi) + başlık + alt açıklama (`textSecondary`) + opsiyonel trailing ikon (ör. arşiv klasörü).
- **Input:** dolu beyaz, 10px köşe, `border` kenarlık; odakta `accent` 1.5px.
- **Köşe yarıçapı standardı:** kart 12, input/buton 10.
- **Snackbar:** floating.
- **Genel his:** bol beyaz boşluk, ince ayraçlar, düz (flat) yüzeyler, minimal gölge.

---

## 3. Navigasyon & Ekran Envanteri

> ⚠️ Aşağıdaki **kullanıcıya dönük ekranlar** tasarlanır. Kod tabanındaki `🧪` ile işaretli geliştirici/test ekranları (vosk_test, nllb_test, opus_mt_test, small100_test, llm_translate_test, vad_test, streaming_test, session_test, db_test, dual_mic_test, push_to_talk_test, crunch_derisk, vosk_en_derisk) **tasarım kapsamı dışında** — sadece geliştirme amaçlı.

### Üst seviye akış
```
Ana Ekran (Home)
├── Konferans Modu  → Konferans Setup → Konferans (canlı) → [bitince] Konferans Detay
│                      └── Konferanslarım (Arşiv) → Konferans Detay
├── SmallTalk        → SmallTalk Setup → (Bas Konuş ekranı | Hands-free Setup → SmallTalk canlı) → [bitince] Detay
│                      └── SmallTalk'larım (Arşiv) → Detay
├── Manuel Çeviri    → Manuel Çeviri ekranı
├── Görsel Çeviri    → OCR ekranı
└── Ayarlar (appbar) → Model yönetimi (indir/sil/durum)

[Her mod girişinde model eksikse] → ModelsRequiredGate (→ Ayarlar)
[Ağır katman + düşük RAM]         → Düşük-RAM uyarı dialogu
```

### 3.1 Ana Ekran (Home)
- **Amaç:** Mod seçimi.
- **İçerik:** AppBar başlık "Hermes" + sağda Ayarlar ikonu. "Bir mod seç" alt başlığı. Altında dikey liste halinde 4 `HermesCard`:
  1. **Konferans Modu** — "Canlı çeviri + transkript + sonradan yapay zekâ özeti" (ikon: sunum; aksan mor). Trailing: "Konferanslarım" klasör ikonu.
  2. **SmallTalk** — "Karşılıklı çeviri — bas konuş veya hands-free" (ikon: forum; aksan yeşil). Trailing: "SmallTalk'larım" klasör ikonu.
  3. **Manuel Çeviri** — "Yaz, çevir, dinle (menü/tabela)" (ikon: translate; aksan amber).
  4. **Görsel Çeviri** — "Fotoğraf çek/seç → metni tanı → çevir" (ikon: belge tarayıcı; aksan mavi).

### 3.2 Konferans Modu (tek yönlü dinleme)
- **Senaryo:** Telefonu kenara koy, dersi/konuşmacıyı dinle, ekranda canlı altyazıyı oku. Bitince yapay zekâ özeti al.
- **Konferans Setup:** Adımlar — kaynak dil (konuşulan dil) + hedef dil (kullanıcı dili) + kalite (Hızlı / Akıllı). Model eksikse kapıya yönlendir.
- **Konferans (canlı ekran):** Tek sütun, alt alta dökülen mesaj baloncukları. Her mesaj: üstte küçük gri **orijinal** (konuşma dili), altında büyük **çeviri** (kullanıcı dili). Üstte/altta kontrol: ▶ Başlat / ⏸ Duraklat / ■ Bitir. Canlı "dinleniyor" göstergesi.
- **Konferans Detay:** Bitmiş oturumun başlığı + tarih + tam transkript. Aksiyonlar: **Transkripti Kopyala** (her zaman); model/anahtar varsa **Derinlemesine Çevir** + **Özetle** (yerel Gemma3) veya **Gemini ile Çevir & Özetle / Gemini ile Özetle** (internet — "veri Google'a gider" notu). Özet sonucu: başlık + anlatı özeti (ana hikaye, önemli noktalar).
- **Konferanslarım (Arşiv):** Kayıtlı konferansların listesi (başlık + tarih + mesaj sayısı). Tıkla → Detay.

### 3.3 SmallTalk (karşılıklı, iki yönlü çeviri)
- **Senaryo:** İki kişi yüz yüze, sırayla konuşur. Telefon tek cihaz.
- **SmallTalk Setup:** Dil çifti + mod seçimi: **Bas Konuş** veya **Hands-free**.
- **Bas Konuş ekranı (turn-based, tek mic):** App'in **en sıradışı ekranı** — portrait, **tam ekran (immersive, sistem çubukları gizli)**, aksan rengi yeşil (`success #2E9E6B`). 4 fazı var; tasarım dördünü de kapsamalı:

  **a) Isınma fazı (girişte):** Motorlar arka planda yüklenirken ekran ortasında büyük (≈96px) **dairesel başlat butonu**. Yüklenirken: gri daire + üstünde dönen ilerleme halkası + kum saati ikonu + "Isınıyor…". Hazır olunca: yeşil daire + ▶ play ikonu + "Bas Konuş — Başlat". Altında dil çifti (`{kaynak} ↔ {hedef}`, soluk) + "Geri" metin butonu.

  **b) Çalışan faz (bölünmüş ekran):** Ekran ortadan **yatay 2px ayraçla** ikiye bölünür.
  - **Üst yarı = karşı taraf:** tüm içerik **180° döndürülmüş** (`RotatedBox` — karşıdaki kişi telefon kendine dönükken normal okur).
  - **Alt yarı = kullanıcı:** normal yön.
  - **Her yarının tamamı görünmez bas-konuş alanı:** o yarıya basılı tut → o tarafın sesi kaydedilir, bırak → çevrilir. Görünür buton yok. Bir yarı kayıttayken **diğer yarı kilitli** (aynı anda iki taraf konuşamaz).
  - **Kayıt göstergesi:** basılı tutulan yarının zemini yeşile (≈%14) boyanır + ortada mic ikonu + "konuş…" yazısı.
  - **Chat baloncukları:** her yarıda o tarafın okuduğu dilde son ≈6 mesaj. Kendi mesajı sağa yaslı + yeşil tonlu balon; karşının (çevrilmiş) mesajı sola yaslı + beyaz balon (1px `border`, 12px köşe). Boş durumda ipucu: "basılı tut · konuş ({dil})".
  - **Ortada yüzen kontrol hapı:** beyaz, yuvarlak köşeli pill — **Bitir** (kırmızı `stop` ikonu) + dil çifti etiketi + işlem sürerken küçük yeşil spinner.

  **c) Bitti fazı:** Ortada ✓ (yeşil) + "Konuşma kaydedildi." + "Tam çeviri + özet + başlık çıkarmak ister misin?". İki buton: **"Çevir & Özetle"** (dolu mor, → Detay ekranı) ve **"Crunch later"** (kenarlıklı, → ana ekrana dön).

  **d) Hata fazı:** ⚠ (kırmızı) + "Bas Konuş başlatılamadı. Lütfen tekrar deneyin." + "Geri" butonu.

  > **Not:** Detay/özet ve arşiv, Konferans ile **aynı** ekranları kullanır (oturum `mode=pushToTalk` ile "SmallTalk'larım" arşivine düşer).

- **Hands-free akışı (eller serbest, otomatik konuşmacı ayrımı):** Tek mic, iki tanıyıcı; kimin konuştuğu güven skoruyla otomatik ayrılır — buton yok. **Görsel olarak Konferans kalıbını miras alır (mor `accent` teması)**, Bas Konuş'un yeşilinden farklı.

  **Hands-free Setup — 3 adımlı sihirbaz** (üstte appbar "SmallTalk — Hands-free", adımlar arası yumuşak geçiş):
  1. **Diller:** "Senin dilin (master)" dropdown + ortada **↕ dilleri değiştir** ikon butonu + "Karşı kişinin dili (local)" dropdown. İki dil aynıysa "İki dil farklı olmalı" uyarısı; geçerliyse "Devam".
  2. **Seslendirme:** "Karşı kişinin çevirisi senin kulaklığına sesli okunsun mu?" → iki **seçim kartı**: 🎧 "Evet, kulaklığa seslendir" / 📝 "Hayır, sadece ekran (play ile dinlersin)". (Kartlar: sol mor `accentSoft` ikon kutusu + başlık + alt açıklama + sağ chevron.)
  3. **Mod (kalite):** 3 seçim kartı — ⚡ **Hızlı** (Vosk + ML Kit; en hızlı, konuşmacı ayrımı yaklaşık) / ✓ **Tam** (Whisper + ML Kit; güvenilir ayrım) / ✨ **Tam+** (Whisper + NLLB; en kaliteli, ağır/yüksek RAM). **Tam+ seçilince düşük-RAM uyarı dialogu.**

  **SmallTalk canlı (hands-free) — fazlar:**
  - **Model kontrol / kapı:** Model eksikse `ModelsRequiredGate` (eksik adlar: Whisper/Vosk + ML Kit/NLLB → Ayarlar).
  - **Isınma:** Ortada büyük (≈168px) dairesel **"SmallTalk Başlat"** butonu (yüklenirken gri + dönen halka + "Isınıyor…"; hazır olunca mor + ▶ + "Hazır · dokun"). Altta dil çifti `{master} (sen) ↔ {local}` + seslendirme açıksa `🎧 seslendirme` rozeti.
  - **Çalışan:** Üstte ince bar — yeşil canlı noktası + "Canlı" + dil çifti. Altında **akan chat baloncukları**: **master = sağ** (büyük transkript + altında küçük gri çeviri + 🔊 play), **local = sol** (küçük gri transkript + büyük çeviri + 🔊 play). En altta **canlı partial satırı** (italik, soluk — tanınmakta olan konuşma) + tam genişlik **"SmallTalk'ı Bitir"** kenarlıklı butonu.
  - **Bitti:** ✓ + "Konuşma kaydedildi." + **"Çevir & Özetle"** (dolu **mor crunch** rengi → Detay) + **"Crunch later"** (→ ana ekran).
  - **Hata:** ⚠ + mesaj + "Geri".
- **SmallTalk Detay & Arşiv:** Konferans ile aynı kalıp (başlık/tarih/transkript + kopyala + özet; "SmallTalk'larım" listesi). Bas Konuş ve hands-free oturumları aynı arşivde toplanır.

### 3.4 Manuel Çeviri
- **Senaryo:** Menü/tabela için yaz-çevir-dinle.
- **İçerik:** Kaynak/hedef dil seçici + kalite seçici (Hızlı=ML Kit / Akıllı=NLLB). Metin giriş alanı → "Çevir" → çeviri sonucu kartı → "Dinle" (TTS) butonu.

### 3.5 Görsel Çeviri (OCR)
- **Senaryo:** Fotoğraftaki yazıyı çevir.
- **İçerik:** Kaynak dil ("Otomatik algıla" seçeneği dahil) + hedef dil. "Fotoğraf çek" / "Galeriden seç" butonları. Sonuç: orijinal tanınan metin + çeviri kartı. (Faz 2'de canlı kamera overlay — arayüz değişmez.)

### 3.6 Ayarlar (Model Yönetimi)
- **Amaç:** **Tüm model indirmeleri burada.** Kategorilere ayrılmış model listesi:
  - **STT:** Whisper (small), Vosk modelleri.
  - **Çeviri Modelleri (NMT):** NLLB-600M.
  - **Özet Modeli (Crunch):** Gemma3-1B.
  - **Çevrimiçi Özet (Gemini):** API anahtarı ekle/düzenle (maskeli `••••xxxx` gösterim) + gizlilik notu.
- Her model satırı: ad + boyut (MB) + durum (indirildi ✓ / indir / sil). İndirirken **ilerleme çubuğu + yüzde + hız (MB/s) + inen/toplam MB + tahmini süre (ETA)**. (Bazı modeller — ML Kit/Whisper — yalnız boyut + "indiriliyor…" gösterir.)

### 3.7 Paylaşılan / Yardımcı Ekranlar
- **ModelsRequiredGate:** Bir moda girişte gerekli modeller eksikse: açıklama + **eksik model adları** + "Ayarları Aç" butonu + "Geri". Ayarlar'dan dönünce otomatik yeniden kontrol.
- **Düşük-RAM uyarı dialogu:** Ağır katman + düşük bellek → "Cihaz belleği düşük (~X GB). Yine de Akıllı kullanılsın mı?" → İptal / Yine de kullan.
- **HermesCard:** Tüm liste öğelerinin temel kartı (ikon + başlık + açıklama + opsiyonel trailing).

---

## 4. Klasör Yapısı Tanımı

Flutter projesi kökü: `Hermes/hermes/`. Kaynak `lib/` altında **`core/` (motor/mantık)** ve **`features/` (ekranlar)** olarak ikiye ayrılır.

```
hermes/
├── lib/
│   ├── main.dart                      # Uygulama girişi; tema = hermesLightTheme; portrait kilidi; Manuel Çeviri (TranslationTestScreen) burada
│   │
│   ├── core/                          # İş mantığı, motorlar, veri — UI'dan bağımsız
│   │   ├── theme/
│   │   │   └── app_theme.dart         # HermesColors paleti + hermesLightTheme (KANONİK tasarım kaynağı)
│   │   │
│   │   ├── audio/                     # Ses giriş stratejileri (AudioInput interface)
│   │   │   ├── audio_input.dart           # interface + AudioUtteranceEvent + AudioSource{primary,secondary}
│   │   │   ├── single_mic_audio_input.dart    # Ders/Konferans — tek mic, VAD sarmalı
│   │   │   ├── push_to_talk_audio_input.dart  # Bas Konuş — buton=utterance sınırı, ham PCM
│   │   │   ├── streaming_audio_input.dart     # hands-free streaming
│   │   │   ├── dual_mic_channel.dart          # (Faz 2, ertelendi) çift mic native kanal
│   │   │   └── wav_writer.dart
│   │   │
│   │   ├── engines/                   # Değiştirilebilir motorlar (Strategy Pattern)
│   │   │   ├── stt/                       # Konuşma→Metin: whisper_cpp, vosk, hybrid
│   │   │   ├── translation/               # Çeviri: google_mlkit, nllb, llm, opus_mt, small100 + translation_tier (Hızlı/Akıllı katman tanımı)
│   │   │   ├── tts/                        # Metin→Ses: native_tts, silent
│   │   │   ├── ocr/                        # Görsel: mlkit_text_recognizer
│   │   │   └── language_id/                # Dil tespiti (ML Kit) — çoğunlukla pasif
│   │   │
│   │   ├── models/                    # İndirilebilir model yöneticileri + Ayarlar'daki ManagedModel kayıtları
│   │   │   ├── managed_model.dart          # Ayarlar listesi için model soyutlaması (boyut, durum, indir/sil)
│   │   │   ├── nllb_model_manager.dart     # NLLB 4 dosya (GitHub Release host)
│   │   │   ├── vosk_models.dart / vosk_model_manager.dart
│   │   │   └── opus_mt / small100 manager'ları
│   │   │
│   │   ├── services/                  # Saf servisler
│   │   │   ├── crunch_service.dart         # Transkript → çeviri + özet (chunk/reduce/başlık)
│   │   │   ├── gemini_client.dart          # Çevrimiçi özet (gemini-2.0-flash REST)
│   │   │   ├── gemini_key_store.dart       # Gemini API anahtarı saklama (shared_preferences)
│   │   │   ├── hf_token_store.dart         # HuggingFace token saklama
│   │   │   ├── device_memory.dart          # RAM tespiti + düşük-RAM eşiği
│   │   │   ├── download_stats.dart         # indirme hız/ETA/yüzde hesabı
│   │   │   ├── filler_cleaner.dart         # dolgu sesi temizleme (ee, mmm, yani…)
│   │   │   ├── title_generator.dart        # oturum başlığı (timestamp fallback / online)
│   │   │   └── vad_controller.dart         # Silero VAD — ses aktivite tespiti
│   │   │
│   │   ├── session/                   # Canlı oturum yöneticileri
│   │   │   ├── conversation_session_manager.dart  # çekirdek: utterance → STT → çeviri → repo
│   │   │   ├── conference_streaming_session.dart
│   │   │   └── smalltalk_streaming_session.dart
│   │   │
│   │   ├── database/                  # Drift (SQLite) — sessions + messages
│   │   │   ├── app_database.dart           # tablolar, migration
│   │   │   └── app_database.g.dart         # codegen (build_runner)
│   │   │
│   │   ├── repositories/
│   │   │   └── conversation_repository.dart  # SessionMode + SessionQuality{fast,full,fullPlus} + CRUD
│   │   │
│   │   └── utils/
│   │       └── llm_text.dart
│   │
│   └── features/                      # Ekranlar (her klasör bir özellik)
│       ├── home/home_screen.dart              # Ana ekran (mod kartları)
│       ├── conference/                        # Konferans: setup, screen, detail, archive, crunch_runner, format, theme
│       ├── smalltalk/                         # SmallTalk: setup, handsfree_setup, screen, archive
│       ├── push_to_talk/push_to_talk_screen.dart   # Bas Konuş (180° üst yarı, görünmez tap alanı)
│       ├── ocr_translate/ocr_translate_screen.dart # Görsel Çeviri
│       ├── settings/settings_screen.dart      # Ayarlar (model yönetimi + Gemini anahtarı)
│       ├── mode_entry/                         # language_select_screen + model_tier_selector (ortak dil/kalite seçici)
│       └── shared/                             # Paylaşılan widget'lar
│           ├── hermes_card.dart                    # temel kart
│           ├── models_required_gate.dart           # eksik model kapısı → Ayarlar
│           └── low_ram_warning.dart                # düşük-RAM dialogu
│
├── android/                           # Android native (NDK 29 pinli, izinler, plugin)
├── pubspec.yaml                       # Bağımlılıklar
└── test/                              # Unit + widget testleri (188 test)
```

### Klasör katmanı kuralları
- **`core/` UI bilmez:** sadece motor/servis/veri. Ekranlar `core`'u kullanır, tersi olmaz.
- **`features/<x>/`:** her kullanıcı senaryosu kendi klasöründe. Ekran widget'ları burada.
- **`features/shared/`:** birden çok feature'ın paylaştığı widget'lar.
- **Tasarım tek kaynak:** tüm ekranlar `core/theme/app_theme.dart`'tan renk/tema alır; ekran içinde gömülü renk verilmez (mod aksan renkleri hariç).
- **🧪 dev/test ekranları** (yukarıda listelenenler) ayrı `features/*_test/` ve `*_derisk/` klasörlerinde; **son kullanıcı tasarımına dahil değil.**

---

## 5. Tasarım Aracı İçin Özet Talimat

> Hermes için **açık (light) temalı, sade ve şık** bir mobil arayüz tasarla. Kırık beyaz zemin (`#F7F7FB`), saf beyaz kartlar (1px `#E6E6EF` kenarlık, 12px köşe, gölgesiz), mor marka aksanı (`#6C5CE7`). Portrait, Android öncelikli, Türkçe metin. Bol beyaz boşluk, ince ayraçlar, minimal gölge. Tasarlanacak ekranlar: Ana Ekran (4 mod kartı), Konferans (setup + canlı altyazı + detay/özet + arşiv), SmallTalk (setup + bas-konuş bölünmüş ekran + hands-free + arşiv), Manuel Çeviri, Görsel Çeviri (OCR), Ayarlar (model indirme listesi), ve yardımcı durumlar (eksik-model kapısı, düşük-RAM uyarısı). §3'teki her ekranın amacı/içeriği ve §2'deki palet/bileşen stiline sadık kal.
