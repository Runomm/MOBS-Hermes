# Hermes — Konuşma Modu (Sürekli Çift Yönlü) Tasarım

**Statü:** Kararlar onaylandı (2026-05-17). Implementasyon Step 1'den başlayabilir.
**Yazıldığı tarih:** 2026-05-17
**Bağlam:** ML Kit translate + Whisper STT cihazda test edildi, çalışıyor. TTS henüz yok. Bu doküman, Mehmet'in *"Google Translate'ten ayıran asıl özellik"* dediği sürekli çift yönlü konuşma modunu tarifler.

---

## 1. Vizyon (1 cümle)

İki kişi normal tempoda farklı dillerde konuştukça, app session boyunca VAD ile her sözceyi otomatik yakalayıp, dilini tespit edip karşı dile çevirir; chat akışına dökerken karşıya TTS ile sesli verir, "ee/şey/uhh" gibi filler'leri post-process'te ayıklar.

## 2. Kullanıcı Akışı

1. Ana ekran → **Yeni Konuşma** → dil çifti seçimi (örn. TR ↔ ES)
2. Konuşma ekranı açılır, ortada büyük **▶ Başlat**
3. Başlat → mikrofon sürekli açık → VAD sessizliği takip eder
4. Sözce biter (≥800ms sessizlik) → chunk Whisper'a → text + dil
5. Algılanan dile göre **kaynak veya hedef** taraf seçilir, çeviri yapılır, chat'e iki tarafta da eklenir, TTS karşı dilden oynar
6. **⏸ Duraklat** → mikrofon kapanır, state yaşar / **■ Bitir** → SQLite flush + özet ekranı

## 3. Mimari Bileşenler

### 3.1 ConversationSessionManager *(yeni)*

State machine + lifecycle, tüm zinciri yönetir.

**States:** `idle` → `listening` → `transcribing` → `paused` → `ending`

**Events:** `start()`, `pause()`, `resume()`, `end()`, internal `_onUtteranceDetected(audio)`, `_onTranscriptReady(text, lang)`

**Mod parametresi (constructor'da verilir):**
```dart
enum SessionMode {
  fast,   // "Hızlı Mod" / "Konuşma Modu" / "Turist Modu" (label TBD)
          // - Whisper tiny
          // - TTS çakışmada: kes
          // - Diyalog temposu, hız öncelik
  full,   // "Tam Mod" / "Ders Modu" (label TBD)
          // - Whisper small (varsa)
          // - TTS çakışmada: kuyrukta bekle, sırayla oynat
          // - Doğruluk öncelik, eksiksiz çeviri
}
```

UI'daki mod isimleri (Hızlı/Tam veya Konuşma/Ders veya Turist/Akademik) **subject to change**, kod tarafında enum yeterli. Settings ekranında label rename'i her zaman mümkün.

Bağladığı şeyler: `AudioStreamSource`, `VadController`, `SttEngine`, `TranslationEngine`, `TtsEngine`, `FillerCleaner`, `ConversationRepository`.

### 3.2 VadController *(yeni)*

**Karar (a):** `vad_silero` paketi kullanılacak. Silero VAD ONNX modeli (~2MB), Flutter wrapper var, gürültüye dayanıklı insan-konuşması sınıflandırması. RMS eşik yolu (eski opsiyon B) elendi — Erasmus/turist senaryolarında kafe/sokak gürültüsü gerçek bir risk.

**Parametreler (Silero output frame'lerinde):**
- `voiceProbThreshold = 0.5` (Silero 0..1 verir; 0.5 üstü = konuşma)
- `minUtteranceMs = 500` (öksürük/nefes yutulur)
- `endSilenceMs = 800` (bu kadar sessiz frame = sözce bitti)
- `maxUtteranceMs = 30000` (monolog zorla kesilir)

**Asset:** Silero ONNX modeli APK içine asset olarak gömülür (tıpkı whisper tiny gibi), runtime'da indirme yok.

### 3.3 FillerCleaner *(yeni, saf Dart)*

İki katmanlı post-processing.

**Katman 1 — Default (Faz 1):** Rule-based regex pipeline, tamamen offline, saf Dart, sıfır API maliyeti.

İki agresiflik seviyesi (Settings'te toggle):

```
CONSERVATIVE (default — sadece bariz dolgu sesleri):
  TR: \bee+\b, \bmmm+\b, \baaa+\b, \buhh\b
  EN: \bum+\b, \buh+\b, \bumm+\b, \bmmm+\b
  Genel: \s{2,}→' ', trim, cümle başı büyük harf

AGGRESSIVE (kullanıcı toggle açarsa — söz kalıpları dahil):
  Yukarıdakilere ek:
  TR: \byani\b, \bişte\b, \bhani\b, \bfalan\b, \bşey\b
  EN: \byou know\b, \bi mean\b, ^like\s, \bkinda\b, \bsorta\b
```

Ayrıca **Filler temizleme master toggle**: Kullanıcı tüm post-processing'i komple kapatabilir (raw Whisper transkripti görmek için).

**Katman 2 — Opsiyonel, Faz 2 (online cleanup):** Gemini Flash API'ye prompt: *"Bu transkripti akıcı bir Türkçe metne dönüştür, anlamı koruyarak filler'ları temizle ve yarım cümleleri tamamla."*

Faz 2'de eklenecek, Settings'te ayrı toggle: "Online dil cilalama (internet gerekli)". Default kapalı. Offline-first ilkesini bozmaz, sadece ekstra cilalama.

### 3.4 ConversationRepository *(yeni, Drift)*

```sql
sessions(id, source_lang, target_lang, started_at, ended_at, duration_seconds, message_count)
messages(id, session_id, sender_lang, original_text, translated_text, audio_path?, created_at)
```

Ders Modu'ndaki batch-flush burada YOK — Konuşma Modu real-time, her mesaj direkt insert.

### 3.5 ConversationScreen *(yeni)*

```
┌─────────────────────────────────────────┐
│ ← Konuşma    TR ⇄ ES    ⏸  ■            │  ← üst bar
├─────────────────────────────────────────┤
│                                         │
│              ┌──────────────────┐       │
│              │ Hola, ¿qué tal?  │       │  ← ES (sol, gri)
│              │ ─────────────    │       │
│              │ Merhaba, nasıl?  │       │
│              │ 14:32            │       │
│              └──────────────────┘       │
│                                         │
│       ┌──────────────────────────┐      │
│       │ İyiyim, sen nasılsın?    │      │  ← TR (sağ, mor)
│       │ ─────────────────        │      │
│       │ Estoy bien, ¿y tú?       │      │
│       │ 14:33                    │      │
│       └──────────────────────────┘      │
│                                         │
├─────────────────────────────────────────┤
│ ●●●●●●●●  Dinleniyor: TR algılandı      │  ← waveform + status
└─────────────────────────────────────────┘
```

- Chat list reverse'lü, otomatik scroll
- Long-press mesaj → TTS yeniden oynat
- Waveform: record paketinin amplitude stream'inden basit bar visualizer

## 4. Veri Akışı (sequence)

```
[Mikrofon stream PCM 16kHz mono]
        ↓
[VadController] ─── RMS eşik
        ↓ utterance_end event
[Buffer → WAV dosyası]
        ↓
[Whisper tiny, language='auto']
        ↓ {text, detected_lang}
[FillerCleaner]
        ↓ {clean_text, detected_lang}
        ↓
   ┌────┴────────────────────────────┐
   │ if detected_lang == source_lang │
   │   translation = MLKit(s→t)       │
   │   chat.addRight(text, translation) │
   │   TTS.speak(translation, target) │
   │ elif detected_lang == target_lang│
   │   translation = MLKit(t→s)       │
   │   chat.addLeft(text, translation)│
   │   TTS.speak(translation, source) │
   │ else: log warning, skip          │
   └─────────┬───────────────────────┘
             ↓
[ConversationRepository.insertMessage()]
```

## 5. Riskler ve Mitigasyon

| Risk | Etki | Mitigasyon |
|---|---|---|
| TTS sesini mikrofon duyup VAD tetikler (feedback loop) | **KRİTİK** | TTS aktifken VAD bypass: `if (_tts.isSpeaking) skipChunk()` |
| Whisper tiny dil tespiti zayıf, kısa chunk'larda yanlış dil | YÜKSEK | Confidence eşiği (örn. 0.6); altındaysa **sessizce drop** — UI'da hiçbir şey gösterme, log warning yaz. Kullanıcı response olmadığını görüp doğal olarak tekrar/daha yüksek söyler ("silence as implicit feedback") |
| Aynı dilden iki konuşmacı | ORTA | Şu an unsupported, sessizce sağa eklemeye devam |
| Kafe/sokak gürültüsü VAD'i bozar | YÜKSEK | "Mikrofon Kalibrasyonu" dialog: 3 sn sessizlik dinle → noise floor + 12dB offset |
| 30dk session'da RAM/pil | ORTA | Chunk'lar diske yazılıp Whisper'a path verilir, RAM'de tutulmaz |
| Whisper işlerken yeni utterance gelir | YÜKSEK | Async queue, sırayla işle. UI: "X mesaj işleniyor…" badge |
| Ekran kapanırsa session duraklar (Faz 1) | ORTA | `wakelock_plus` ile session aktifken ekran açık tutulur. Foreground service Faz 2'de gelecek. |

## 6. Test Senaryoları (cihaz testleri için referans)

1. **TR monolog** — 5 cümle, hepsi sağda, ES çevirileri olmalı
2. **TR→ES sıralı diyalog** — taraflar doğru hizalanmalı
3. **Filler temizleme** — "Eee, şey, yani bugün ne yapacağız?" → "Bugün ne yapacağız?"
4. **TTS-mikrofon feedback** — TTS oynarken konuşmaya başla, mikrofon dinlememeli; status: "📢 Cihaz konuşuyor"
5. **Offline** — internet kapalıyken full akış çalışmalı
6. **Uzun session** — 30 dakika, SQLite'ta tüm mesajlar olmalı, özet ekranı açılmalı
7. **Yabancı dil** — Almanca cümle söyle, sessizce skip, log warning

## 7. İmplementasyon Sırası

Her adımdan sonra: `flutter analyze` → temiz + USB cihaz testi → sonra bir sonraki.

| Step | İçerik | Yeni paketler / asset | Test |
|---|---|---|---|
| 1 | TtsEngine + Native flutter_tts | `flutter_tts` | Test ekranında çeviriyi sesli oynat |
| 2 | Dil paketi indirme UI (**Özellik 1**) | — | İndirilmiş/indirilmemiş dropdown renkleri, confirm dialog |
| 3 | VadController (Silero) | `vad_silero` (veya benzeri Flutter wrapper) + Silero ONNX asseti | Headless: 5 cümle konuş, terminal'de doğru utterance count, gürültü filtresi |
| 4 | FillerCleaner (saf Dart, conservative + aggressive) | — | Unit test: 10+ örnek string, iki seviye |
| 5 | Drift schema + ConversationRepository | `drift`, `drift_flutter`, `sqlite3_flutter_libs` | Insert/query smoke test |
| 6 | ConversationSessionManager (zincir, mode parametreli) | — | Cihazda debug ekran, konsola mesaj akışı; her iki mode test edilir |
| 7 | ConversationScreen UI + mode toggle + filler toggle'ları | — | Cihazda 3 dk konuş, görsel doğruluk |
| 8 | Ana ekran navigation + mod seçimi | — | Senaryo 1, 2 baştan sona |
| 9 | Polish: TTS-mikrofon feedback guard, confidence drop, Wakelock (ekran açık tut) | `wakelock_plus` | Senaryo 4, 5; ekran açıkken session 10dk |

**Wakelock notu:** Faz 1'de foreground service kurmuyoruz (Karar e); onun yerine session aktifken `wakelock_plus.enable()` ile ekranı açık tutarız. Cihaz cebe konmadıkça çalışır.

## 8. Onaylanmış Kararlar (2026-05-17)

**a) VAD opsiyonu:** ✅ `vad_silero` kullanılacak. ~2MB ONNX modeli APK'ya gömülür. Gürültüye dayanıklı insan-konuşması tespiti. (Eski opsiyon B / RMS eşik elendi.)

**b) TTS çakışma davranışı:** ✅ Mode-bazlı default:
- **Hızlı Mod (Konuşma/Turist):** Yeni utterance TTS oynarken gelirse → **kes**, yeniyi seslendir. Doğal diyalog temposu.
- **Tam Mod (Ders/Akademik):** Yeni utterance gelirse → **kuyrukta bekle**, sırayla oynat. Eksiksiz çeviri öncelik.
- Mod isimleri (Hızlı/Tam vs Konuşma/Ders vs Turist/Akademik) **subject to change**. Kod'da enum `SessionMode.fast`/`SessionMode.full`.

**c) Aynı dil üst üste:** ✅ Sessizce devam, iki ayrı mesaj olarak ilgili tarafa ekle. Warning yok.

**d) Filler cleaning:**
- Default: **conservative** (sadece "ee", "uhh", "umm" gibi bariz dolgu sesleri)
- Settings toggle: **aggressive**'e geçilebilir (yani/işte/hani/şey, you know/i mean dahil)
- Settings toggle: filler temizleme **komple kapatılabilir** (raw transkript görmek için)
- Post-processing motor sorusu: **Faz 1'de saf Dart rule-based regex** (offline, LLM yok). Gemini Flash ile online cleanup Faz 2'ye eklenecek opsiyonel cilalama, default kapalı.

**e) Background çalışma:**
- **Faz 1: KURULMAYACAK.** Yerine `wakelock_plus` ile session aktifken ekran kapanmaz, app foreground'da kalır.
- **Faz 2: Android foreground service eklenecek** (NotificationChannel + Kotlin service kod). Telefonu cebe atıp konuşmaya devam etmek mümkün olur.
- **Faz 2: iOS background audio** değerlendirilecek. `UIBackgroundModes → audio` capability ile mümkün ama Apple review riskli; prototip + kullanım gerekçesi App Store başvurusunda açıklanmalı.

**f) Dil tespit belirsizliği:** ✅ Confidence eşiği altında **sessizce drop**, UI'da hiçbir şey gösterme. Kullanıcı response olmadığını görüp doğal olarak daha yüksek/uzun konuşur. "Silence as implicit feedback" — daha az gürültülü UX, kullanıcıyı eğitir. Eşik değeri cihaz testinde kalibre edilecek (ilk tahmin: 0.6).

---

## Kapsam Dışı (Faz 2'ye ertelenmiş)

- Sesli komut session başlatma ("Hey Hermes, başla")
- Konuşmacı diarization (3+ kişi)
- Senkron canlı altyazı (real-time partial transcript) — bu Whisper streaming gerektirir, tiny modelinde maliyetli
- Çeviri belleği (sık tekrarlayan ifadeler için cache)
- PDF/markdown export (session özet ekranında yapılır, ama bu aşama Faz 1'in geri kalanı)
