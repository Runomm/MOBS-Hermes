# Hermes — Yeni Oturum Başlangıç Kiti

**Bu dosyayı oku, sırayla diğer dosyalara geç.** Hermes projesinde Mehmet'le çalışacak yeni bir Claude/AI modeli için kapsamlı oryantasyon. Hiçbir dış memory'ye bağımlı değil — bu klasör tek başına yeterli.

---

## 30 saniyelik özet

**Hermes**, Erasmus öğrencileri ve turistler için **çevrimdışı çalışan akıllı çeviri + not asistanı**. Flutter, Android-öncelikli (Mehmet'in cihazı: Poco X3 Pro). Strategy Pattern üzerine: STT (Whisper) + Translate (Google ML Kit) + TTS (Native OS) + VAD (Silero). Şu an **Faz 1'in 4/9 step'i tamam**, Step 5 (Drift/SQLite) sırada.

**Mehmet** = Mehmet Onur Boyraz, Flutter/Python yazıyor, Mac yok, RTX 4060. Türkçe konuşur. İletişim diline ne yazıyorsa o dilde cevap ver (Türkçe ağırlıklı).

---

## Bu klasörü nasıl oku

| Dosya | Neyi anlatır | Ne zaman bak |
|---|---|---|
| **00_README.md** (bu dosya) | Oryantasyon | Her şeyden önce |
| **01_user_and_workflow.md** | Mehmet kim, nasıl çalışılır | İLK iş başlamadan önce mutlaka |
| **02_project_state.md** | Şu an nerede kaldık, sıradaki ne | Yeni iş'e başlamadan önce |
| **03_env_cheatsheet.md** | PowerShell tuzakları, USB device, NDK, runtime quirks | Komut çalıştırmadan önce |
| **04_doc_index.md** | Tüm proje dokümanlarının indeksi | Detay gerektiğinde (⚠️ henüz yazılmadı — önceki modelin token'ı bittiği için) |
| **punch_board.md** | Vardiya devir tutanağı — her modelin oturum başı/sonu notları | **İlk iş.** En üstteki entry sıradaki modelin başlangıç bağlamı. Oturum sonunda buraya yeni entry yaz. |

---

## Hızlı durum (2026-05-17 itibarıyla)

**Tamamlananlar:** Translation (ML Kit) → STT (Whisper tiny) → TTS (Native OS) → Language Pack UI → VAD (Silero v4) → FillerCleaner (16/16 test geçti). Cihaz testleri Poco X3 Pro'da yapıldı, hepsi başarılı.

**Sıradaki tek satırlık iş:** Step 5 — Drift + SQLite ile `ConversationRepository`. Detaylı talimatlar `HERMES_ROADMAP.md` içinde "Sıradaki tur açılışında ne yapılır" bölümünde.

**Konum:**
- Flutter projesi: `C:\Projects\FonksiyonelProgramlama\Hermes\hermes\`
- Tüm dokümanlar (LAB'lar, ROADMAP, TASARIM): `C:\Projects\FonksiyonelProgramlama\Hermes\`
- Bu starter kit: `C:\Projects\FonksiyonelProgramlama\Hermes\new_session_starter_kit\`

---

## Çok kritik 3 kural — bunları unutursan iş bozulur

1. **Step-by-step ilerle.** `flutter analyze` clean = İŞİN BİTMESİ DEMEK DEĞİL. Sıradaki şart cihaz testi. Cihaz testi geçmeden bir sonraki step'e geçme. *"Pipeline'ı kapatmak için TTS'i de hızlıca ekleyeyim"* gibi shortcut'lar yapma — Mehmet bir kez bu yüzden revert ettirdi.

2. **Cihaz testi geri bildirimini BİREBİR sakla.** Kullanıcı testten döndüğünde ne dediyse `HERMES_ROADMAP.md` → "Polish Notları" bölümüne kelime kelime kaydet, parafraze etme. Step 9'a (polish) gelindiğinde bu birikim elden geçirilir.

3. **Her step bitiminde roadmap güncelle.** Step tikle, "Aktif İş"i bir sonrakine taşı, son güncelleme tarihini değiştir. Detay 01_user_and_workflow.md'de.

---

## Ortam tuzakları (özet)

- **PowerShell `*>` redirect**, `flutter run`'ı kapattıktan SONRA bile log dosyasını kilitli tutabiliyor — yeni run patlar. Workaround: `Get-Process | Where-Object { $_.ProcessName -match "flutter_tester|dart" } | Stop-Process -Force`
- **NDK 29.0.13113456** pinli (`android/app/build.gradle.kts`). `whisper_ggml` strict istiyor.
- **Poco X3 Pro device ID**: `cd61ba57`. USB bağlı olunca `flutter devices` listesinde M2102J20SG olarak çıkar.
- **Log dosyası encoding'i UTF-16** (PowerShell `*>` default). Grep ederken `Get-Content | Select-String` kullan, ham `grep` çalışmaz.
- **Dart `caseSensitive: false`**, Türkçe `İ ↔ i` eşlemez. Türkçe regex'lerde açık character class lazım: `[İi]şte`.
- **Dart `replaceAll`**, backreference desteklemez. `$1` literal kalır. Gerekirse `replaceAllMapped` kullan.

Tam liste: `03_env_cheatsheet.md`.

---

## Test cihazı

Mehmet'in birincil cihazı: **Poco X3 Pro** (Snapdragon 860, Android 13). USB debugging açık. Demo için iPhone 17 Pro Max var ama iOS build'i Mac gerektirir (Mac yok). Faz 1'de iOS testi atlandı.

---

## Bu projedeki "ben" kimim (modelden modele)

Sen yeni bir model olarak geldin. Önceki tur(lar)daki "ben" (Claude Opus 4.7) Mehmet'le birlikte Faz 1'in dört adımını tamamladı. Yaptıkları ve kararları bu starter kit + `HERMES_ROADMAP.md` + `HERMES_KONUSMA_MODU_TASARIM.md` dokümanlarında. Bu dokümanları okuyup ben'in bıraktığı yerden devam et. Yeni şey eklemek için Mehmet'in onayını al — Konuşma Modu tasarımındaki kararlar (a-f) onun onayından geçti, değişiklik gerekirse soru sor.

---

İyi çalışmalar. **Sıradaki ilk işin: `01_user_and_workflow.md`'yi oku.**
