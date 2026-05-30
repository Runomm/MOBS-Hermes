# 02 — Proje Durumu (2026-05-17 itibarıyla)

## Tek satırlık özet

Faz 1'in **4/9 step'i tamam**, **Step 5 (Drift/SQLite + ConversationRepository) sıradaki iş**. Tüm cihaz testleri Poco X3 Pro'da başarılı. `flutter analyze` clean, FillerCleaner için 16/16 unit test yeşil.

## Tamamlanmış olanlar

| # | Step | Ne yapıldı | Cihaz testi |
|---|---|---|---|
| Faz 0 | Proje iskeleti | Flutter app, Material 3 dark tema, brand renkleri | — |
| Faz 0 | TranslationEngine interface | Strategy abstract sınıf | — |
| Faz 0 | GoogleMLKitEngine | `google_mlkit_translation` ile offline çeviri | ✅ Cihazda doğrulandı |
| Faz 0 | SttEngine interface | Strategy abstract | — |
| Faz 0 | WhisperCppEngine | `whisper_ggml`, tiny modeli `assets/models/ggml-tiny.bin` | ✅ Cihazda doğrulandı |
| Faz 0 | Mikrofon + transkript akışı | `record` paketi, otomatik ML Kit zinciri | ✅ Cihazda doğrulandı |
| Faz 0 | NDK 29 pin + record 6.x | NDK 29.0.13113456, record 5→6 uyumsuzluk fix | — |
| Faz 0 | Konuşma Modu tasarım dokümanı | 6 açık soru → karara bağlandı | — |
| **1** | **TtsEngine + flutter_tts** | Native OS TTS, BCP-47 locale, auto-speak toggle, manuel Seslendir/Stop | ✅ 6 senaryo geçti |
| **2** | **Dil paketi indirme UI** | Dropdown ✓/⬇ ayrımı, confirm dialog, indirme akışı, overflow fix | ✅ Cihazda doğrulandı |
| **2-fix** | **Dropdown baseline assertion** | `selectedItemBuilder` ile inline gösterim sadeleştirildi | ✅ Cihazda doğrulandı |
| **3** | **VadController (Silero v4)** | `vad: ^0.0.7+1`, ONNX modeli APK asset (1.8MB), MODIFY_AUDIO_SETTINGS izni, standalone VAD Test ekranı | ✅ 5/5 cümle, misfire mantığı doğru |
| **4** | **FillerCleaner** | Saf Dart, conservative/aggressive/off, TR + EN + jenerik, **16/16 unit test geçti** | — (saf Dart, cihaz testi gerekmedi) |

## Sıradaki tek satırlık iş

**Step 5 — Drift schema + `ConversationRepository`** (Konuşma Modu veritabanı katmanı)

### Detaylı talimatlar (kopyala-yapıştır şeklinde uygulanabilir)

1. **Paketleri ekle** (`hermes/pubspec.yaml`):
   ```yaml
   dependencies:
     drift: ^2.x
     sqlite3_flutter_libs: ^0.5.x
     path: ^1.9.x
   dev_dependencies:
     drift_dev: ^2.x
     build_runner: ^2.x
   ```
   Versiyonları doğrulamak için `flutter pub upgrade --major-versions` çalıştırıp uyumlu olanı seç.

2. **Drift schema yaz**: `lib/core/database/app_database.dart`
   - Tablolar (HERMES_KONUSMA_MODU_TASARIM.md Bölüm 3.4'ten):
     ```
     sessions: id, source_lang, target_lang, started_at, ended_at,
               duration_seconds, message_count
     messages: id, session_id, sender_lang, original_text, translated_text,
               audio_path (nullable), created_at
     ```
   - Foreign key: messages.session_id → sessions.id

3. **Codegen çalıştır**:
   ```powershell
   Push-Location "C:\Projects\FonksiyonelProgramlama\Hermes\hermes"
   dart run build_runner build --delete-conflicting-outputs
   Pop-Location
   ```
   Çıktı: `app_database.g.dart`.

4. **Repository yaz**: `lib/core/repositories/conversation_repository.dart`
   - `createSession({source, target}) → int sessionId`
   - `insertMessage({sessionId, senderLang, original, translated, audioPath?})`
   - `getMessages(sessionId) → Stream<List<Message>>` (canlı güncellenir)
   - `endSession(sessionId)` → ended_at + duration hesabı
   - **Faz 1'de batch flush YOK** — real-time chat akışı, her message direkt insert

5. **Smoke test yaz**: `test/core/repositories/conversation_repository_test.dart`
   - In-memory `NativeDatabase.memory()` ile
   - 1 session + 3 message insert → query → 3 message sırayla gelir
   - `endSession` → duration > 0

6. **Doğrulama**:
   ```powershell
   Push-Location "C:\Projects\FonksiyonelProgramlama\Hermes\hermes"
   flutter test test/core/repositories/conversation_repository_test.dart
   flutter analyze
   Pop-Location
   ```

7. **Roadmap güncelle**: `HERMES_ROADMAP.md` Step 5'i tikle, "Aktif İş"i Step 6'ya geçir.

8. **Step 6 (ConversationSessionManager)**'a başlamadan önce Mehmet'e onay sor — bu adım VAD + STT + Translate + TTS + Repository'i birleştirir, scope büyük.

### Cihaz testi gerekli mi?

**Step 5 için gerekli DEĞİL** — saf data katmanı, UI yok, unit test yeterli. Ama Mehmet'in step-by-step kuralının istisnası olarak görmemen lazım: Step 6 (Manager) cihaz testi gerektirir, çünkü real-time UI etkileşimi başlar.

## Bilinen riskler / borçlar

- **NDK r29-beta1**: `whisper_ggml` strict istedi, beta. Stable r29 çıkarsa upgrade. Production release öncesi konu.
- **13 paket outdated**: `permission_handler`, `record`, `google_fonts` major bump var. Faz 2'de toplu upgrade.
- **TTS feedback loop**: Mikrofon TTS'in sesini duyup VAD tetikleyebilir. Step 9 polish'inde guard kodu (`if (tts.isSpeaking) vad.skip`).
- **Whisper small modeli**: Faz 1'de seçilemiyor, tiny varsayılan. Settings'te toggle Step 7+.
- **Robotic TTS**: Native TTS robotic geliyor — sistem ayarından "Google TTS" engine'i seçilirse iyileşir, kullanıcıya yönlendirme Step 9'da. Coqui TTS Faz 2.

## Polish için biriken cihaz testi geri bildirimleri

**Mutlaka HERMES_ROADMAP.md → "Polish Notları" bölümüne bak** — Step 1 (TTS) ve Step 3 (VAD) test sonuçları Mehmet'in kendi kelimeleriyle orada saklı. Step 9'a (polish) gelindiğinde tek tek elden geçirilecek.

Özet:
- Step 1 — "Sesler robotik" + "dil paketi UI yok" + "overflow 2.3px" + "session yok" geri bildirimi → kısmı düzeltildi, kısmı Step 9/Faz 2
- Step 3 — VAD test sonuçları kalıcı not. Özellikle: uzaktaki başka konuşmanın misfire olarak sınıflandırılması → bu davranış korunmalı (false trigger önler). `minSpeechFrames` düşürürken bozmamaya dikkat.

---

**Sıradaki: `03_env_cheatsheet.md`** — komut çalıştırmadan önce mutlaka oku.
