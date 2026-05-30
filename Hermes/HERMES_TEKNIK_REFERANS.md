# Hermes — Teknik Referans Dokümanı
*Kodlama aşamasında kullanılacak mimari rehber*

---

## 1. Proje Özeti

| | |
|---|---|
| **Uygulama Adı** | Hermes |
| **Vizyon** | Çevrimdışı çalışan, Erasmus öğrencileri ve turistler için akıllı çeviri + not asistanı |
| **Platform** | Flutter — iOS + Android |
| **Primary test cihazı** | Poco X3 Pro (Android / Snapdragon 860) |
| **Demo cihazı** | iPhone 17 Pro Max (iOS build: Codemagic veya üniversite Mac lab) |
| **Backend** | Yok — tüm core işlem cihazda |

---

## 2. Mimari Desen: Strategy Pattern

Her motor (STT, Çeviri, TTS) bu interface'i implement eder:

```dart
// STT
abstract class SttEngine {
  Future<String> transcribe(Uint8List audioChunk, String sourceLanguage);
  String get name;
}

// Çeviri
abstract class TranslationEngine {
  Future<String> translate(String text, String from, String to);
  Future<void> ensureModelLoaded(String from, String to);
  bool get isOfflineCapable;
  String get name;
}

// TTS
abstract class TtsEngine {
  Future<void> speak(String text, String language);
  String get name;
}

// Servis katmanı — motor değişimi tek satır
class TranslationService {
  TranslationEngine _engine;
  void switchEngine(TranslationEngine e) => _engine = e;
  Future<String> translate(String text, String from, String to) =>
      _engine.translate(text, from, to);
}
```

**Mevcut implementasyonlar:**

| Interface | Mevcut | Faz 2 alternatifi |
|---|---|---|
| SttEngine | WhisperCppEngine (tiny/small) | SeamlessM4TEngine |
| TranslationEngine | GoogleMLKitEngine | ArgosEngine, OpusMTEngine |
| TtsEngine | NativeOsTtsEngine | CoquiTtsEngine |

---

## 3. Teknoloji Kararları

### STT: whisper.cpp
- **Flutter paketi:** `whisper_flutter_new` veya `flutter_whisper_kit` (iOS)
- **Modeller:**
  - `ggml-tiny.bin` → ~75MB → Snapdragon 860'ta ~1-2s/5sn ses
  - `ggml-small.bin` → ~250MB → Snapdragon 860'ta ~5-8s/5sn ses (demo için iPhone)
- **Kullanıcı seçimi:** Settings ekranında toggle — "⚡ Hızlı" / "🎯 Doğru"
- **Ders Modu varsayılanı:** small (doğruluk)
- **Konuşma Modu varsayılanı:** tiny (hız)

### Çeviri: Google ML Kit Translation
- **Flutter paketi:** `google_mlkit_translation`
- **Dil modeli boyutu:** ~30MB / dil
- **Offline:** Evet, ilk indirmeden sonra tamamen offline
- **Ücret:** Ücretsiz, limit yok
- **Lisans:** Proprietary (Google) — Strategy Pattern sayesinde değiştirilebilir

```dart
class GoogleMLKitEngine implements TranslationEngine {
  final translator = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.spanish,
    targetLanguage: TranslateLanguage.turkish,
  );

  @override
  Future<String> translate(String text, String from, String to) async {
    return await translator.translateText(text);
  }

  @override
  bool get isOfflineCapable => true;
}
```

### TTS: Native OS
- **Flutter paketi:** `flutter_tts`
- **iOS:** AVSpeechSynthesizer
- **Android:** TextToSpeech API
- **Offline:** Evet, built-in
- **Faz 2 upgrade:** Coqui TTS (daha doğal ses, açık kaynak)

### LLM Özet: Gemini Flash API
- **Model:** `gemini-1.5-flash` (hızlı, ucuz)
- **Ücretsiz katman:** 15 RPM, 1 milyon token/gün — proje için fazlasıyla yeterli
- **Fallback:** Internet yoksa UI'da "Özet için bağlantı gerekiyor" mesajı
- **Prompt örneği:**
  ```
  Aşağıdaki ders transkriptini Türkçe olarak analiz et:
  1. 3 cümlelik özet
  2. Ana konular (madde madde)
  3. Verilen ödevler ve tarihler
  4. Yeni kelimeler ve Türkçe karşılıkları

  Transkript: {transcript}
  ```
- **Değiştirilebilirlik:** Ücretli hale gelirse Claude API veya local Ollama ile swap

### Veritabanı: SQLite
- **Flutter paketi:** `drift` (type-safe SQLite ORM)
- **Yazma stratejisi:** Transaction batch — her chunk'ta değil, her 6 chunk'ta (≈30 saniye) tek bir transaction ile yazılır.
  - Crash kaybı: maksimum 30 saniye
  - Performans: 6x daha az fsync
  - Session bitince `_flushToDb()` çağrılarak pending buffer boşaltılır

```dart
List<TranscriptEntry> _pending = [];

void onChunkReady(TranscriptEntry entry) {
  _pending.add(entry);
  if (_pending.length >= 6) _flushToDb();
}

Future<void> _flushToDb() async {
  final batch = List.from(_pending);
  _pending.clear();
  await db.transaction(() async {
    for (final entry in batch) {
      await db.into(transcripts).insert(entry);
    }
  });
}

Future<void> endSession() async {
  if (_pending.isNotEmpty) await _flushToDb();
}
```

- **Tablo yapısı:**
  ```
  sessions:    id, mode, source_lang, target_lang, started_at, duration_seconds
  transcripts: id, session_id, original_text, translated_text, timestamp
  words:       id, session_id, original, translation, source_lang, target_lang
  ```

---

## 4. Mod Sistemi

### Ders Modu
- Tek yönlü (profesör → öğrenci)
- Sürekli mikrofon dinleme, VAD (Voice Activity Detection) ile sessizlikte duraklama
- 5 saniyelik chunk'lar halinde işleme
- Whisper **small** varsayılan (doğruluk öncelikli)
- Transkript ekranda aşağı kaydırılarak akar

### Konuşma Modu
- Çift yönlü, sıra tabanlı
- Her konuşma sonunda mikrofon karşı tarafa geçer (UI'da gösterilir)
- Whisper **tiny** varsayılan (hız öncelikli)
- Ekran iki panele bölünür (üst: Kişi A, alt: Kişi B)

### Belge Modu *(Faz 2)*
- Kamera ile metin çevirisi
- Vision model + OCR pipeline
- Not: GeoEngine'den türetilebilecek potansiyel modül

---

## 5. UI Tasarım Sistemi

```
Tema: Dark (varsayılan)
  Background:  #0F0F0F
  Surface:     #1A1A1A
  Border:      #2A2A2A
  Accent:      #7C6FE0  (soft mor)
  Text-primary: #F0F0F0
  Text-secondary: #A0A0A0

Tipografi:
  Font: Inter (Google Fonts paketi)
  H1: 24sp / Medium
  H2: 18sp / Medium
  Body: 15sp / Regular / line-height 1.6
  Caption: 12sp / Regular

Bileşen kuralları:
  Kart radius: 12px
  Kart border: 1px solid #2A2A2A (gölge değil çizgi)
  Buton radius: 100px (pill shape)
  Animasyon: 250ms ease-out (bounce yok)
  İkon: Lucide Icons (temiz, minimal)
```

---

## 6. Proje Klasör Yapısı (Flutter)

```
hermes/
├── lib/
│   ├── core/
│   │   ├── engines/
│   │   │   ├── stt/
│   │   │   │   ├── stt_engine.dart          # Abstract interface
│   │   │   │   └── whisper_cpp_engine.dart  # Implementation
│   │   │   ├── translation/
│   │   │   │   ├── translation_engine.dart  # Abstract interface
│   │   │   │   └── google_mlkit_engine.dart # Implementation
│   │   │   └── tts/
│   │   │       ├── tts_engine.dart          # Abstract interface
│   │   │       └── native_tts_engine.dart   # Implementation
│   │   ├── services/
│   │   │   ├── session_manager.dart
│   │   │   └── summary_client.dart          # Gemini API
│   │   └── database/
│   │       └── app_database.dart            # Drift / SQLite
│   ├── features/
│   │   ├── home/                            # Ana Ekran
│   │   ├── active_session/                  # Aktif Çeviri
│   │   └── session_detail/                  # Oturum Özeti
│   └── main.dart
├── assets/
│   └── models/
│       ├── ggml-tiny.bin                    # Whisper tiny
│       └── ggml-small.bin                   # Whisper small
└── pubspec.yaml
```

---

## 7. Faz Planı

| Faz | Kapsam |
|---|---|
| **Faz 1 (Mevcut)** | Ders Modu + Konuşma Modu + Özet + PDF export |
| **Faz 2** | Belge Modu (kamera OCR), offline harita tile cache, Coqui TTS |
| **Faz 3** | SeamlessM4T (ses→ses direkt), GeoEngine Belge Modu entegrasyonu |

---

## 8. Performans Referansları

| Model | Cihaz | 5sn ses için işlem süresi | Kabul edilebilir mi? |
|---|---|---|---|
| Whisper tiny | Poco X3 Pro | ~1-2s | ✓ Ders modu |
| Whisper small | Poco X3 Pro | ~5-8s | ✗ Çok yavaş |
| Whisper tiny | iPhone 17 Pro Max | ~0.3s | ✓ Mükemmel |
| Whisper small | iPhone 17 Pro Max | ~0.8s | ✓ Mükemmel |
| ML Kit çeviri | Her ikisi | ~0.1-0.3s | ✓ |
| Native TTS | Her ikisi | Anlık | ✓ |
