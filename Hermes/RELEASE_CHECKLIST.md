# Hermes — Release Öncesi Kontrol Listesi

> Uygulamayı yayınlamadan (store / public release) önce bu listeyi gözden geçir.
> Roadmap Step 9 (Polish) bu dosyaya yönlendirir.

## 🔒 Güvenlik / sırlar

- [ ] **HF token app içinde KALMASIN.** Geliştirme sırasında LLM çeviri test
      ekranında (`lib/features/llm_translate_test/`) HuggingFace token'ı bir
      alana elle giriliyor (runtime, in-memory). Release build'inde:
  - [ ] Dev/test ekranları (🧪 menüsü — `llm_translate_test`, `vosk_test`,
        `streaming_test`, `session_test`, `db_test`, `dual_mic_test`, vb.)
        production'dan **çıkarılmalı** → token alanı da onunla gider.
  - [ ] Kodda **hardcoded token YOK** doğrula: `git grep -nE 'hf_[A-Za-z0-9]{30,}'`
        boş dönmeli. (Token değeri yalnızca repo DIŞINDAKİ memory dosyasında:
        `~/.claude/.../memory/ref_hf_token.md`.)
  - [ ] Gated model (Gemma vb.) gerçekten kullanılacaksa: kullanıcıların **kendi
        token'ına ihtiyacı olmamalı** → modeli **kendi sunucunda host et**
        (token'sız iner) + Gemma Terms of Use / Prohibited Use bildirimini ekle.
        (Mevcut karar: Tier-3 = **Qwen**, Apache-2.0 → bu yük yok.)
  - [ ] **Kalıcı HF token (NS-3).** Ayarlar + model seçici girilen token'ı
        `HfTokenStore` ile **shared_preferences'a düz metin** yazar (kişisel
        cihaz kolaylığı). Release'de: ya secure storage'a taşı ya da Gemma
        self-host edilip token alanı tamamen kaldırılsın (`HfTokenStore`,
        `model_tier_selector` token kutusu, Ayarlar token dialog'u).
- [ ] Başka API anahtarı (Gemini vb. Faz 2) eklendiyse: koda gömülü değil,
      `.env` / secure storage üzerinden. Root `.gitignore` sır kalıplarını
      yoksayar; `.githooks/pre-commit` commit'te token kalıbını engeller
      (`git config core.hooksPath .githooks` ile aktif).

## 🧰 Dev görünürlük (release'de kapat)

- [ ] **Bas Konuş DEV overlay** — `push_to_talk_screen.dart` `kPttDevOverlay = true`
      ekranda aktif STT motoru/modeli + çeviri katmanı/modeli + son drop/hata
      teknik detayını basıyor (dev tanılama). Release'de **`false`** yap veya
      kaldır. Son kullanıcıya motor/model adı (Whisper/Vosk/Qwen…) gösterilmez.

## 📦 Build / boyut

- [ ] `flutter_gemma` MediaPipe lib'leri APK'yı ~656MB yapıyor. Tier-3 LLM
      (Qwen) tutuluyorsa: app bundle + model **ayrı indirme** (asset'e gömme).
- [ ] Kullanılmayan deney kodu temizliği (dual-mic Faz 2 harness'ı vb.).

## 🧪 Kalite

- [ ] `flutter analyze` temiz, tüm testler geçer.
- [ ] Hedef cihaz(lar)da son smoke test.
