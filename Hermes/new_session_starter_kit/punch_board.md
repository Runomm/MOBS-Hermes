# Punch Board — Modelden Modele Zaman Kapsülü

**Bu dosya nedir?** Hermes projesinde çalışan her Claude modeli (veya başka AI model), oturum başında ve sonunda buraya **bir entry** yazar. Bir nevi mesai defteri / vardiya devir tutanağı.

**Neden var?** Bir modelin token'ı bitebilir, oturum kapanabilir, conversation context buharlaşır. Memory & roadmap güncel kalsa bile, sıradaki model **"benden hemen önce kim ne yaptı, neyi çözmeye çalıştı, ne bıraktı"** sorusuna tek noktadan cevap bulamıyor. Punch board bunu çözer.

**Nerede dururuz?**
- **Roadmap (`HERMES_ROADMAP.md`)** = projenin step durumu (Step 5 ✅, Step 6 sırada). Stabil, refactoring değil, sadece tamamlanmış işler.
- **Polish Notları** (roadmap içinde) = cihaz testinden birebir geri bildirim. Step 9'a kadar saklanır.
- **Memory (`MEMORY.md`)** = oturumlar arası kalıcı bilgi (Mehmet kim, hangi kararlar, hangi mimari).
- **Punch board (BURASI)** = "şu anki oturum içinde ne oldu" + "bir sonraki model nereden devam etsin". Daha **kısa vadeli**, daha **anlatısal**. Bir entry birkaç hafta sonra anlamını yitirebilir; eski entry'leri silmek yerine arşivle (en yenisi üstte tutulur).

---

## Nasıl kullanılır

### Oturum başında

1. **En üstteki entry'i oku** (en yeni). Önceki modelin "Bıraktıklarım" bölümü senin başlangıç bağlamın.
2. Hâlâ açık bir iş varsa (örn. "cihaz testi bekliyor", "şu dosyayı yazamadım"), önce onu bitir.
3. Roadmap'i de oku — punch board ile çelişiyorsa **roadmap doğrudur** (punch board hatalı, düzelt).

### Oturum sırasında

Entry'i hemen yazma; oturum sırasında zaten roadmap + memory güncellenmeli. Punch board oturum **sonunda** doldurulur.

### Oturum sonunda (veya token bitmeden önce)

Aşağıdaki template'i kopyala, en üste (mevcut entry'lerin **üstüne**) yapıştır, doldur. **Bir paragrafı geçme** — kısa tut, ayrıntı için ilgili dosyaya link ver (roadmap, memory, kod dosyası).

### Acil durum (token kapanırken)

Tek satırla bile olsa yaz: "X dosyasını yazarken token bitti, devam eden gelir." Detay olmayabilir — varlık önemli.

---

## Entry template

Yeni entry'i bu bölümün hemen altına (en üste) yapıştır.

```markdown
---

## YYYY-MM-DD HH:MM — [Model adı, örn. Claude Opus 4.7]

**Devraldım:** [Önceki modelden ne aldım — bir cümle. "Step N bitmiş, Step N+1 sırada" gibi.]

**Yaptıklarım:**
- [Madde 1]
- [Madde 2]
- [Madde 3]

**Bıraktıklarım:** [Bir sonraki model için ne açık, neye dikkat etsin — bir/iki cümle. Aktif iş varsa onun durumu net olsun: kod yazılı mı, test geçti mi, cihazda denendi mi?]

**Sıradaki modele not:** [Opsiyonel — sezgi, uyarı, dikkat edilecek hassas nokta. Yoksa boş bırak veya "—" yaz.]
```

---

## Entry'ler (en yeni üstte)

---

## 2026-05-17 (akşam) — Claude Opus 4.7

**Devraldım:** Step 5 (Drift) bitmiş, Step 6 (ConversationSessionManager) yeni başlamış. Aynı modelin (ben) sabah Step 5'i bitirdiği oturumun devamı.

**Yaptıklarım:**

Step 6'yı **6a → 6b → 6c → 6d → 6e → 6f** olarak alt parçalara böldüm. Mehmet "Yöntem 2 — her parça ayrı tur" seçti.

- **6a ✅** `lib/core/engines/language_id/` — `LanguageDetector` interface + `MlKitLanguageDetector`. `google_mlkit_language_id: ^0.13.0` paketi eklendi (~3MB bundled offline asset). Tasarım kararı: conf < 0.6 → null = sessizce drop sinyali. 8/8 unit test (fake ile interface kontratı). Mehmet "(a) ML Kit, 50ms ihmal edilebilir" diye seçti, alternatifler tartışıldı (saf Dart heuristic, whisper_ggml fork).
- **6b ✅** `lib/core/audio/wav_writer.dart` — VAD'in `List<double>` Float32 samples'ını 44-byte canonical WAV header + 16-bit LE PCM olarak yazar (16kHz mono, Whisper tiny native rate). Clip ±1.0, asimetrik scale (-32768/+32767). 9/9 unit test.
- **6c ✅** `lib/core/session/conversation_session_manager.dart` (~300 satır) — State enum (idle/listening/transcribing/translating/speaking/paused/ending/error), `ConversationEvent` sealed (MessageAdded/Dropped/Error), `ConversationParticipant` enum (sourceSpeaker/targetSpeaker), pipeline: VAD→WAV→Whisper(auto)→LangID→FillerClean→Translate→TTS→Repository. Sıralı `_pipelineQueue`, repository'e TTS'ten önce yaz (TTS patlasa bile kalıcı), `temporaryDirectory` parametresi test edilebilirlik için. 8/8 unit test (fake engines + in-memory Drift).
- **6d ✅** TTS feedback guard (`_isTtsSpeaking` manager-level flag) + `_speakWithMode` (fast → stop+speak, full → sequential). 9 ek unit test: aynı dil üst üste / boş transkript / lang null / yabancı dil / translation exception recovery / feedback guard / mode davranışı. Toplam 61/61 test geçiyor, `flutter analyze` clean.

**6d sonunda fark ettim ki tasarım dokümanında çelişki var:** Bölüm 5 "TTS aktifken VAD bypass" diyor (kritik feedback loop guard). Bölüm 3.1b "Hızlı Mod: yeni utterance TTS oynarken gelirse → kes" diyor. İkisi çakışıyor — feedback guard aktifken yeni utterance pipeline'a hiç giremez ki interrupt'ı tetiklesin. Üç sahne anlattım Mehmet'e (A: rahat akış, B: araya girme, C: sessiz oda echo) ve üç seçenek sundum (1. mevcut bırak + polish notu, 2. pipeline parçala + AEC, 3. tasarımı düzelt).

**Mehmet bambaşka bir çözüm önerdi — donanım ayrımı.** Tasarımı 3 moda böldü:

1. **Headset Mode** — Kullanıcı kulaklık takar. Kulaklığın mic+hoparlörü User A için, telefonun mic+hoparlörü User B için. Donanım ayrımı = mantıksal ayrım. Feedback loop yok, dil tespiti gereksiz (hangi mic = hangi konuşmacı = hangi dil).
2. **Handset Mode** — Kulaklıksız. Ekran ortadan ikiye bölünür: üstte User A bölgesi + buton, altta User B bölgesi + buton. Basılı tut konuş (push-to-talk). Turn-based, aynı anda iki kişi konuşmaz.
3. **Manuel Çeviri** — Mevcut `TranslationTestScreen` (yaz, çevir, dinle). Menü/tabela çevirisi için kalır.

Kararlar:
- ✅ Mod seçimi **otomatik** (kulaklık takılıysa Headset, değilse Handset)
- ✅ `TranslationTestScreen` 3. mod olarak ana ekranda kalır
- ✅ `LanguageDetector` + ML Kit Language ID **silinecek** (yeni mimaride gereksiz)
- ✅ `SessionMode.fast/full` → `SessionMode.headset/handset` olarak revize edilecek
- ✅ Tasarım dokümanı (`HERMES_KONUSMA_MODU_TASARIM.md`) refactor edilecek

**Ama AÇIK kalan KRİTİK bir teknik soru var:** Headset Mode'un altındaki "iki ayrı donanım = iki ayrı stream" varsayımı Android'de gerçekten çalışıyor mu? İki yorum var:

- **Yorum X (paralel dual mic capture):** App aynı anda HEM kulaklık mic'ini HEM telefon mic'ini dinler. İki AudioRecord instance, iki VAD pipeline, iki yön. A ve B aynı anda konuşabilir. Bu Mehmet'in tasarımının orijinal niyeti gibi görünüyor ama emin değilim.
  - Android'de concurrent audio capture API 29+ destekli ama cihaza/OS sürümüne/audio policy'ye bağımlı
  - Xiaomi MIUI bunu optimization olarak kapatabilir (Poco X3 Pro'da bilinmez)
  - Flutter'daki `record` paketi tek `AudioRecord` instance açıyor → native Kotlin plugin yazmak gerek
  - **Önce POC**: ~3-5 saatlik mini bir Flutter native plugin yaz, Poco X3 Pro'da dual stream çalışıyor mu test et. Çalışırsa devam, çalışmazsa pivot

- **Yorum Y (tek mic + audio routing izolasyonu):** Kulaklık takılınca Android otomatik mic ve hoparlörü kulaklığa yönlendirir. Telefon mic'i ve hoparlörü uyur. Tek kullanıcı vardır (kulaklığı takan). Feedback loop yok çünkü ses kulaklıkta izole. Karşı kullanıcı telefon ekranını okur (yazılı). Bu yorumda Headset Mode tek-yönlü olur, Handset Mode'la pratikte aynı paradigmaya iner. O zaman **3 mod yerine 2 mod (Handset + Manuel) yeterli olur**, kulaklık sadece kullanım rahatlığı sağlar.

**Bıraktıklarım:** 6d sonunda durdum. Kod 61/61 test geçer hâlde, eski tasarıma göre. Refactor BAŞLAMADI. Mehmet "çok yoruldum, sonra tartışalım, punch board'a not düş" dedi.

**Sıradaki modele not — BU TURUN İLK İŞİ TASARIM KARARI:**

Mehmet henüz **Yorum X mi Yorum Y mi** olduğunu söylemedi. Kendisinin son cevabını birebir alıntılıyorum:
> "kulaklık takma zorunluluğu getiriyoruz. kulaklıkldaki mikrofon ve hoparlör, telefondaki mikrofon ve hoparlörden etkilenmeyecek. ayrıca kulaklığı olmayanlar için: app'in şuanki hali ayrı bir mod ahize modunda ekran ortadan ikiye bölünsün ve ekranın üstünde bir buton altında bir buton olsun kullanıcılar konuşurken butonlara basılı tutarak konuşsun. ve çeviri turn-based olarak gerçekleşsin. bu sayede ayrıca konuşanın kim olduğunu tespit etmekdende kurtulacağın kulaklığın mikrofonundan geliyorsa sağ telefonun mikrofonundan geliyorsa chatin soluna mesaj gider."

Cümle birden fazla yoruma açık. "Etkilenmeyecek" = feedback loop yok, kesin. Ama "iki ayrı mic'ten paralel okuma" şart mı, yoksa "iki ayrı mic'in fiziksel olarak izole olması yeter" mi belli değil. Son cümle ("kulaklığın mic'inden = sağ, telefonun mic'inden = sol") **paralel dual stream** ima ediyor — yani Yorum X gibi duruyor ama Mehmet bunu açıkça doğrulamadı.

İlk tur açılışında **kesinlikle bu soruyu netleştir.** Ben Mehmet'e şu soruyu sordum (cevap alamadım):

```
Headset Mode'un teknik niyeti hangisi?
A) Paralel dual mic capture (iki kişi aynı anda konuşabilir)
B) Tek mic, sadece feedback loop'sus (kulaklık ergonomik tercih, pratikte Handset gibi)
C) 3. yorum (Mehmet tarif eder)
```

**Eğer X seçilirse:**
1. Önce POC: minimal Flutter native plugin, Poco X3 Pro'da iki paralel `AudioRecord` aç (kulaklık ve telefon mic ayrı `setPreferredDevice`), 30 sn dinle, iki stream'in de gerçekten geldiğini doğrula. Çalışmazsa MIUI / cihaz limitasyonu kabul et, pivot
2. Çalışırsa: `HeadsetAudioInput` + `HandsetAudioInput` strategy interface, `ConversationSessionManager` her ikisini de destekler

**Eğer Y seçilirse:**
1. Daha sade: 2 mod (Handset push-to-talk + Manuel), kulaklık otomatik routing'i kullanılır ama özel mantık yok
2. Refactor daha hafif

**Karar verildikten sonra ortak adımlar:**
1. `HERMES_KONUSMA_MODU_TASARIM.md` baştan yaz (3.1 ConversationSessionManager bölümü, 3.2 VAD bölümü, 4 Veri Akışı, 5 Riskler, 7 İmplementasyon Sırası, 8 Onaylanmış Kararlar — hepsi etkilenir)
2. Kodu temizle (silinecekler):
   - `lib/core/engines/language_id/` (iki dosya)
   - `test/core/engines/language_id/`
   - `pubspec.yaml` → `google_mlkit_language_id` kaldır
   - `ConversationSessionManager`'dan `languageDetector` parametresi + `_classifyParticipant` mantığı
3. Refactor (kalanlar):
   - `WavWriter` aynen kalır (Handset için de gerek)
   - `SessionMode.fast/full` → `SessionMode.headset/handset`. **DİKKAT:** Drift schema'da `mode` text column, eski entry'lerde "fast"/"full" string'i yazılı. Mehmet'in cihazında Step 5 cihaz testinden 2 oturum var. Migration / mapping gerek. Hızlı çözüm: enum'a `fromDbValue` ile eski string'leri map et (`'fast' → 'handset' say`, `'full' → 'headset' say` veya tam tersi mantıklı eşleme).
   - `ConversationSessionManager` Strategy Pattern ile `AudioInput` abstract'ı alacak
4. Yeni kod:
   - `HeadsetAudioInput` (eğer X) — dual mic Kotlin plugin
   - `HandsetAudioInput` — push-to-talk wrapper, butondan tetiklenen single mic
   - UI: ana ekran 3 mod kart, Handset için bölünmüş ekran, Headset için (eğer X) chat
5. Test
6. Cihaz testi

**Diğer hatırlatmalar bir sonraki modele:**
- Mehmet "MOBS-Hermes" git repo'sunun içine `Hermes` klasörünü taşımak istedi, AMA process locks yüzünden başarısız oldu (adb + Gradle daemonlar kapatıldı, ama hâlâ bir şey klasörü tutuyordu — büyük ihtimal Windows Explorer veya bir IDE). Mehmet "boşver ben sonra yaparım" dedi, bunu üzerinde durma. Eğer Mehmet tekrar isterse: muhtemelen tüm IDE/Explorer kapatmadan olmaz.
- `04_doc_index.md` starter kit'in README'sinde referans veriliyor ama dosya yok (önceki bir model token'ı yetmemiş). Düşük öncelik, Mehmet onay verirse yazılabilir.

**Sıradaki modele not:** Mehmet'in yorgun olduğunu hissettim, ısrar etme. Yeni tur açıldığında "merhaba, kaldığımız yerden devam: Headset Mode'un teknik niyeti X mi Y mi?" diye nazikçe başla. Cevap geldikten sonra konuyu birkaç sahne ile sunarak doğrula (Yorum X seçilirse POC önerini açıkça söyle, "kod yazmadan önce 1-2 saatlik POC çalışıyor mu kontrol edelim" gibi). Refactor başladığında 61/61 test'in çoğu silinecek ama bu normal — şimdiki test'ler eski tasarımı doğruluyordu.

---

## 2026-05-17 — Claude Opus 4.7

**Devraldım:** Step 1-4 tamam (TTS, Dil paketi UI, VAD, FillerCleaner), Step 5 (Drift + ConversationRepository) önceki turda session limit'e takılıp bekletilmişti. Roadmap'te "Sıradaki tur açılışında ne yapılır" 8 maddelik plan hazırdı.

**Yaptıklarım:**
- `pubspec.yaml` → `drift: ^2.21.0`, `sqlite3_flutter_libs: ^0.5.24`, `path: ^1.9.0` + dev `drift_dev`/`build_runner` eklendi, `flutter pub get` temiz
- `lib/core/database/app_database.dart` — Drift şeması: `sessions` (id, mode, sourceLang, targetLang, startedAt, endedAt?) + `messages` (id, sessionId FK cascade, speakerLang, sourceText, translatedText?, createdAt). `PRAGMA foreign_keys=ON` `MigrationStrategy.beforeOpen`'da
- `build_runner` ile `app_database.g.dart` üretildi
- `lib/core/repositories/conversation_repository.dart` — `SessionMode.fast|full` enum + 7 metot. `listAllSessions` `startedAt desc + id desc` tiebreak (SQLite saniye granular)
- `test/core/repositories/conversation_repository_test.dart` — 11/11 unit test (in-memory `NativeDatabase.memory()`). İki bug yakaladı + düzeltildi: aynı saniye sıralama tiebreak ve `PRAGMA foreign_keys=ON` eksikliği
- `lib/features/db_test/db_test_screen.dart` + AppBar `Icons.storage` butonu — cihazda izole test ekranı (Oturum Aç / Mesaj Ekle / Oturumu Kapat + ListView)
- Mehmet Poco X3 Pro'da 6/6 senaryo geçirdi: oturum aç, 3 mesaj ekle, kapat, ikinci oturum + sıralama, **uygulamayı kill edip tekrar açma → veriler yerinde (kalıcılık ✅)**
- `flutter analyze` clean (28/28 unit test geçiyor — widget_test'in stale title beklentisi de yol üstünde düzeltildi: "Hermes — Çeviri Testi" → "Hermes — Çeviri + STT Testi")
- `HERMES_ROADMAP.md` Step 5 ✅ tikli, Step 6 aktif + Polish Notları'na Mehmet'in birebir geri bildirimi + analiz eklendi
- `project_hermes` memory checkpoint güncellendi (Step 5 ve Drift/SQLite kalıbı detayları)

**Bıraktıklarım:** Step 5 tam kapalı, açık iş yok. Step 6 (ConversationSessionManager — state machine, mode-aware fast/full TTS davranışı, auto-dil tespit, VAD→STT→çeviri→TTS pipeline'ını tek state machine altında birleştirme) bir sonraki turda başlayabilir. Detaylı adım listesi roadmap "Sıradaki tur açılışında ne yapılır" altında.

**Sıradaki modele not:** Step 6'da `AppDatabase` instance lifecycle'ına dikkat — DI ile **tek singleton** olmalı, birden fazla `AppDatabase()` aynı `hermes.sqlite` dosyasını locklayabilir (Step 5'te `DbTestScreen` izole olduğu için kendi instance'ını açıyor, prod'da bu kalıp tekrarlanmamalı). Bu uyarı zaten `project_hermes` memory'sine işlendi. Ayrıca: `04_doc_index.md` starter kit'in README'sinde referans veriliyor ama dosya yok (önceki tur token'ı yetmemiş) — Mehmet onay verirse onu da yazılabilir.
