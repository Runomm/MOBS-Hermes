# Hermes — Yeni Oturum Başlangıç Kiti

**Bu dosyayı oku, sırayla diğer dosyalara geç.** Hermes projesinde Mehmet'le çalışacak yeni bir Claude/AI modeli için kapsamlı oryantasyon. Hiçbir dış memory'ye bağımlı değil — bu klasör tek başına yeterli.

> **Not (bu README sabit eğitim materyalidir):** Mevcut proje durumu / step numarası / aktif iş zamanla değişir. Kanonik güncel durum **`HERMES_ROADMAP.md`** ("Aktif İş" + "Sıradaki tur açılışında ne yapılır" bölümleri) ve **`punch_board.md`** (en üstteki entry) içindedir. Aşağıdaki "30 saniyelik özet" sadece projenin genel kimliğini tarifler.

---

## 30 saniyelik özet

**Hermes**, Erasmus öğrencileri ve turistler için **çevrimdışı çalışan akıllı çeviri + not asistanı**. Flutter, Android-öncelikli (Mehmet'in cihazı: Poco X3 Pro). Strategy Pattern üzerine: STT (Whisper) + Translate (Google ML Kit) + TTS (Native OS) + VAD (Silero) + AudioInput.

**3 mod var** (Mehmet 2026-05-30 kesinleştirdi, isimler subject-to-change ama development boyunca korunur):
1. **Ders Modu** — tek yönlü live subtitles + transkript + sonradan Gemini özet
2. **Voice Translator** — kulaklık zorunlu, çift mic donanım ayrımı (kulaklık → sağ, telefon → sol)
3. **Bas Konuş Modu** — portrait ahize, ekran ortadan yatay ikiye bölünür, üst yarı 180° dönmüş + görünmez tap alanı

Plus bağımsız **Manuel Çeviri** (mevcut TranslationTestScreen, ana ekranda).

**Mehmet** = Mehmet Onur Boyraz, Flutter/Python yazıyor, Mac yok, RTX 4060. Türkçe konuşur. İletişim diline ne yazıyorsa o dilde cevap ver (Türkçe ağırlıklı).

---

## ⭐ Önerilen okuma sırası (deneyime göre)

Mevcut adımlar zaman ekonomik sıralamayla — başlangıçta en taze ve kararsal bağlamı, sonra geniş resmi al. Atlama yapma; her adım sonraki adımı anlamlı kılıyor.

### 1. **`punch_board.md` — en üstteki entry** *(her şeyden önce)*
Önceki modelin "Bıraktıklarım" + "Sıradaki modele not" satırları senin **gerçek başlangıç bağlamın**. Hangi sub-step'te bırakıldı, hangi karar açık, neye dikkat etmen gerek — hepsi orada. Aşağıdaki entry'leri sadece tarihsel ilgi için tarayabilirsin.

### 2. **`HERMES_ROADMAP.md` "Mevcut Durum" + "Aktif İş" + "Sıradaki tur açılışında ne yapılır"**
Roadmap kanonik statü dosyası. Aktif sub-step'i, somut adım listesini, açık riskleri burada görürsün. Punch board "anlatısal", roadmap "yapılandırılmış" — ikisi tutarsızsa **roadmap doğrudur** (punch board hatalı, düzelt).

### 3. **`01_user_and_workflow.md` — Mehmet'in kuralları**
Step-by-step ilerleme, cihaz testi sonrası birebir geri bildirim kaydı, roadmap güncelleme zorunluluğu. **Kural 1** ihlali Mehmet'i geçmişte revert ettirmiş — okuduğundan emin ol.

### 4. **`memory/MEMORY.md` + ilgili memory dosyaları** *(varsa)*
Konum: `C:\Users\mehon\.claude\projects\C--Projects-FonksiyonelProgramlama-MOBS-Hermes\memory\` (eski konum `...-FonksiyonelProgramlama\memory\` taşındı). `MEMORY.md` indeks, ilgili dosyaları (project_hermes, feedback_hermes_workflow, ref_hermes_roadmap, ref_hermes_konusma_modu_tasarim) sırayla oku. Memory point-in-time observation — kod referansı varsa **mevcut state'i doğrula**, körü körüne güvenme.

### 5. **`HERMES_KONUSMA_MODU_TASARIM.md`** *(koda dokunmadan önce zorunlu)*
3 mod mimari blueprint — AudioInput strategy, DualMicAudioInput plan, Drift schema, veri akışları, riskler, sub-step sırası, onaylanmış kararlar. Kod yazarken kararları **dokümandan oku, değiştirme** — yeni karar gerekirse Mehmet'e sor.

### 6. **`03_env_cheatsheet.md`** *(komut çalıştırmadan önce zorunlu)*
PowerShell tuzakları, log UTF-16 encoding, NDK pin, cihaz USB ID, Drift codegen komutu. **3 hayatî tuzak**:
- `*>` redirect log dosyasını lock'lar → yeni `flutter run` öncesi stale dart process'leri kill
- `2>&1` native command'ları kırar → `*>` kullan
- Log UTF-16 → `iconv -f UTF-16LE -t UTF-8` veya `Get-Content | Select-String`

### 7. **`02_project_state.md`** *(geniş resim, ama eskiyebilir)*
Snapshot doküman — yazıldığı tarihteki step durumunu özetler. **Roadmap kanonik kaynak**; bu dosyayla çelişiyorsa roadmap'i takip et. Tarihsel referans için faydalı.

### 8. **`04_doc_index.md`** *(eğer varsa)*
⚠️ Henüz yazılmamış olabilir (önceki modellerin token'ı yetmediği için). Mehmet onayı verirse yazılabilir.

---

## Bu klasördeki dosyaların kısa özeti

| Dosya | İçerik |
|---|---|
| **00_README.md** (bu dosya) | Oryantasyon + okuma sırası |
| **punch_board.md** | Vardiya devir tutanağı — her modelin oturum başı/sonu notları, en yeni üstte |
| **01_user_and_workflow.md** | Mehmet'in profili + 5 çalışma kuralı |
| **02_project_state.md** | Snapshot proje durumu (eskiyor — roadmap kanonik) |
| **03_env_cheatsheet.md** | PowerShell tuzakları, USB cihaz, NDK, Drift codegen, log encoding |
| **04_doc_index.md** | Tüm proje dokümanlarının indeksi (⚠️ henüz yazılmadı) |

Klasör dışındaki ana referanslar:
- `..\HERMES_ROADMAP.md` — kanonik statü
- `..\HERMES_KONUSMA_MODU_TASARIM.md` — 3 mod mimari blueprint
- `..\HERMES_TEKNIK_REFERANS.md` — teknoloji seçimleri
- `..\HERMES_LAB2..6_*.md` — akademik teslim labları
- `..\hermes\` — Flutter projesi (kod)

---

## Konum

- **Proje kökü:** `C:\Projects\FonksiyonelProgramlama\MOBS-Hermes\Hermes\` (2026-05-30'da MOBS-Hermes git repo'sunun içine taşındı; eski yol `...\FonksiyonelProgramlama\Hermes\` artık geçersiz)
- **Flutter app:** `C:\Projects\FonksiyonelProgramlama\MOBS-Hermes\Hermes\hermes\`
- **Bu starter kit:** `C:\Projects\FonksiyonelProgramlama\MOBS-Hermes\Hermes\new_session_starter_kit\`
- **Hafıza dosyaları:** `C:\Users\mehon\.claude\projects\C--Projects-FonksiyonelProgramlama-MOBS-Hermes\memory\`

---

## Çok kritik 3 kural — bunları unutursan iş bozulur

1. **Step-by-step ilerle.** `flutter analyze` clean = İŞİN BİTMESİ DEMEK DEĞİL. Sıradaki şart **cihaz testi** (Poco X3 Pro). Cihaz testi geçmeden bir sonraki step'e geçme. *"Pipeline'ı kapatmak için TTS'i de hızlıca ekleyeyim"* gibi shortcut'lar yapma — Mehmet bir kez bu yüzden revert ettirdi.

2. **Cihaz testi geri bildirimini BİREBİR sakla.** Kullanıcı testten döndüğünde ne dediyse `HERMES_ROADMAP.md` → "Polish Notları" bölümüne kelime kelime kaydet, parafraze etme. Mehmet "önemli değil" dese bile kaydet (Step 9 polish'inde "neyi unutmuştum?" sorusunun cevabı orada olsun).

3. **Her step bitiminde:**
   - `HERMES_ROADMAP.md` "Aktif İş" + "Sıradaki tur" + "Polish Notları" + "Son güncelleme" güncellenir
   - Memory ilgili dosyaları (project_hermes vb.) güncellenir
   - Oturum sonunda **punch_board.md** en üstüne yeni entry — bir sonraki modelin "Devraldım" satırı senin entry'inden geliyor

---

## Ortam tuzakları (özet — detay `03_env_cheatsheet.md`'de)

- **PowerShell `*>` redirect**, `flutter run`'ı kapattıktan SONRA bile log dosyasını kilitli tutabiliyor — yeni run patlar. Workaround: `Get-Process | Where-Object { $_.ProcessName -match "flutter_tester|dart" } | Stop-Process -Force`
- **NDK 29.0.13113456** pinli (`android/app/build.gradle.kts`). `whisper_ggml` strict istiyor.
- **Poco X3 Pro device ID**: `cd61ba57`. USB bağlı olunca `flutter devices` listesinde M2102J20SG olarak çıkar. İlk USB bağlantıda telefon ekranında "USB hata ayıklamasına izin ver" dialogu çıkar — Mehmet onaylamalı.
- **Log dosyası encoding'i UTF-16** (PowerShell `*>` default). Bash'ten okurken `iconv -f UTF-16LE -t UTF-8`, PowerShell'den `Get-Content | Select-String`. Ham `grep` çalışmaz.
- **PowerShell `2>&1` native command'ları kırar** → `NativeCommandError` false positive üretir, `BUILD FAILED` gibi görünür. Log'un son satırlarına bak: `Sending viewport metrics to the engine` + `ProfileInstaller` görüyorsan **build başarılıdır**, görünür hata göz ardı edilebilir.
- **Dart `caseSensitive: false`**, Türkçe `İ ↔ i` eşlemez. Türkçe regex'lerde açık character class lazım: `[İi]şte`.
- **Dart `replaceAll`**, backreference desteklemez. `$1` literal kalır. Gerekirse `replaceAllMapped` kullan.
- **Drift codegen**: schema değişikliği sonrası `dart run build_runner build --delete-conflicting-outputs` → `app_database.g.dart` regen.
- **flutter run task'i exit edebilir**: hot reload bağlantısı bittikten sonra (cheatsheet tuzak #4) — app cihazda çalışmaya devam ediyor olabilir, log'a yeni satır düşmez. Smoke testten önce log'u incele.

---

## Test cihazı

Mehmet'in birincil cihazı: **Poco X3 Pro** (Snapdragon 860, Android 13, USB ID `cd61ba57`). USB debugging açık. Demo için iPhone 17 Pro Max var ama iOS build'i Mac gerektirir (Mac yok). **Faz 1 boyunca iOS test edilmiyor** (Codemagic iterasyonu 15+ dk, Android'de 30 sn).

---

## Bu projedeki "ben" kimim (modelden modele)

Sen yeni bir model olarak geldin. Önceki tur(lar)daki "ben" (genelde Claude Opus 4.7) Mehmet'le birlikte Faz 1'in büyük kısmını tamamladı. Yaptıklarını ve kararları **punch_board** + **memory** + **HERMES_ROADMAP** + **HERMES_KONUSMA_MODU_TASARIM** dokümanlarında bulabilirsin. Bunları yukarıdaki sırayla oku, sonra "Aktif İş"i ele al.

Yeni şey eklemek için Mehmet'in onayını al — Konuşma Modu tasarımındaki kararlar (3 mod + Yöntem B + 2D enum + LangID saklama + portrait lock vs.) onun onayından geçti, değişiklik gerekirse soru sor.

---

## ⚡ Token & hız tasarrufu — sıradaki modele tüyolar (2026-05-31, Opus 4.8 deneyiminden)

Önceki turlar bu tuzaklara düştü ve token yaktı. Sen düşme:

1. **Bir dosyayı İKİ KEZ okuma.** Read sonucu zaten context'inde — tekrar Read edersen harness "Wasted call" döndürür, token gider, bilgi gelmez. Edit'ten sonra da geri okuma: Edit hata vermediyse değişiklik tutmuştur (harness dosya state'ini izliyor).

2. **Paralel tool batch'inde bağımlı/yinelenen çağrı koyma.** Aynı mesajda birden fazla tool çağırmak hızlıdır AMA biri patlarsa (özellikle Bash parse hatası) **tüm batch iptal olur** — bu turda 20+ çağrılık bir batch tek bir `cat` quoting hatasından çöptü, Kotlin dosyaları diske düşmedi. Kural: aynı batch'e yalnızca **birbirinden bağımsız** ve **tek seferlik** çağrılar koy. Şüphedeysen böl.

3. **Bash yerine dedicated tool.** Dosya okuma=Read, içerik arama=Grep, dosya bulma=Glob, yazma=Write/Edit. `cat`/`grep`/`find`/`echo` Bash'te hem yavaş hem Windows'ta quoting tuzaklı (cascade kıran tam buydu). Bash'i yalnızca git/flutter/gerçek komutlar için kullan. Çok satırlı içerik için `cat <<EOF` deneme — Write kullan.

4. **Okumayı sınırla — hepsini baştan sona okuma.** Başlangıç bağlamı için **sadece** şu 3 şey yeter: `punch_board.md` en üst entry + roadmap "Aktif İş"/"Sıradaki tur açılışında" + ilgili bir-iki kod dosyası. Starter kit'in 01/02/03'ünü ezbere okuma; ihtiyaç anında Grep'le nokta atışı yap. `02_project_state.md` çoğu zaman eskimiş — atla, roadmap kanonik.

5. **Deferred tool'u çağırmadan schema yükle.** `TaskCreate`/`TaskUpdate` gibi araçlar başta tanımlı değil — doğrudan çağırırsan validation hatası alırsın (typed param'lar string'e döner). Önce `ToolSearch query:"select:TaskCreate,TaskUpdate"`, sonra çağır. Tek seferde yükle, her task için tekrar arama yapma.

6. **AskUserQuestion'ı topla.** Mehmet'e soracaklarını tek çağrıda 2-4 soru olarak sor (multiSelect destekli), tek tek sorma — her tur-trip token + Mehmet'in zamanı.

7. **flutter analyze/test'i arka planda çalıştır** (`run_in_background: true`), bitince bildirim gelir; boşuna polling yapma. `flutter run` öncesi stale dart process'leri öldür (cheatsheet tuzak #1).

8. **Mehmet kısa konuşur, sen de öyle yap.** Uzun açıklama yerine eylem+sonuç. Bir tasarım kararı zaten dokümanda yazılıysa tekrar tartışma — oku, uygula (Kural 4).

---

İyi çalışmalar. **Sıradaki ilk işin: `punch_board.md`'nin en üstündeki entry'i oku.**
