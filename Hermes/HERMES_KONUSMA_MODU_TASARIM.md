# Hermes — 3 Mod Mimarisi Tasarım

**Statü:** Tüm kararlar final (2026-05-30). Step 6 refactor için blueprint.
**Yazıldığı tarih:** 2026-05-30 (revizyon; 2026-05-17 versiyonu için git history)
**Bağlam:** 2026-05-17 akşamı Mehmet "donanım ayrımı" pivotu önerdi. 2026-05-30'da 3 mod (Ders Modu + Voice Translator + Bas Konuş) ve Yöntem B (kulaklık+telefon çift mic dinleme) kesinleşti. Bu doküman yeni mimariyi tarifler. Eski tasarım (sürekli VAD + auto dil tespit + tek mod) git history'de korunmuştur.

---

## 1. Vizyon

Hermes 3 mod sunar:

1. **Ders Modu** — Tek yönlü, live subtitles + transkript + sonradan Gemini özet. Hoca/konuşmacıyı dinler.
2. **Voice Translator** — Çift yönlü, kulaklık zorunlu, çift mic donanım ayrımı. Yüz yüze konuşma.
3. **Bas Konuş Modu** — Voice Translator'ın kulaklıksız alternatifi. Ahize modu, ekran ortadan ikiye bölünür, push-to-talk.

Her mod altında iki kalite seviyesi:
- `fast` (Whisper tiny, hız öncelik)
- `full` (Whisper small, doğruluk öncelik)

Ortak özellikler:
- **Transkript kaydedilir** (ses kaydı **YOK**)
- **Başlık otomasyonu:** internet varsa Gemini içerikten, yoksa timestamp fallback
- **Strategy Pattern:** STT / Translate / TTS / AudioInput hepsi değiştirilebilir interface
- Bağımsız 4. seçenek: **Manuel Çeviri** (mevcut `TranslationTestScreen`, modlardan ayrı ana ekranda kalır)

---

## 2. Modlar Detayı

### 2.1 Ders Modu

**Senaryo:** Telefonu açıp ders modunu başlatır, kenara koyar, dersi dinler. Anlamadığın bir kelime olduğunda ya da dili hiç bilmiyorsan ekrandaki live subtitles'a bakarsın.

**Akış:**
1. Ana ekran → Ders Modu → dil seçimi (kaynak = ders dili, hedef = kullanıcı dili)
2. ▶ Başlat → mikrofon sürekli açık, VAD utterance'ları yakalar
3. Her utterance → Whisper (kaynak dili `language` parametresiyle forced) → Translate → chat'e live subtitle olarak düşer
4. Opsiyonel: Kulaklık takılıysa → TTS çevirisi kulaklığa sesli verilir (izlenmesi gereken ders senaryosu)
5. ⏸ Duraklat / ■ Bitir
6. **Sonradan:** internet varsa Gemini özet + önemli noktalar (Faz 1 Step 8/9'da, ileride)

**UI:** Tek sütun chat, mesajlar alt alta. Her mesaj: küçük gri orijinal (ders dili), altta büyük beyaz çeviri (kullanıcı dili).

**Audio Input:** `SingleMicAudioInput` — Android default routing (kulaklık varsa kulaklığa, yoksa dahili mic).

**Quality default:** `full` (doğruluk öncelik). Settings'ten `fast` toggle.

### 2.2 Voice Translator (kulaklık zorunlu)

**Senaryo:** Erasmus öğrencisi sokakta yerel halkla konuşuyor. Kullanıcı kulaklığını takmış, karşı taraf kulaklıksız.

**Donanım kurulumu:**
- Kullanıcı (sadece app'i kullanan): Bluetooth/kablolu kulaklık
- Karşı taraf: kulaklıksız
- **Mic A = kulaklık mic'i** → kullanıcının sesi → mesaj **sağ** tarafa
- **Mic B = telefon dahili mic'i** → karşı tarafın sesi → mesaj **sol** tarafa
- Her iki mic eş zamanlı dinlemede

**Akış:**
1. Ana ekran → Voice Translator → dil çifti seçimi (örn TR ↔ ES)
2. App kulaklık bağlı mı kontrol eder — yoksa "Kulaklık takın" uyarısı, mod başlamaz
3. ▶ Başlat → iki paralel `AudioRecord` instance açılır (`DualMicAudioInput` plugin), iki ayrı VAD pipeline
4. **Mic A** utterance bitti → Whisper (lang=TR forced) → Translate TR→ES → chat sağ tarafa düşer
5. **Mic B** utterance bitti → Whisper (lang=ES forced) → Translate ES→TR → chat sol tarafa düşer + **otomatik kulaklıktan TR seslendirilir** (kullanıcı duyar)
6. Sağ taraftaki play butonuna basılırsa → telefon hoparlöründen ES seslendirilir (karşı taraf duyar)

**Feedback loop çözümü (Yöntem B'nin asıl getirisi):**
- TTS kulaklığa → kulaklık mic'ini etkilemez (yakın olsa bile farklı transducer)
- Telefon hoparlörü sadece play butonu basıldığında ses verir → o sırada Mic B VAD bypass guard ile yutulur (kısa pencere)

**UI:**
```
SOL (karşı = ES)              SAĞ (sen = TR)
┌──────────────────────┐      ┌──────────────────────┐
│ hola como estas      │      │     ne yapıyorsun    │
│ (küçük, gri)         │      │     (küçük, gri)     │
│                      │      │                      │
│ merhaba nasılsın     │  ▶   │  qué estás haciendo  │
│ (büyük, beyaz)       │      │  (büyük, beyaz)      │
└──────────────────────┘      └──────────────────────┘
                              ▲
                       play butonu burada
```

**Audio Input:** `DualMicAudioInput` — yeni native Kotlin plugin (detay §3.2.2).

**Quality default:** `fast` (doğal konuşma temposu). Settings'ten `full` toggle.

### 2.3 Bas Konuş Modu

**Senaryo:** Kullanıcının kulaklığı yok, veya Voice Translator'ın dual mic özelliği cihazda çalışmıyor. Turist senaryosu — telefonu masaya koyar, iki kişi sırayla konuşur.

**Donanım:** Tek mic (telefon dahili), tek hoparlör.

**Cihaz oryantasyonu:** Portrait (dik tutulur). Tüm Hermes modlarında portrait zorunlu — landscape lock aktif. Bas Konuş'ta "ahize" benzetmesi içerik akışına dair, oryantasyona dair değil: telefon dik tutulur, üst yarının içeriği 180° dönmüş halde render edilir (karşıdaki kişi başını eğmeden okur).

**UI tasarımı (portrait):**
```
┌──────────────────────┐
│  ¿qué estás haciendo?│  ← üst yarı (180° döndürülmüş içerik):
│  ne yapıyorsun (gri) │     karşı taraf kendi yönünden NORMAL okur
│                      │     TÜM YARI = karşının
│                      │     görünmez bas-konuş alanı
│  ────────────────────│  ← ince düz ayraç çizgisi (ekran ortası)
│                      │
│  merhaba nasılsın    │  ← alt yarı, normal yön:
│  hola como estas (gri)│    kullanıcı okur
│                      │     TÜM YARI = kullanıcının
│                      │     görünmez bas-konuş alanı
└──────────────────────┘
```

**Akış:**
1. Ana ekran → Bas Konuş → dil çifti seçimi
2. Telefon portrait, ekran ortadan **yatay bir çizgi ile** ikiye bölünür
3. **Üst yarı:** karşı tarafın bölgesi
   - İçerik 180° döndürülmüş (text + ikon) — karşıdaki kişi telefonu kendine doğru bakarken NORMAL okur
   - **Tüm yarı görünmez bir bas-konuş butonu** — karşı taraf bu yarıya basılı tuttuğu sürece kayıt alınır
4. **Alt yarı:** kullanıcı bölgesi
   - İçerik normal yön — kullanıcı okur
   - **Tüm yarı görünmez bir bas-konuş butonu** — kullanıcı bu yarıya basılı tuttuğu sürece kayıt alınır
5. Kullanıcı alt yarıya basılı tutar → konuşur → bırakır → Whisper (lang=TR) → Translate → karşı tarafa (üst yarı, ters) yazılır + otomatik hoparlörden ES seslendirilir
6. Karşı taraf üst yarıya basılı tutar → konuşur → bırakır → Whisper (lang=ES) → Translate → kullanıcıya (alt yarı, normal) yazılır + otomatik hoparlörden TR seslendirilir

**Buton paradigması:** Ortada görünür buton **yok**. Her ekran yarısının tamamı kendi tarafının bas-konuş alanı. `GestureDetector` `onTapDown` / `onTapUp` (veya `Listener` widget) ile yakalanır. **"Kim konuşuyor" sorusu doğal olarak çözülür** — hangi yarıya parmak değdiyse o taraf konuşuyor demek.

**Üst yarıyı 180° döndürme:** Flutter'da `Transform.rotate(angle: math.pi, child: ...)` veya `RotatedBox(quarterTurns: 2, child: ...)` ile yapılır. Tüm üst yarı widget tree'si bu transform içine sarılır — text, ikon, status indicator hepsi karşı taraftan normal görünür. `GestureDetector` transform'un dışında veya içinde olabilir (touch koordinatları transform'dan etkilenmez çünkü hit-testing widget'ın ekrandaki bounding box'una göre yapılır).

**Görsel feedback (kayıt sırasında):** Aktif yarı highlight olur (örn soft glow, renk değişimi, kenar pulse animasyonu). Mikrofon ikonu veya kayıt göstergesi o yarının ortasında belirir. Karşı yarı eş zamanlı disabled görünür (TTS oynaması engellenmek için).

**Feedback loop çözümü:**
- Buton kayıt sırasında → TTS oynamaz
- TTS oynarken → buton disabled
- → Kapalı state machine, feedback loop imkânsız

**Audio Input:** `SingleMicAudioInput` + push-to-talk wrapper (buton state'i start/stop'u kontrol eder, VAD kullanılmaz).

**Quality default:** `fast`. Settings'ten `full` toggle.

---

## 3. Mimari Bileşenler

### 3.1 ConversationSessionManager (refactor)

**Yeni sorumluluklar:**
- Constructor'da `SessionMode` + `SessionQuality` + `AudioInput` alır
- `AudioInput` event stream'ini dinler (Voice Translator'da 2 source, diğerlerinde 1)
- Pipeline: `AudioInput → WavWriter → STT(language=explicit) → FillerClean → Translate → TTS + Repository`
- Eski `LanguageDetector` parametresi **çıkarıldı** (kod `lib/core/engines/language_id/` altında saklı; Step 9'da gerekirse yeniden bağlanır — bkz roadmap "Polish Notları")
- Mode'a göre TTS davranışı:
  - **Ders Modu:** opsiyonel kulaklığa (Settings toggle ile)
  - **Voice Translator:** Mic B'den gelen utterance'ın çevirisi otomatik kulaklığa, sağdaki play butonu → telefon hoparlörü
  - **Bas Konuş:** otomatik hoparlöre, buton state guard'lı

**State'ler:** `idle → starting → listening → processing → ttsPlaying → paused → ending → error`

### 3.2 AudioInput (yeni strategy)

```dart
abstract class AudioInput {
  Stream<AudioUtteranceEvent> get utterances;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

class AudioUtteranceEvent {
  final List<double> samples;   // 16kHz mono Float32 (WavWriter yutar)
  final AudioSource source;     // Hangi mic'ten geldi
  final DateTime detectedAt;
}

enum AudioSource {
  primary,    // Voice Translator: kulaklık mic; diğer modlarda tek source
  secondary,  // Voice Translator: telefon mic; diğer modlarda yok
}
```

#### 3.2.1 SingleMicAudioInput

- Mevcut `record` paketi + `VadController` (Silero) ile sarmalanır (Ders Modu)
- Bas Konuş için push-to-talk wrapper: buton state'i `start/stop`u kontrol eder, VAD bypass edilir (utterance boundary buton boundary)
- Tek `AudioRecord` instance, Android default routing

#### 3.2.2 DualMicAudioInput (yeni, native Kotlin plugin)

Flutter'ın `record` paketi tek `AudioRecord` instance açıyor. Yöntem B için iki paralel instance gerekli.

**Plan:**
- `hermes/android/.../HermesDualMicPlugin.kt` — MethodChannel (control) + iki EventChannel (audio streams)
- İki `AudioRecord` instance:
  - **Mic A:** `MediaRecorder.AudioSource.MIC` + `setPreferredDevice(BluetoothHeadsetMic | WiredHeadsetMic)`
  - **Mic B:** `MediaRecorder.AudioSource.MIC` + `setPreferredDevice(BuiltinMic)`
- Her instance PCM stream'ini ayrı EventChannel ile Dart tarafına gönderir
- Dart tarafında iki ayrı `VadController` örneği, her biri kendi stream'ini işler
- `AudioUtteranceEvent.source` = `primary` (A) veya `secondary` (B)

**Riskler:**
- Android API 29+ concurrent audio capture destekliyor ama MIUI optimize etmek için kapatmış olabilir
- AudioPolicy çakışması olabilir (Bluetooth + builtin aynı anda)
- iOS'ta AVAudioSession daha kısıtlı (Faz 2)

**Mitigasyon:** İlk cihaz testi (Step 6r-d) kritik kontrol noktası. Başarısızsa Voice Translator'ı Faz 2'ye ertelenir, Faz 1 Bas Konuş + Ders Modu ile devam eder.

### 3.3 VadController (mevcut, kullanım modu güncellendi)

- **Ders Modu:** kullanılır (sürekli dinleme, utterance otomatik tespit)
- **Voice Translator:** iki ayrı instance, her mic için ayrı pipeline
- **Bas Konuş:** KULLANILMAZ (buton state utterance boundary'yi belirler)

### 3.4 FillerCleaner (mevcut, aynı)

Üç modda da aynı şekilde transkript sonrası post-process. Settings'teki agresiflik toggle'ı global.

### 3.5 ConversationRepository (Drift schema v2)

**Yeni schema:**
```dart
sessions:
  id              INT PRIMARY KEY
  mode            TEXT   -- 'lecture' | 'voiceTranslator' | 'pushToTalk'
  quality         TEXT   -- 'fast' | 'full'
  sourceLang      TEXT
  targetLang      TEXT
  startedAt       DATETIME
  endedAt         DATETIME?
  title           TEXT?  -- Gemini'den veya timestamp'ten

messages:
  id              INT PRIMARY KEY
  sessionId       INT FK (cascade)
  speakerLang     TEXT
  sourceText      TEXT
  translatedText  TEXT?
  createdAt       DATETIME
```

**Migration v1 → v2:**
- `sessions` tablosuna `quality` ve `title` column'ları eklenir
- Eski `mode` değerleri güncellenir:
  - `'fast'` → `mode='voiceTranslator'`, `quality='fast'`
  - `'full'` → `mode='lecture'`, `quality='full'`
- Drift `MigrationStrategy.onUpgrade` ile yapılır
- Cihazdaki 2 test oturumu otomatik geçer

### 3.6 SessionMode + SessionQuality enum

```dart
enum SessionMode {
  lecture,          // Ders Modu
  voiceTranslator,  // Voice Translator (kulaklık zorunlu)
  pushToTalk;       // Bas Konuş Modu

  String get dbValue => name;

  static SessionMode fromDbValue(String v) => switch (v) {
    'lecture' || 'full' => SessionMode.lecture,
    'voiceTranslator' || 'fast' => SessionMode.voiceTranslator,
    'pushToTalk' => SessionMode.pushToTalk,
    _ => throw StateError('Unknown SessionMode dbValue: $v'),
  };
}

enum SessionQuality {
  fast,  // Whisper tiny
  full;  // Whisper small

  String get dbValue => name;

  static SessionQuality fromDbValue(String v) => switch (v) {
    'fast' => SessionQuality.fast,
    'full' => SessionQuality.full,
    _ => SessionQuality.fast, // varsayılan eski oturumlar için
  };
}
```

### 3.7 TitleGenerator (yeni)

```dart
abstract class TitleGenerator {
  Future<String> generate({
    required SessionMode mode,
    required List<Message> messages,
    required DateTime startedAt,
  });
}

class GeminiTitleGenerator implements TitleGenerator {
  // Internet varsa Gemini Flash API
  // Prompt: "Bu konuşmayı 3-5 kelimelik bir başlıkla özetle"
  // Örn çıktı: "yol tarifi", "kahve siparişi", "kütüphane saatleri"
}

class TimestampFallbackGenerator implements TitleGenerator {
  // Internet yoksa: "YYYY-MM-DD-HH-MM-SS tarihli {mod} konuşması"
  // Örn: "2026-05-30-14-32-18 tarihli voice translator konuşması"
}

class HybridTitleGenerator implements TitleGenerator {
  // Önce Gemini'yi dener, hata/timeout → timestamp fallback
}
```

`SessionEnd` event'inde çağrılır, başlık `sessions.title` column'una yazılır.

### 3.8 ConversationScreen (refactor + 3 ayrı UI)

Tek ekran yerine her mod için ayrı widget:
- `LectureScreen` — tek sütun chat
- `VoiceTranslatorScreen` — sol/sağ chat + play butonu
- `PushToTalkScreen` — üst/alt ahize + tam orta bas-konuş butonu

Ortak `MessageBubble` widget: küçük gri orijinal + büyük beyaz çeviri.

---

## 4. Veri Akışları

### 4.1 Voice Translator akışı

```
[Kulaklık mic] → [AudioRecord A] → [EventChannel A]
                                          ↓
                                    [VAD A] (Silero)
                                          ↓ utterance end
                                    [WavWriter]
                                          ↓
                                    [Whisper(lang=source)]
                                          ↓
                                    [FillerClean]
                                          ↓
                                    [Translate s→t]
                                          ↓
            ┌─────────────────────────────┴────────────┐
            ↓                                          ↓
   [Repository.insert(side=right)]      [Chat'e sağa ekle, play butonlu]


[Telefon mic] → [AudioRecord B] → [EventChannel B]
                                          ↓
                                    [VAD B] (Silero)
                                          ↓ utterance end
                                    [WavWriter]
                                          ↓
                                    [Whisper(lang=target)]
                                          ↓
                                    [FillerClean]
                                          ↓
                                    [Translate t→s]
                                          ↓
            ┌─────────────────────────────┴────────────┐
            ↓                                          ↓
   [Repository.insert(side=left)]       [Chat'e sola ekle]
                                                      ↓
                                            [TTS → kulaklık otomatik]
```

### 4.2 Bas Konuş Modu akışı

```
[Buton basılı] → [AudioRecord başlat]
[Buton bırakıldı] → [AudioRecord durdur, samples toplandı]
                          ↓
                    [WavWriter]
                          ↓
                    [Whisper(lang=hangi tarafsa)]
                          ↓
                    [FillerClean]
                          ↓
                    [Translate]
                          ↓
            ┌─────────────┴────────┐
            ↓                      ↓
   [Repository.insert]    [Chat'e ekle (alt veya üst)]
                                   ↓
                          [TTS → hoparlör otomatik]
```

### 4.3 Ders Modu akışı

```
[Dahili mic veya bağlı kulaklık mic] → [AudioRecord]
                                              ↓
                                        [VAD] (Silero)
                                              ↓ utterance end
                                        [WavWriter]
                                              ↓
                                        [Whisper(lang=lecture)]
                                              ↓
                                        [FillerClean]
                                              ↓
                                        [Translate lecture→user]
                                              ↓
                          ┌───────────────────┴────────┐
                          ↓                            ↓
                 [Repository.insert]       [Chat'e ekle, live subtitle]
                                                       ↓
                                          [TTS → kulaklık (opsiyonel)]
```

---

## 5. Riskler ve Mitigasyon

| Risk | Etki | Mitigasyon |
|---|---|---|
| **Dual mic concurrent capture** Android'de cihaza/MIUI'ye bağımlı | KRİTİK (Voice Translator için) | İlk cihaz testinde (Step 6r-d) doğrula. Başarısızsa Voice Translator Faz 2'ye ertelenir. Mehmet 2026-05-30: "POC öncesi yapma, sorun çıkarsa o zaman düşünürüz". |
| TTS feedback loop | YÜKSEK → ÇÖZÜLDÜ | Voice Translator: donanım ayrımı (TTS kulaklığa, mic telefonun). Bas Konuş: buton state guard. Ders Modu: kulaklık opsiyonel = varsa izolasyon. |
| Whisper kısa chunk'larda zayıf dil tespiti | YOK (eskiden vardı) | Diller explicit verildiği için yanlış dil tespiti riski tamamen ortadan kalktı. |
| Cafe/sokak gürültüsü VAD'i bozar | YÜKSEK | "Mikrofon Kalibrasyonu" Step 9'a. Silero VAD zaten gürültüye dayanıklı (2026-05-17 cihaz testi: uzaktaki başka konuşma misfire). |
| Voice Translator'da iki paralel pipeline RAM/pil | ORTA | Async queue, sırayla işle. Whisper instance paylaşılır (aynı motor, farklı language parametresi). |
| Ekran kapanırsa session duraklar (Faz 1) | ORTA | `wakelock_plus` ile session aktifken ekran açık. Foreground service Faz 2. |
| Bluetooth kulaklığın audio latency'si | ORTA (Voice Translator için) | Bluetooth kulaklıkta 100-200ms latency normal. Feedback loop'a etkisi yok ama UX'te karşı taraftan ses gecikmesi olabilir. Kullanıcı toleranslı (yüz yüze çeviri zaten gerçek zamanlı beklenmez). |
| Bas Konuş "kim konuşuyor" netliği | ÇÖZÜLDÜ | Ortada buton yok; her ekran yarısının tamamı kendi tarafının görünmez bas-konuş alanı. Hangi yarıya parmak değdiyse o taraf konuşur (doğal çözüm). |
| Tüm modlar portrait, Bas Konuş'ta üst yarı 180° döner | TASARIMDA NET | Landscape lock aktif. Bas Konuş'taki "ahize modu" benzetmesi içerik akışına dair, oryantasyona dair değil — telefon dik tutulur, üst yarının widget tree'si `RotatedBox(quarterTurns: 2)` ile döndürülür. |
| `DualMicAudioInput` iOS'ta çalışmaz | KABUL (Faz 1) | Faz 1 Android-only. iOS uyarlama Faz 2 — Mehmet'in iPhone'da demo öncesi değerlendirilir. |

---

## 6. Test Senaryoları

### Voice Translator
1. **Dual mic temel** — Kulaklığa "hello" + telefon mic'ine "hola" → sağa hello, sola hola, doğru hizalanma
2. **Concurrent capture** — A ve B aynı anda konuşur (overlap) → ikisi de yakalanır (kritik test, başarısızsa pivot)
3. **Feedback loop** — TTS karşı çeviriyi kulaklıkta oynarken kullanıcı konuşur → kullanıcı sesi sağa düşer, TTS sesi mic B'ye sızmaz
4. **Play butonu** — sağdaki play'e bas → telefon hoparlörü ES seslendirir
5. **Kulaklık yok uyarı** — Kulaklıksız başlat → "Kulaklık takın" uyarısı, mod başlamaz
6. **Kulaklık çıkarma runtime** — Aktif session sırasında kulaklık çıkarılır → ne olur? (Davranış: session paused + uyarı, kararı Step 6r-d'de netleştir)

### Bas Konuş Modu
1. **Alt yarı bas-konuş** — Alt yarıya parmakla basılı tut "merhaba" → bırak → üst yarıda ters "hola" + otomatik hoparlörden TTS
2. **Üst yarı bas-konuş** — Üst yarıya basılı tut → kayıt alınır, alt yarıya çeviri yazılır + TTS
3. **State guard** — Bir yarı kayıt alıyorken karşı yarı disabled; TTS oynarken her iki yarı disabled
4. **Üst-alt yön doğru** — Ters yazı gerçekten karşı taraftan okunabilir (cihazda yatay tutarak doğrula)
5. **Çoklu parmak** — İki yarıya aynı anda basılırsa ilk basan kazanır, ikincisi yok sayılır (basit FIFO)

### Ders Modu
1. **Live subtitle** — Hoca konuşur → chat'e canlı ekleme, latency <3sn hedef
2. **Kulaklık opsiyonel** — Kulaklıksız sadece görsel + Kulaklıklı + sesli çeviri
3. **Uzun session** — 30 dakika, transkript SQLite'ta tüm mesajlar, başlık otomatik

### Ortak
1. **Schema migration** — Eski v1 'fast'/'full' oturumları v2'ye doğru map'lendi
2. **Offline başlık fallback** — Internet kapalı → timestamp formatlı başlık
3. **Online başlık** — Gemini'den anlamlı başlık üretilir
4. **Kalıcılık** — App kill + reopen → tüm oturumlar + başlıklar yerinde

---

## 7. İmplementasyon Sırası (Step 6 refactor sub-adımları)

Her adımdan sonra: `flutter analyze` → temiz + (relevant ise) USB cihaz testi.

| Sub-step | İçerik | Test |
|---|---|---|
| **6r-a** | `ConversationSessionManager` constructor'dan `LanguageDetector` parametresi çıkar; ilgili testleri güncelle (LangID akışına ait olanlar disable/sil) | `flutter test` mevcut suite hâlâ geçer (LangID'siz) |
| **6r-b** | `SessionMode` (3) + `SessionQuality` (2) enum'ları; Drift schema v2 migration (`quality` + `title` column'ları, eski değer mapping) | Migration unit testi: eski 'fast'/'full' → yeni doğru map'lendi |
| **6r-c** | `AudioInput` strategy abstract + `SingleMicAudioInput` (mevcut `record`+`vad` sarmalı) | Unit test: 5 utterance simüle et, doğru event dispatch |
| **6r-d** | `DualMicAudioInput` native Kotlin plugin (HermesDualMicPlugin.kt) | **CİHAZ TESTİ KRİTİK**: Poco X3 Pro'da iki paralel mic gerçekten çalışıyor mu — başarısızsa Mehmet pivot kararı verir |
| **6r-e** | `ConversationSessionManager` 3 mod + 2 quality destekleyecek refactor | Unit test: her kombinasyon için fake `AudioInput` ile pipeline doğru çalışır |
| **6r-f** | `TitleGenerator` (Gemini + timestamp fallback hybrid) | Unit test: internet yok → fallback tetiklenir |
| **6r-g** | DB Test ekranını yeni schema'ya hizala (varolan ekran kırılmasın) | Cihaz: mevcut oturumlar görünür, yeni oturumlar yeni schema |
| **6r-h** | Step 6 entegrasyon cihaz testi | Cihazda Ders + Bas Konuş + Voice Translator gerçek test |

**Sub-step 6r-d KRİTİK kontrol noktası.** Sonuca göre Step 7+ planı değişebilir.

Sonra Step 7+ UI'ları sırayla:
- Step 7 — `LectureScreen` + cihaz testi
- Step 8 — `VoiceTranslatorScreen` + `PushToTalkScreen` + ana ekran 3 mod kart navigasyonu
- Step 9 — Polish (LangID re-enable polish, kalibrasyon, wakelock, başlık Gemini)

---

## 8. Onaylanmış Kararlar (final, 2026-05-30)

**a) Mod sayısı:** 3 mod (Ders + Voice Translator + Bas Konuş) + bağımsız Manuel Çeviri (`TranslationTestScreen` modlardan ayrı ana ekranda)

**b) Voice Translator audio mimarisi:** Yöntem B — kulaklık+telefon çift mic eş zamanlı dinleme. Native Kotlin plugin. MIUI risk kabul edildi, POC öncesi yapılmıyor.

**c) Mode + Quality:** İki ayrı enum/column. `SessionMode (3) × SessionQuality (fast/full)` = 6 kombinasyon, hepsi anlamlı.

**d) Language ID:** Kod ve paket **korunuyor** ama Step 6 refactor sonrası ana akıştan koparılıyor. Step 9 polish'de iki kullanım için bekliyor:
1. Yanlış dil uyarısı (kullanıcı seçilen dilden farklı konuşursa)
2. Hibrit ders modu (TR/EN karışık ders gibi)

**e) Transkript persistence:** Her 3 modda transkript Drift'e yazılır. **Ses kaydı YOK.** Başlık otomatik (internet varsa Gemini, yoksa timestamp).

**f) Geliştirme cihazı:** Poco X3 Pro (Android). iPhone Faz 1 demo cihazı, Faz 1 boyunca iOS testine girilmez.

**g) FillerCleaner:** Mevcut implementasyon aynen kullanılır.

**h) Background:** Faz 1 wakelock_plus, foreground service Faz 2.

**i) VAD:** Silero v4 (mevcut). Ders Modu + Voice Translator'da kullanılır, Bas Konuş'ta kullanılmaz (buton state utterance boundary).

---

## 9. Kapsam Dışı (Faz 2/3)

- Konuşmacı diarization (3+ kişi aynı tarafta)
- Real-time partial transcript (Whisper streaming)
- Sesli komut session başlatma ("Hey Hermes")
- Belge Modu (kamera OCR)
- Coqui TTS (daha doğal ses)
- SeamlessM4T (ses→ses tek model)
- iOS foreground/background audio
- Çeviri belleği cache
- Voice Translator iOS desteği (Faz 2'de değerlendirilir)

---

## Tarihsel Not

Bu doküman 2026-05-17 versiyonunun yerine geçer. Eski mimari (tek mod, sürekli VAD + auto dil tespit + side detection + `SessionMode.fast/full`) 2026-05-17 akşamı Mehmet'in donanım ayrımı pivotuyla terk edildi; pivot kararı 2026-05-30'da netleşti (3 mod + Yöntem B + 2D enum).

Eski tasarımı görmek için:
```
git log --all --oneline -- HERMES_KONUSMA_MODU_TASARIM.md
git show <commit>:HERMES_KONUSMA_MODU_TASARIM.md
```
