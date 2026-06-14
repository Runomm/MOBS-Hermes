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

## 2026-06-14 — Claude Opus 4.8 — iOS BUILD HAZIRLIĞI (Mac'siz, Codemagic + Sideloadly) — `ios-build` dalı push edildi

**Devraldım:** #4 entry — kod tamam, analyze temiz, 196 test, açılış siyah-ekran açık. Mehmet bu turda YÖN DEĞİŞTİRDİ: **iPhone 17 Pro Max'te iOS testi** (Faz 1 boyunca iOS test edilmiyordu, artık ediliyor). "Son kontroller + animasyon/pixel doğru mu + adım adım iOS build."

**Yaptıklarım:**
- **Son kontroller ✅:** analyze temiz; mesh **oransal** çiziliyor → her boyuta ölçeklenir; `HgScreen` **SafeArea** kullanıyor → iPhone Dynamic Island/home indicator doğru; HgGlass standart BackdropFilter; orientation portraitUp + status bar transparan. Animasyon/pixel iOS için sorunsuz.
- **iOS engelleri (kod/config) düzeltildi:** (1) `ios/Runner/Info.plist`'e NSMicrophone/Camera/PhotoLibrary UsageDescription (yoktu → çökerdi); (2) deployment target **13.0→16.0** (flutter_gemma+onnxruntime 16, whisper 15.6, mlkit 15.5) — `project.pbxproj` (3 yer) + yeni `ios/Podfile` (post_install tüm pod'ları 16.0'a sabitler); (3) kök `.gitignore`'a build/ + handoff zip/klasörleri.
- **`codemagic.yaml`** (repo kökü): `ios-unsigned` workflow, `working_directory: Hermes/hermes`, `flutter build ios --release --no-codesign` → Payload zip → imzasız IPA artifact.
- **Git:** origin/main yalnız "Lift Off"tu, TÜM uygulama kodu commit'siz idi → hepsi (139 dosya, build/scratch/zip hariç) yeni **`ios-build` dalında** tek commit (9e4525e) → **origin'e push edildi**. main'e dokunulmadı.

**Bıraktıklarım:** **`ios-build` GitHub'da, Codemagic derlemeye hazır.** AÇIK İŞ (Mehmet yapacak, ben başlatamam): (1) Codemagic'e repo bağla → `ios-build` → `ios-unsigned` run → `Hermes-unsigned.ipa` indir; (2) Windows Sideloadly + ücretsiz Apple ID ile iPhone'a sideload (7 gün). **Codemagic ilk build'de pod/derleme hatası çıkabilir (gemma/onnxruntime/whisper iOS ilk kez derleniyor) → log gelince düzeltilecek.**

**Sıradaki modele not:** ⚠️ **vosk_flutter_2 iOS YOK** → "fast" hands-free tier iPhone'da MissingPluginException (Whisper full/full+ çalışır; açılışta Vosk'a dokunulmuyor, app açılır). Demoda fast seçme; istenirse `Platform.isIOS`'ta fast tier gizlenebilir (yapılmadı). ⚠️ Ücretsiz Apple ID = 7 gün + bazı entitlement limiti. ⚠️ Açılış siyah-ekran (Android, #4) hâlâ açık. ⚠️ Codemagic free tier macOS dakika limitli. Mehmet kısa/net.

---

## 2026-06-13 (#4) — Claude Opus 4.8 — 3. cihaz testi düzeltmeleri (overflow fit + native splash + connectivity eyebrow + OCR overlay şeffaf)

**Devraldım:** Aynı oturum. Mehmet 3. testte: header overflow, açılışta hâlâ siyah ekran, eyebrow animasyonsuz/takılıyor/az dil, görsel çeviri kontrolleri yeterince şeffaf değil. (Overscroll/Manuel/boş-transkript/çökme ✅ onaylandı.)

**Yaptıklarım (analyze temiz, 196 test, arm64 APK build):**
- **(A) Overflow:** Home header eyebrow + "Hermes"+logo satırı `FittedBox(scaleDown, centerLeft)` → tüm cihaz en-boylarında otomatik küçülür (Poco'ya özel değil).
- **(2) Eyebrow ✅:** `connectivity_plus: ^6.1.0` (event-driven, internet kopunca anında; `InternetAddress.lookup` poll'u kaldırıldı); `_OnlineBadge` 10 dil (tr/en/es/fr/de/it/ar/zh/ja/ru) online+offline eşit; fade+slide 650ms, döngü 2.2s.
- **(5) Görsel Çeviri overlay ✅:** `_langBar`/`_tierSelector`/`_resultCard`/`_captureButtons`'a `glass`/`intensity`/`compact` paramları; foto-üstü hepsi `glass:42` (şeffaf) + compact + padding 12/üst6/alt8 (kenarlara yakın). ModelTierSelector'a `intensity` param eklendi.
- **(1) Splash siyah — ⚠️ ÇÖZÜLEMEDİ (4 deneme, cihazda devam):** (i) `drawable-v21` + NormalTheme `?android:colorBackground` karanlıkta siyahmış → `colors.xml`(+night) `launch_bg`; (ii) Android 12+ `windowSplashScreenBackground` → `values-v31`+`values-night-v31`; (iii) `main()` `await FlutterGemma.initialize()` runApp'ten önceydi → `SplashScreen._initEngines`'e ARKA PLANA alındı, runApp neredeyse anında; (iv) night `launch_bg` #100E14→#FCFBFF. **Mehmet son test: hâlâ ~3sn siyah + 1sn logo.** 1s logo=sistem splash OK; ~3s siyah DEVAM (muhtemelen debug motor cold-start veya native pencere boşluğu).

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 196 test, arm64 APK Poco'da. ✅ overflow/eyebrow/OCR-overlay onay bekliyor (muhtemelen iyi).** ⚠️ **AÇIK İŞ: açılıştaki ~3sn siyah ekran GİTMEDİ** (Mehmet bugünlük bıraktı). Bugünkü 4 yöntem yetmedi.

**Sıradaki modele not — SİYAH EKRAN İÇİN DENE:** (a) **`flutter_native_splash`** paketi (Android 12 keep-on-screen dahil, battle-tested — manuel `values-v31`/colors yerine bunu kullan); (b) **release/profile APK** ile süreyi ölç → debug mı suçlu kesinleştir (büyük olasılıkla evet); (c) `MainActivity.onCreate`'de `androidx.core.splashscreen` `installSplashScreen().setKeepOnScreenCondition` ile sistem splash'i ilk Flutter frame'e kadar tut. ⚠️ `connectivity_plus` interface bağlantısı=online (captive portal'da yanlış olabilir, kabul). Native splash zemini cihaz DARK MODE'una göre (hgThemeMode'a değil). FittedBox kalıbı diğer overflow'larda da kullanılabilir. Mehmet kısa/net.

---

## 2026-06-13 (#3) — Claude Opus 4.8 — Büyük feedback paketi (7 madde): RAM disiplini + crash guard + splash + tam-overlay OCR + boş transkript fix

**Devraldım:** Aynı oturum. Mehmet 2. cihaz testinden 7 maddelik feedback verdi (Polish'te birebir). Hepsi bu turda kodlandı.

**Yaptıklarım (analyze temiz, 196/196 test, arm64 debug APK build):**
- **(1) RAM + crash:** `core/services/ram_manager.dart` — NLLB daima resident; `withLlmRam` (offline özet: NLLB unload→LLM→LLM unload→NLLB sessiz reload); `freeForLiveSession` (canlı warmup öncesi LLM unload, NLLB kalır); `freeAll`. `NllbTranslationEngine` statik `preloadShared`/`unloadShared`/`sharedLoaded`. `main()` `runZonedGuarded` + `ErrorWidget.builder`→dostça "cihaz tam kapasite" ekranı. Canlı 3 ekran hata görünümüne "RAM'i boşalt ve tekrar dene". crunch_runner `runSummarize` NLLB swap'li.
- **(2) Banner/overscroll:** `main.dart` `_NoGlowScrollBehavior` (mor glow/stretch yok); `hg_glass.dart` açık-mod gölge mor-mavi(60,50,120)→nötr ink(40,38,66).
- **(3) Eyebrow:** `home_screen` `_OnlineBadge` — 6 dilde çevrimdışı/çevrimiçi fade döngü; offline=coral, online=yeşil (InternetAddress.lookup, 10s probe; .timeout YOK→test timer leak'i önlendi).
- **(4) Manuel:** scroll→Expanded sonuç alanı (ekran dolu, alt boş değil); input tek-çerçeve (TextField filled:false + tüm border none + isCollapsed).
- **(5) Boş transkript (KÖK NEDEN):** ekran `dispose()`'ta `_db.close()` senkron çalışıp async `deleteSessionIfEmpty`'yi boşa düşürüyordu → DB kapatma session/manager dispose SONRASINA alındı (conf/smalltalk/ptt).
- **(6) Görsel Çeviri tam overlay:** fotoğrafsız=sade CTA (boş preview yok); fotoğraflı=`Scaffold` tam ekran foto + Positioned şeffaf cam üst (başlık/dil/motor) + alt (sonuç/çek-galeri); bloklar fotoğrafta. OCR motoru `OcrBlock`+`imageSize` (önceki turdan).
- **(7) Splash:** `features/splash/splash_screen.dart` animasyonlu (logo fade+scale + parıltı şeridi) ~1.7s → Home; NLLB arka planda preload. Tema toggle kalıcı (önceki tur).

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 196/196, arm64 APK build.** Cihaza kurulup başlatıldı (Poco). **CİHAZ SMOKE BEKLİYOR (Mehmet):** (1) ağır işlerde çökme azaldı mı + hata→dostça mesaj + "RAM boşalt"; (2) overscroll mor yanıp sönme gitti mi + banner şeffaf; (3) eyebrow çok-dilli animasyon + renk; (4) Manuel açılıyor + tek kutu + alt dolu; (5) boş konuşma (konferans/smalltalk geri tuşu) artık kaydedilmiyor; (6) Görsel Çeviri tam ekran foto + şeffaf kontroller; (7) splash + NLLB hazır hissi.

**Sıradaki modele not:** ⚠️ Native OOM (signal 9) Dart'ta yakalanamaz — RAM disiplini azaltır ama tam çözmez; cihaz testinde hâlâ çökerse `freeForLiveSession`'a NLLB unload da eklemek gerekebilir (ama Mehmet NLLB resident istiyor — denge). `InternetAddress.lookup` eyebrow probe'u online/offline için; gerçek bağlantı yokken coral. Splash süresi sabit 1.7s. ⚠️ HgScreen scroll:true İÇİNE TextField/LayoutBuilder KOYMA (IntrinsicHeight patlar) — scroll:false + kendi scroll'un. ⚠️ ekran dispose'ta DB'yi session dispose'tan ÖNCE kapatma. Mehmet kısa/net.

---

## 2026-06-13 — Claude Opus 4.8 — UI RESTYLE TUR 2 KALANI (a–f) BİTTİ + Görsel Çeviri LENS overhaul (analyze temiz, 196/196, arm64 APK build)

**Devraldım:** Tur 2 yarıda (önceki Fable 5 entry'si): analyze temiz, 196/196, APK YOK, kalan iş listesi (a–g) roadmap "EN GÜNCEL"de. Bu turda a–f kodlandı + APK build edildi.

**Yaptıklarım (analyze temiz, 196/196 test, arm64 debug APK BUILD edildi):**
- **(a) PTT split** (`push_to_talk_screen.dart`) → HgScreen, warmup/running/ended/error fazları SmallTalk kalıbında; split korundu (üst yarı RotatedBox 2, görünmez bas-konuş), cam balonlar (smalltalk tint), orta cam pill "SmallTalk · pair"+hairline+Bitir, mic ipucu; **session/manager mantığı aynen**.
- **(b) Manuel Çeviri** (`main.dart`) → HgScreen+NavHeader (dev menü cam ikonda), LangBar pill→cam bottom-sheet dil picker (6 dil, ready/indir dot), cam input/sonuç kartları, Çevir gradient+mic cam, autoSpeak. Eski dropdown+`_LanguageRow` silindi.
- **(c) GÖRSEL ÇEVİRİ LENS (feature!)** → `OcrResult`+`OcrBlock`(metin+`Rect`)+`imageSize`; `MlKitTextRecognizer` blok kutuları + `instantiateImageCodec` ile piksel boyutu. Ekran: foto cam viewport, blok=tıklanabilir kutu (scale=viewportW/imageW), dokun→çevir→kutu üstüne bindir (Lens)+sonuç kartı; auto'da blok bazında dil tespiti. `HgScreen(scroll:false)`+kendi SingleChildScrollView (LayoutBuilder↔IntrinsicHeight çakışması). OCR test 4/4 (MLKit kanal mock + büyük pencere + reduce-motion).
- **(d) ModelTierSelector** HG (cam segment + WarnGlass "Ayarları Aç"), opsiyonel `accent`.
- **(e) low_ram_warning** → cam dialog. **(f) tema toggle KALICI** (`setHgThemeMode`/`loadHgThemeMode`, prefs `hg_theme_mode`, main'de yükle, Home toggle setter'a bağlı).

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 196/196, arm64 debug APK build (`build/app/outputs/flutter-apk/app-debug.apk`, ~617MB). CİHAZ YOKTU → KURULAMADI. CİHAZ SMOKE BEKLİYOR (Mehmet):** `adb -s cd61ba57 install -r -d ...app-debug.apk` → (1) PTT split iki yarı+180°+balon+Bitir; (2) Manuel dil picker/çevir/dinle/tier "Ayarları Aç"; (3) **Görsel Çeviri Lens: foto→bloklar kutu→bloğa dokun→üstüne çeviri biner+sonuç kartı** (ASIL YENİ FEATURE); (4) low_ram cam dialog; (5) tema toggle yeniden başlatınca kalıcı mı.

**Sıradaki modele not:** Cihaz smoke + birebir feedback'i Polish'e. Sonra: tema toggle'ı Ayarlar'a taşı (şu an Home); `hermes_card.dart` ölü kod (silinebilir); dev/test 🧪 ekranları hâlâ HermesColors/Material (kullanıcıya görünmez). ⚠️ Dosya düzenleme yalnız Edit/Write (PowerShell `-replace` Türkçe UTF-8 bozar). ⚠️ HgGlass gerçek BackdropFilter — OCR çok-bloklu fotoda jank olursa `blur:false`. Önceki turların bekleyen cihaz smoke'ları (Gemini/crunch/NLLB/daanzu) hâlâ açık. Mehmet kısa/net.

---

## 2026-06-12 (2) — Claude Fable 5 — UI RESTYLE TUR 2: tüm ekranlar liquid-glass (YARIDA — kota bitti)

**Devraldım:** Aynı oturum. Tur 1 (Mercury Home) cihaz smoke'unda Mehmet (birebir Polish'te): mesh hareket etmiyor + dişli ikonu yamuk + navigasyon/toggle ✅ + **"uygulamanın her aşamasına UI'ı implemente et"** + **Görsel Çeviri'ye Google Lens tarzı overhaul** (fotoğrafta alan seç → o bölgeyi çevir).

**Yaptıklarım (analyze temiz, 196/196 test; APK BUILD EDİLMEDİ):**
- **Mesh drift animasyonu** (hg-drift keyframe'leri birebir, 17-23s, reduce-motion'lı) + **dişli fix** (sıkıştırılmış arc-flag parse sorunu — cihaz screenshot'uyla doğrulandı; Lucide geometrisi) + tüm ikon seti (~30) portlandı.
- **`hg_widgets.dart`** paylaşılan bileşen kütüphanesi (NavHeader/SerifTopBar/GradientButton/WarmupCircle/Equalizer/StatGlass/ChecklistGlass/Choice-QualityCard/Segmented/LangBar/ResultTile/WarnGlass…).
- **SmallTalk 3-adım wizard'a** birleştirildi (Diller→Yöntem→Mod; narration toggle Yöntem'de; PTT model kapısı Başlat'ta) — **eski `smalltalk_handsfree_setup_screen.dart` + `language_select_screen.dart` SİLİNDİ.** Konferans setup da wizard'a çevrildi.
- **SmallTalk canlı + Konferans canlı 5-faz restyle** (warmup dairesi, balonlar/altyazı kartları, partial bar+ekolayzer, done istatistikleri, error) — tüm session/engine mantığı aynen korundu.
- Arşivler ×2 + detay + Ayarlar + ModelsRequiredGate restyle; **(D) "Daha İyi Çevir" etiketi** uygulandı; crunch dialogları HG.

**Bıraktıklarım:** **KOD DERLENİYOR (analyze temiz, 196/196) AMA TUR YARIDA + APK YOK + CİHAZ SMOKE YOK.** Kalan işler roadmap "EN GÜNCEL (3. iş)" bölümünde sıralı: PTT split restyle → Manuel Çeviri → **Görsel Çeviri Lens overhaul (feature!)** → model_tier_selector → low_ram dialog → tema toggle kalıcılaştırma → **APK build + komple cihaz smoke**.

**Sıradaki modele not:** Hand-off kaynakları `MOBS-Hermes/_handoff_ui/` (README + `prototype/hermes-screens.jsx` §SmallTalkSplit/§ManualTranslate/§VisualOCR kalan ekranların spec'i). ⚠️ PowerShell `-replace`+`Set-Content` Türkçe UTF-8'i BOZUYOR (settings_screen baştan yazıldı) — yalnız Edit/Write kullan. ⚠️ HgGlass gerçek BackdropFilter — Poco'da jank görürsen `blur:false`. Cihazda `crunch_derisk` (8.5GB) silindi (onaylı temizlik), `vosk_en_derisk` duruyor. Mehmet kısa/net.

---

## 2026-06-12 — Claude Fable 5 — Bug taraması + 11 Haziran artıkları + UI RESTYLE TUR 1 (liquid-glass Mercury Home)

**Devraldım:** Entry (üstteki 06-10) + punch board'a YAZILMAMIŞ kesik bir 06-11 oturumu: boş-oturum-silme kodu eklenmiş (4 testi kırmış), `GeminiClient.validateKey` yazılmış ama bağlanmamış. Mehmet bu turda (1) tüm-kod bug taraması + fix, (2) Claude Design'ın UI hand-off'unun implementasyonunu istedi.

**Yaptıklarım (analyze temiz, 196/196 test, arm64 debug APK build edildi):**
- **Bug turu:** 4 kırık test boş-oturum-silme davranışına güncellendi (+3 boş-oturum testi); validateKey Ayarlar'a bağlandı (yalnız 200'de kaydet, +3 test); indirme hata yolunda açık IOSink (5 dosya); crunch progress dialog geri-tuşu kaçağı (PopScope); session start() çift-çağrı guard'ı (conference+smalltalk); duplicate VAD aboneliği (dual_vosk+streaming_mic) + `_vad.dispose()` await; FillerCleaner TR `i→İ` locale fix (+2 test, 1 beklenti düzeltildi); settings `_delete` mounted guard. Detay: roadmap "Sıradaki tur" 1. iş.
- **UI Tur 1 (hand-off: `MOBS-Hermes/_handoff_ui/`):** Mehmet kararları = Mercury + Coral + Noir şimdi + aşamalı. Tasarım sistemi kuruldu: `hg_tokens/hg_typography/hg_background/hg_glass` + `hg_icons` (fontlar `assets/fonts/`'a indirildi: Manrope + Cormorant Garamond VF; `path_drawing` eklendi). **Home Mercury'ye yeniden yazıldı** (navigasyon birebir), `hermesNoirTheme` + Home'da geçici tema toggle'ı (varsayılan açık).

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 196/196, APK build edildi AMA cihaz USB'de yoktu → kurulamadı.** **CİHAZ SMOKE (Mehmet):** (1) `adb -s cd61ba57 install -r -d build/app/outputs/flutter-apk/app-debug.apk` → Home: mesh + glass panel + serif tipografi + Türkçe karakterler (İ/ğ/ş), 4 mod + 2 klasör + Ayarlar navigasyonu, ay/güneş toggle'ı (Noir'da ESKİ ekranlar kusurlu görünebilir — bilinen, geçiş dönemi); (2) önceki turların bekleyen smoke'ları (Gemini anahtar doğrulama + crunch akışı + NLLB in-app indirme + daanzu Vosk EN).

**Sıradaki modele not:** UI Tur 2 = SmallTalk wizard + ConversationLive 5-faz (hand-off README "Screens" §2-3 + `prototype/hermes-conversation.jsx`); Tur 3 = Konferans 5-faz; Tur 4 = Manuel/OCR/Ayarlar/Arşiv; hepsi göçünce HermesColors emekli + themeMode kalıcı (şu an `hgThemeMode` notifier, Home'da toggle). HgGlass = gerçek BackdropFilter — liste-yoğun ekranda jank olursa `blur:false` parametresi var. (D) crunch etiket polish'i hâlâ açık ("Derinlemesine Çevir"→"Daha İyi Çevir"). Mehmet kısa/net.

---

## 2026-06-10 — Claude Opus 4.8 — (B) Gemini çevrimiçi crunch fallback + transkript kopyala (CİHAZSIZ KOD İŞİ)

**Devraldım:** Entry (8) — kod tamam, cihaz USB koptu, smoke bekliyordu. Mehmet bu turda cihazı sonra bağlayacak, **yemek molasına çıktı**, "vakit alacak cihazsız bir işi bitir" dedi. GH durumu (Mehmet): Gemma3 yüklü + indirme test edildi çalışıyor, NLLB 4 dosya yüklü. → Açık tek büyük cihazsız iş = **(B) düşük-RAM crunch fallback** seçildi.

**Yaptıklarım (analyze temiz, 188/188 test — +10 yeni):**
- **Yeni `gemini_key_store.dart`** (`HfTokenStore` birebir aynası, prefs `gemini_api_key`) + **`gemini_client.dart`** (`GeminiClient.generate` → `gemini-2.0-flash` REST `generateContent`, `http.post`; `GeminiException`: 400/403→geçersiz, 429→kota, boş candidates/blockReason→engellendi; `http.Client` enjekte → `MockClient` test).
- **`CrunchService` aynen yeniden kullanıldı** — `run`/`translate` enjekte edilebilir olduğu için Gemini backend olarak takıldı; chunk/reduce/başlık/özet promptları DEĞİŞMEDİ. `CrunchService.languageName` public yapıldı (çeviri prompt'u dil adı). Çevrimiçi yolda `maxCharsPerChunk`=4000/`reduceCharBudget`=8000.
- **`crunch_runner.dart`** + 2 runner (private `_CrunchProgressDialog`/`_info`'yu paylaşmak için aynı dosya): `runOnlineCrunch` (yerel model YOK → Gemini çeviri+özet+başlık → `setCrunchResult`) + `runOnlineSummarize` (hibrit: yerel NLLB çevirisini Gemini özetle → `setCrunchSummary`).
- **`conference_detail_screen.dart`:** anahtar varsa raw'da `[Gemini ile Çevir & Özetle]`, çevrildi'de `[Gemini ile Özetle]` (outline+bulut + "internet · veri Google'a gider" notu); anahtar yoksa Ayarlar ipucu; **transkript başlığına "Kopyala"** (her zaman, `Clipboard.setData`+snackbar).
- **`settings_screen.dart`:** "Çevrimiçi Özet (Gemini)" bölümü (maskeli anahtar `••••xxxx` + ekle/düzenle + gizlilik notu) + `_GeminiKeyDialog` (`_HfTokenDialog` aynası).
- 10 test: gemini_client (6: URL/body/parse + 400/429/blocked/500) + gemini_key_store (4: roundtrip/trim/sil).

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 188/188 test. APK YENİDEN BUILD EDİLMEDİ** (entry 8 APK'sı Gemini'yi içermez). **CİHAZ SMOKE BEKLİYOR (Mehmet dönünce):** Ayarlar→Gemini anahtarı yapıştır → konferans/oturum detayı → "Gemini ile Çevir & Özetle" çeviri+özet+başlık çıkıyor mu (internet) → yerel çeviri varsa "Gemini ile Özetle" hibrit → "Transkripti Kopyala" → geçersiz anahtar net hata. **+ Entry 8'in hâlâ bekleyen cihaz işleri** (daanzu push+APK kur+3 smoke; NLLB in-app indirme testi).

**Sıradaki modele not:** Mehmet dönünce ÖNCE yeni APK build + kur (`flutter build apk --debug` / `flutter run`), sonra yukarıdaki smoke. Gemini model adı tek `const` (`GeminiClient.defaultModel='gemini-2.0-flash'`) — gerekirse değişir. Global toggle YOK (anahtar varlığı butonları gate'ler). Anahtar shared_preferences düz metin (HfTokenStore ile aynı kabul, RELEASE_CHECKLIST). de-risk artıkları (🧪 crunch_derisk + vosk_en_derisk ekranları + scratch/cihaz klasörleri) hâlâ temizlenebilir. Mehmet kısa/net.

---

## 2026-06-09 (8) — Claude Opus 4.8 — SpeechService çökme fix + Crunch 2-adım + Vosk EN de-risk

**Devraldım:** Aynı oturum. Crunch (Gemma3-1B) cihazda çalışınca Mehmet 3 yeni iş verdi (plan modu → onaylı plan).

**Yaptıklarım (analyze temiz, crunch_service 9/9 test, APK build):**
- **P1 — SpeechService re-entry çökme (acil):** `vosk_streaming_controller.dart` statik `_active` nöbeti + idempotent/memoized `dispose` + `load()` önce önceki SpeechService'i **tam** dispose eder (ekran sistem geri tuşuyla kapanıp fire-and-forget dispose olsa bile yeni `load()` bekler). `initSpeechService` global tekil → "already exist" biter. `load()`'a `modelPathOverride` da eklendi (P3 için).
- **P2 — Crunch 2 adım:** `CrunchService.translateTranscript`(NLLB) + `summarize`(Gemma) ayrıldı; özet promptları **anlatı özeti** (ana hikaye/verilmek istenen düşünce/önemli noktalar) yapıldı. `repo.setCrunchTranslation`/`setCrunchSummary` (crunchedAt yalnız özet sonrası). `crunch_runner` `runDeepTranslate`+`runSummarize`. **conference_detail_screen** durum-tabanlı 2 buton (ham→Derinlemesine Çevir→çeviri görünür+Özetle→özet). Bitiş ekranları (conf/smalltalk/ptt) + arşivler artık inline crunch yapmaz → **detaya yönlendirir** ("Crunch now" kaldırıldı, satır→detay). crunch_service_test iki-faza güncellendi (9/9).
- **P3 — Vosk EN de-risk:** 🧪 `vosk_en_derisk_screen` (canlı mic + model seçici: small-0.15 baseline / daanzu / 0.22) → `VoskStreamingController.load(modelPathOverride:)`. daanzu (~922MB) alphacephei'den indirildi (hız ~15MB/s, throttle yok!) + açıldı (1.5GB, `_scratch/vosk_en_derisk/`).

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, APK build. CİHAZ USB KOPTU → push+kurulum yapılamadı.** Bağlanınca: (1) daanzu (1.5GB) push `<ext>/vosk_en_derisk/`, (2) APK kur, (3) 3 smoke: çökme (ısınma→sistem geri→tekrar gir, "already exist" ÇIKMAMALI) / crunch 2-adım (bitiş→detay→Derinlemesine Çevir→Özetle) / Vosk EN (daanzu vs small-0.15 doğruluk). Push: **PowerShell veya MSYS_NO_PATHCONV=1**.

**Sıradaki modele not:** Cihaz bağlanınca push+kur+smoke. daanzu yetmezse 0.22 (1.8GB, alphacephei) push. Kazanan EN modeli → `vosk_models.dart` `en` kaydına al (host: alphacephei hızlı, gerekirse GH). Sonra (hâlâ açık) **düşük-RAM crunch fallback: transkript kopyala + kendi Gemini API key** (Mehmet). de-risk artıkları temizlenebilir (🧪 crunch_derisk+vosk_en_derisk ekranları + cihaz/scratch klasörleri). Mehmet kısa/net.

---

## 2026-06-09 (7) — Claude Opus 4.8 — Crunch modeli de-risk → Gemma3-1B bağlandı (selfHosted GH + streamed + fromFile)

**Devraldım:** Aynı oturum. Faz B (NLLB GH-host) kodu bitti; NLLB 4 dosya release'e yüklendi. Faz B'nin LLM kısmında Phi-4 indirme sorunu (cihaz): "%70-80'de sessiz çöküyor + yetim ~3GB, app 7→10GB, sonra %0'da takılı". → Mehmet crunch için yeni de-risk istedi (≥10 aday, sırala, 3'ünü dene; 2 orta + 1 üst düzey).

**Yaptıklarım (analyze temiz, 174/174 test, APK Poco'da):**
- **Teşhis:** flutter_gemma native indirici büyük dosyada çöküyor; HF `.task` modelleri **Xet CDN**'de (dart:io TLS kırılır, NLLB'yi GH'e taşımamızın sebebi); Phi-4 3.76GB Poco 8GB'de OOM.
- **Araştırma:** litert-community kataloğu; flutter_gemma 0.13.6 `ModelType{general,gemmaIt,deepSeek,qwen,qwen3,llama,hammer,functionGemma,phi}` + `ModelFileType{task,binary,litertlm}`. Yeni modeller (Qwen3, gemma-4, gemma-3n) `.litertlm`. 10+ aday tablolandı (roadmap Polish'e detay).
- **De-risk (3+1, adb-push + 🧪 `crunch_derisk_screen.dart` → `fromFile` → gerçek crunch promptları, TR örnek):** **Gemma3-1B-IT q8 KAZANDI** (Mehmet "yeterli"). Qwen2.5-1.5B elendi (bozuk karakter+özet yerine soru), Phi-4-mini OOM çöktü, gemma-4-E2B (.litertlm) yüklendi ama `LiteRtLmJniException: Failed to invoke the compiled model` (SD860 uyumsuz).
- **Bağlama:** `LlmModelDef.crunch`=`gemma3` (yeni def, **selfHosted**=true, GH `nllb-600m-int8-v1` release URL). `llm_translation_engine.dart`: selfHosted → `_streamLlmDownload`(.part→rename, onProgress) + `generate()` `fromFile` + readiness=yerel dosya; HF tier'ları fromNetwork korundu. `_LlmManagedModel` registry artık yalnız `crunch` (Qwen/Gemma/Phi çıktı), kategori "Özet Modeli (Crunch)".

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 174/174, APK Poco'da. ENGELLEYİCİ (Mehmet'te):** `Gemma3-1B-IT_multi-prefill-seq_q8_ekv1280.task` (1005MB, `_scratch/crunch_derisk/`) → mevcut `nllb-600m-int8-v1` GH release'ine asset EKLENECEK (URL koda gömülü). Sonra cihaz testi: Ayarlar→Özet Modeli (Crunch)→Gemma3-1B in-app indir (streamed %/hız/ETA) → bir oturum crunch → kalite. **NLLB in-app indirme cihaz testi de bekliyor** (4 dosya yüklü).

**Sıradaki modele not:** İLK İŞ Mehmet GH'e Gemma3'ü yükleyince crunch cihaz testi + NLLB in-app test. Sonra **(B) düşük-RAM fallback:** transkripti kopyala + kullanıcının **kendi Gemini API key**'iyle online crunch (Ayarlar; Mehmet=Gemini). **adb push'ta MSYS_NO_PATHCONV=1 / PowerShell** (Git Bash uzak yolu `C:/Program Files/Git/...`'a çevirir). de-risk artıkları temizlenebilir (🧪 ekran + cihaz `crunch_derisk/` ~9GB + `_scratch/crunch_derisk/`). selfHosted kalıbı: yeni büyük modelleri hep GH'e koy + `fromFile`. Mehmet kısa/net.

---

## 2026-06-09 (6) — Claude Opus 4.8 — Faz B: in-app NLLB indirme (GitHub Release host)

**Devraldım:** Aynı oturum — F3b cihazda geçti, Mehmet "sıradaki işe geç" → AskUserQuestion'da **Faz B** seçildi ("github desktop yüklü"). Roadmap'in planlı büyük işleri bitmişti; Faz B son açık mühendislik kalemi (NLLB son kullanıcıda yalnız adb-push'la geliyordu = sevkiyat engeli).

**Yaptıklarım (analyze temiz, APK Poco'da):**
- `nllb_model_manager.dart`: `files` URL'leri **GitHub Release**'e bağlandı — `_releaseBase = https://github.com/Runomm/MOBS-Hermes/releases/download/nllb-600m-int8-v1`, 4 asset (encoder/decoder/decoder_with_past `_quantized.onnx` + `sentencepiece.bpe.model`). `download()` zaten streamed (`.part`→atomik rename) — değişmedi. Doc comment güncellendi (adb-push→GH Release, app-owned, FUSE yok, Xet yok).
- `_NllbManagedModel.download` (`managed_model.dart`): eşit-ağırlık `(i+p)/4` yerine **bayt-ağırlıklı** `(doneMb + p*f.sizeMb)/totalMb` → çubuk + DownloadStats hız/ETA gerçekçi (dosyalar 419/470/445/5 MB).
- F3b düzeltmesi de bu oturumda yapıldı (alttaki notlara bak): DownloadStats kümülatif ortalama + etaLabel.

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, APK Poco'da.** **ENGELLEYİCİ — MEHMET'TE:** GitHub Release web'den oluşturulacak (Desktop release yapamaz): tag **birebir** `nllb-600m-int8-v1`, 4 dosya sürükle (`Hermes/_scratch/nllb600_int8/*.onnx` + `Hermes/_scratch/sentencepiece.bpe.model`; **tokenizer.json YOK** — bozuk/kullanılmıyor; ~1.34GB tek seferlik). Yüklenince **CİHAZ TEST:** Ayarlar→Çeviri Modelleri (NMT)→NLLB-600M indir → in-app iniyor + bayt-ağırlıklı %/hız/ETA + çeviri çalışıyor mu.

**Sıradaki modele not:** Release yüklenmediyse önce onu bekle (Mehmet'e hatırlat). GitHub 302 redirect dart:io http'de otomatik izlenir — teorik olarak çalışır ama **in-app GH indirme ilk kez gerçek test** (de-risk hep adb-push'tu); inmezse redirect/TLS'e bak. Bundan sonra planlı büyük iş yok: kalan = bekleyen cihaz testleri (crunch/Phi, hands-free full(+) R1 Whisper ~466MB, OCR detaylı) + Faz 4 UI detaylı gezme/polish. Mehmet kısa/net.

## 2026-06-09 (5) — Claude Opus 4.8 — F3b (Whisper indirme ilerlemesi) + Faz 4 (UI beyazlaştırma — SON BÜYÜK İŞ)

**Devraldım:** F3 (merkezi indirme) kod tamamdı, cihaz smoke'ta Mehmet "hız/%/ETA görünmüyor" demişti → F3b doğdu. Mehmet bu turda (AskUserQuestion) **F3b + Faz 4'ü birlikte** istedi (cihaz testi gate'i bilinçli atlandı).

**Yaptıklarım (analyze temiz, 169/169 test, arm64 debug APK build):**
- **F3b:** `managed_model.dart` `_WhisperModel.download` → `whisper_ggml` consolidate (ilerleme yok) yerine **NLLB/Vosk streamed-http kalıbı** (`_model.modelUri`→`.part`→atomik rename, byte sayacı + onProgress). `supportsProgress=false→true`. Ayarlar UI değişmedi — `DownloadStats`+`sizeMb`(466) zaten vardı, otomatik %/hız/ETA. ML Kit imkânsız (GMS), boyut+"indiriliyor…" kalır.
- **Faz 4:** Yeni `lib/core/theme/app_theme.dart` (`HermesColors` kanonik palet + `hermesLightTheme` global ThemeData: appBar/card/input/divider/text). `conference_theme.dart` `ConferenceColors`→HermesColors delege + `ConferenceTheme`→hermesLightTheme. `main.dart` `theme=hermesLightTheme` (dark blok kalktı) + status bar ikonları koyu. Yeni `lib/features/shared/hermes_card.dart` (`HermesCard`); home `_ModeCard` silindi→HermesCard. Koyu→HermesColors çevrilen: home, Manuel (main.dart), language_select, model_tier_selector, settings, ocr_translate, push_to_talk (üst-yarı 180°+şeffaf tap korundu; yeşil→success), **models_required_gate** (beyaza-yakın metin görünmez oluyordu — kritik fix). SmallTalk (4) + Konferans ekranları **zaten** ConferenceColors'la açıktı → delege ile otomatik. 🧪 dev/test dokunulmadı.

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 169/169 test, APK build.** **APK Poco'ya KURULAMADI — cihaz USB'de değildi** (`adb devices` boş). **CİHAZ SMOKE BEKLİYOR (Mehmet, Poco bağlanınca):** (1) F3b — Ayarlar→Whisper small indir → %/hız/ETA görünüyor mu; (2) Faz 4 — tüm kullanıcı modları açık/temiz tasarımda mı, kontrast, Bas Konuş 180°, status bar ikon kontrastı. Kurulum: `adb -s cd61ba57 install -r -d build/app/outputs/flutter-apk/app-debug.apk` (adb PATH'te değil → `C:\Users\mehon\AppData\Local\Android\Sdk\platform-tools`).

**Sıradaki modele not:** **Roadmap'in planlı büyük işleri BİTTİ** — F3b + Faz 4 sonuncuydu. Sonrası: cihaz smoke + polish + (açık) **Faz B in-app indirme host'u** (NLLB int8'i GitHub Release'e → `nllb_model_manager.dart` URL'leri; şu an adb-push). Bekleyen cihaz testleri: F3 merkezi indirme smoke, hands-free full(+) (R1 — Whisper ~466MB), crunch (Phi kurulu olmalı), OCR detaylı. **NOT:** HermesColors tek-kaynak; yeni ekranlarda doğrudan onu kullan, ConferenceColors artık alias. Mehmet kısa/net.

---

## 2026-06-09 (4) — Claude Opus 4.8 — F3: Merkezi İndirme (tüm indirmeler Ayarlar'dan)

**Devraldım:** Aynı gün (alttaki) F2 cihazda geçti. Mehmet yeni yön verdi (birebir Polish'te): "gözümüzün gördüğü her yere indirme ekranı koymayacağız, tüm indirmeler Ayarlar'dan; model yoksa Ayarlar'a yönlendir; Ayarlar'da detaylı indirme (hız/boyut/% vb.)". Mehmet kararları (AskUserQuestion): önce F3 sonra Faz 4 UI; gate = mesaj + "Ayarları Aç" buton + eksik model adları.

**Yaptıklarım (analyze temiz, 169/169 test — 165 + 4 yeni):**
- **Yeni `models_required_gate.dart`** (`ModelsRequiredGate`): eksik model adları + "Ayarları Aç" (→ `SettingsScreen`, dönünce `onRecheck()` ile yeniden kontrol) + "Geri". Tek yeniden-kullanılan kapı.
- **İndirme kapıları KALDIRILDI:** `model_tier_selector.dart` (`_download`/ilerleme/token alanı çıktı; readiness + "Ayarları Aç" CTA kaldı; `onChanged` imzası korundu, token hep null). `conference_screen.dart` (`needsDownload`/`downloading`→`needsModels` gate; `_checkModel` eksik-isim üretir). `smalltalk_screen.dart` (aynı; fast→Vosk×2+MLKit / full→Whisper+MLKit / full+→Whisper+NLLB eksik-isim listesi). `main.dart` Manuel (`_handleLanguageChange` inline MLKit dialog→snackbar yönlendirme; `_showDownloadDialog` silindi).
- **Ayarlar indirme UI'si zenginleşti:** yeni saf `download_stats.dart` (`DownloadStats.from(prevFrac,newFrac,dtMs,sizeMb)` → hız/inen/toplam/ETA) + `ManagedModel.sizeMb` (her model override). `settings_screen` `_download` Stopwatch ile tick başına hesaplar; çubuk altında "{inen}/{toplam} MB · {hız} MB/s · ~{eta}s" + %. `supportsProgress=false` (Whisper/MLKit) → boyut + "indiriliyor…".
- **Dokunulmadı:** 🧪 dev/test ekranları (`vosk_test`, `llm_translate_test`) kendi kapılarını korur.
- **4 yeni test:** `download_stats_test` (hesap doğruluğu/null durumları).

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 169/169 test, APK Poco'da.** **CİHAZ SMOKE (Mehmet birebir): "hız, % ve ETA görünmüyor"** (boyut görünüyor). **TEŞHİS:** indirdiği model ilerleme vermeyen tipte (ML Kit/Whisper). hız/%/ETA yalnız **Vosk/NLLB/LLM**'de çalışır (http streamed). **ML Kit** = GMS, progress yok (imkânsız). **Whisper** = `whisper_ggml.downloadModel` consolidate, progress yok. Gate/yönlendirme/merkezi indirme yapısı çalışıyor; eksik olan yalnız ML Kit/Whisper progress'i.

**Sıradaki modele not — İLK İŞ F3b (küçük):** Whisper'ı `whisper_ggml` yerine kendi streamed `http` indirmemizle indir (`_WhisperModel.download` → `model.modelUri` byte byte oku + onProgress, `getPath`'e yaz; Vosk/NLLB kalıbı) → %/hız/ETA çıksın. ML Kit imkânsız (boyut + "indiriliyor…" kalır — kullanıcıya bunu açıkla veya kabul et). Sonra **SON BÜYÜK İŞ = Faz 4 — UI beyazlaştırma** (Konferans tasarımı app geneline; `app_theme.dart` global + paylaşılan widget + kullanıcı ekranları; 🧪 hariç). Plan: `~/.claude/plans/warm-stirring-planet.md`. NOT: Manuel translate hâlâ ensureModelLoaded ile sessiz (timeout-korumalı) indirme dener — görünmez, "indirme ekranı" değil; gerekirse readiness-gate'le.

---

## 2026-06-09 (3) — Claude Opus 4.8 — F2: Hands-free 3-katman (fast/full/full+)

**Devraldım:** Aynı gün (alttaki) F1 cihazda geçti. Mehmet "devam et" → sıradaki F2. Spec Polish'te birebir: hands-free fast=ml kit+vosk / full=whisper+ml kit / full+=whisper+nllb.

**Yaptıklarım (analyze temiz, 165/165 test — 159 + 6 yeni):**
- **`SessionQuality` 2→3:** `fullPlus` eklendi (`conversation_repository.dart`). DB `quality` string (`name`) → geriye uyumlu, **migration YOK**; `fromDbValue`'ya `'fullPlus'` case'i. Manager/Konferans yalnız fast/full görür (fullPlus sadece SmallTalk).
- **`smalltalk_screen.dart` tier-tabanlı motor seçimi:** top-level saf `handsFreeUsesWhisper(q)=(q!=fast)` + `handsFreeUsesNllb(q)=(q==fullPlus)`. `_isFast` kalktı. `_checkModels` (STT: Whisper? / çeviri tier: NLLB? ; full+ NLLB pre-install net hata), `_download` (tek akış: fast→Vosk; fast+full→MLKit paketleri; full/full+→Whisper load'da), `_warmUp` (transcriber+translation tier'a göre), download-gate metni güncellendi.
- **Setup 3 kart** (`smalltalk_handsfree_setup_screen.dart`): Hızlı(Vosk+MLKit)/Tam(Whisper+MLKit)/Tam+(Whisper+NLLB). **F1 RAM uyarısı koşulu `full`→`fullPlus`** (NLLB yalnız full+; full=Whisper+MLKit ağır değil).
- **`SmallTalkStreamingSession.quality`** opsiyonel param (default full) → DB'ye gerçek katman yazılır (eskiden fast bile 'full' yazıyordu). SmallTalkScreen `widget.quality` geçer.
- **6 yeni test:** repository fullPlus roundtrip (dbValue+fromDbValue) + `smalltalk_handsfree_tier_test` (usesWhisper/usesNllb 3 değer).

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 165/165 test, arm64 debug APK Poco'ya KURULDU** (`adb install -r -d`, Success). **CİHAZ SMOKE bekliyor (Mehmet):** SmallTalk→Hands-free→**3 seçenek** çıkmalı. fast=Vosk+MLKit (mevcut gibi); full=Whisper+MLKit (NLLB uyarısı YOK, Whisper inince çalışır); full+=Whisper+NLLB (düşük-RAM uyarısı ÇIKAR + NLLB kurulu değilse net hata). **R1:** hands-free full(+) tam test Whisper ~466MB indirme ister (internet olunca).

**Sıradaki modele not:** Önce Mehmet smoke. Sonra **son büyük iş = Faz 4 — UI beyazlaştırma:** Konferans tasarım dilini app geneline (salt renk değil, genel dizayn) — `ConferenceColors/Theme`→`lib/core/theme/app_theme.dart` global + paylaşılan widget'lar + kullanıcı ekranları (home/language_select/model_tier_selector/push_to_talk/ocr/settings/manuel); dev/test 🧪 ekranları hariç. Plan: `~/.claude/plans/warm-stirring-planet.md`. Mehmet kısa/net.

---

## 2026-06-09 (2) — Claude Opus 4.8 — F1: Düşük-RAM (OOM) uyarısı + ML Kit cihazda çalışır onayı

**Devraldım:** Aynı gün (alttaki entry) ML Kit timeout kodu + APK Poco'da. Mehmet smoke: **"ML kit artık çalışıyor. hata mesajını test edemedim ama önemsiz, sıradaki işten devam et"** → ML Kit/GMS artık PARK değil (çalışıyor). Sıradaki = F1 (RAM/OOM uyarısı).

**Yaptıklarım (analyze temiz, 159/159 test — 154 + 5 yeni):**
- **`device_info_plus` eklendi** (Mehmet kararı: pub paketi OK; iOS dahil RAM, **biz native kod yazmıyoruz** — MethodChannel+Swift'ten kaçınıldı).
- **`lib/core/services/device_memory.dart`:** `DeviceMemory.totalRamMb()` (Android/iOS `physicalRamSize`, hata→null) + saf `isLowRam(mb,{threshold})` + `kLowRamThresholdMb = 11*1024` (≈11GB; Poco 8GB→~7.4GB uyarılır, 12GB+ uyarılmaz). 5 saf test.
- **`lib/features/shared/low_ram_warning.dart`:** `confirmHeavyTierOnLowRam(context,{memory})` → düşük-RAM'de AlertDialog ("Cihaz belleği düşük ~X GB… Yine de Akıllı kullanılsın mı?" İptal/Yine de kullan); yüksek/bilinmeyen RAM → sessiz `true` (akış normal).
- **3 canlı NLLB giriş noktasına bağlandı** (kullanıcı "Akıllı/full" seçince, vazgeçerse fast'te kal/navigasyon iptal): Bas Konuş `language_select_screen._setQuality(full)`, Konferans `conference_setup_screen._go(nllb)`, SmallTalk hands-free `smalltalk_handsfree_setup_screen._go(full)`.

**Bıraktıklarım:** **F1 TAMAMEN BİTTİ — kod + cihaz.** analyze temiz, 159/159 test, APK Poco'da, **CİHAZ SMOKE ✅ GEÇTİ** (Mehmet birebir: "her şey belirttiğin gibi çalışıyor" — 3 modda uyarı + fast'te uyarı yok). Açık kod işi yok.

**Sıradaki modele not:** Önce Mehmet smoke + APK kurulumunu teyit et. Sonra **F2 — Hands-free 3-katman** (fast=MLKit+Vosk / full=Whisper+MLKit / full+=Whisper+NLLB; `smalltalk_handsfree_setup` 2→3 seçenek + `smalltalk_screen` motor seçimi; `SessionQuality` 2→3 değer). **NOT:** F2 SmallTalk full'ü full+'a taşıyınca, F1 RAM uyarısının `_go` koşulunu yeni "full+" değerine güncelle (şu an `quality==full`). Sonra **Faz 4 — UI beyazlaştırma**. Plan: `~/.claude/plans/warm-stirring-planet.md`. Mehmet kısa/net.

---

## 2026-06-09 — Claude Opus 4.8 — ML Kit indirme TIMEOUT + net hata UX (#1 kod kısmı) → kısa, odaklı oturum

**Devraldım:** Dünkü entry (alttaki) "yarın ilk işler" listesi #1 = ML Kit indirmesine timeout + net hata UX (sonsuz "indiriliyor" yerine). NLLB tüm yüzeylerde + readiness audit zaten TAMAM'dı.

**Yaptıklarım (analyze temiz, 154/154 test — önceki 150 + 4 yeni):**
- **`google_mlkit_engine.dart` timeout sargısı:** `kMlKitDownloadTimeout` (90sn — ~30MB paket yavaş mobil veride bile ~1dk'da iner, aşılırsa GMS getiremiyor) + `MlKitDownloadException` (toString=mesaj, kullanıcıyı **NLLB**'ye yönlendirir) + saf/test-edilebilir top-level `runMlKitDownloadWithTimeout(download, {timeout})` (yalnız `TimeoutException`'ı sarar; timeout-dışı hatalar propagate). `ensureModelLoaded` (2 çağrı, **canlı çeviri de korunur**) + `downloadLanguage` sarıldı.
- **UI değişikliği GEREKMEDİ:** tüm indirme/canlı yüzeyler zaten `catch (e)`→`$e` gösteriyor (selector kırmızı `_error`, main `_status`, conference/smalltalk `_fail(e)`) → temiz mesaj otomatik akıyor. Motor tek nokta → tüm yüzeyler korundu.
- **Yeni test** `test/core/engines/translation/google_mlkit_engine_test.dart` (4): timeout→exception, mesaj NLLB içerir, başarı sorunsuz, timeout-dışı hata propagate. (ML Kit platform → saf helper test ediliyor.)

**Bıraktıklarım:** **KOD TAMAM, analyze temiz, 154/154 test, arm64 debug APK Poco'ya KURULDU** (`adb install -r -d`, Success). **CİHAZ SMOKE bekliyor (Mehmet):** ML Kit (Hızlı) indir → ~90sn sonra sonsuz dönme yerine net "...NLLB seçin" hatası + NLLB'ye geçince çalışır. **Mehmet paralel GMS testi:** Google Çeviri'de TR offline indir + MIUI pil "kısıtlama yok".

**Sıradaki modele not:** Önce Mehmet'in smoke testini bekle. Sonra kalan 3 bekleyen iş (sırayla): **F1 — RAM/OOM uyarısı** (Bas Konuş Akıllı Poco'da signal 9 çöküyor; `device_info_plus` yok→ekle veya MethodChannel, full/NLLB öncesi düşük-RAM'de uyar+izin ver), **F2 — Hands-free 3-katman** (fast=MLKit+Vosk/full=Whisper+MLKit/full+=Whisper+NLLB), **Faz 4 — UI beyazlaştırma**. Plan: `~/.claude/plans/warm-stirring-planet.md`. Mehmet kısa/net.

---

## 2026-06-08 (akşam, DEVAM) — Claude Opus 4.8 — Poco cihaz testi + ML Kit readiness audit + ML Kit/GMS indirme teşhisi (KOD DEĞİL, cihaz GMS sorunu) → günü burada bıraktık

**Devraldım:** Aynı oturumun devamı (alttaki entry: NLLB tüm yüzeylere bağlandı + int8 Poco'ya push edildi). Mehmet Poco'da test etti, geri bildirim geldi, ona göre bug-fix turu yaptık.

**Mehmet'in Poco cihaz testi (birebir roadmap Polish'te):** NLLB de-risk ekranı ✅; **Manuel ML Kit çalışmıyor**; **Bas Konuş Akıllı app çöküyor (=OOM, logcat signal 9)**; **Konferans Akıllı çalışıyor ama aşırı yavaş** → cihaz kapasitesine göre tavsiye gerek (F1); **Konferans fast ML Kit "no existing model file"**; **Hands-free full test edilemedi** (~400MB Whisper indirme + internet yetersiz → R1 sonra hatırlat); **YENİ F2:** hands-free 3-katman = fast(MLKit+Vosk) / full(Whisper+MLKit) / full+(Whisper+NLLB).

**Yaptıklarım (analyze temiz, 150/150 test, APK Poco'da):**
- **ML Kit readiness audit (Mehmet: "olmayan modelleri mevcut zannediyorlar sürekli"):** Kök neden — `ModelTierSelector` MLKit'i dil-paketi kontrolü YAPMADAN "hazır" sayıyordu; language_select fast `_modelReady=true` hardcode; conference/smalltalk sadece STT gate'liyordu. **FIX:** `translation_tier.dart` `isTierReady(tier, src, tgt)` helper (MLKit iki paket / NLLB 4 dosya / LLM model; auto-dil ArgumentError yutar). `ModelTierSelector`'a `sourceLang/targetLang` + gerçek MLKit kontrolü + MLKit indirme branch + didUpdateWidget. language_select fast/full ikisi de selector ile gate'li. conference_screen + smalltalk_screen `_checkModel/_download`'a MLKit paket kapısı. main.dart + ocr çağrıları dillerle güncellendi.
- **ML Kit WiFi fix:** `GoogleMLKitEngine.downloadModel` varsayılan `isWifiRequired:true` → mobil veride indirme başlamıyor → `isWifiRequired:false` yaptım. (AMA asıl sorun bu değilmiş, aşağıya bak.)

**🔑 ML Kit ÇÖKMEZ AMA İNMEZ — KESİN TEŞHİS (KOD DEĞİL, CİHAZ/GMS):** WiFi fix sonrası hâlâ `MlKitException: no existing model file`. Derin teşhis:
- Cihazda `run-as ... ls no_backup/com.google.mlkit.translate.models` → **dizin BOŞ** (sadece boş `temp/`). 
- `com.google.mlkit.translate.download_manager.xml` → 3 dil **denenmiş** kayıtlı: en_es/en_fr = `redirector.gvt1.com`, **en_tr = `dl.google.com`**.
- PC'den (aynı lokasyon) her iki CDN **erişilebilir** (curl 200/302) → ağ engeli YOK.
- Mehmet 40+ dk, WiFi açık, önde tuttu → dizin yine boş.
- **Sonuç:** ML Kit çeviri modelini TAMAMEN telefonun **Google Play Services (GMS)** indirir; biz sadece tetikleriz. Poco/MIUI'de GMS indirmeyi başlatıp **tamamlamıyor** (büyük olasılıkla MIUI agresif arka plan/pil kısıtı GMS'i öldürüyor). Modeller **paketlenemez/elle atılamaz**. Yani ML Kit, her cihazın GMS sağlığına + Google CDN'e bağımlı → Mehmet'in cihazında güvenilmez. **NLLB tamamen offline çalışıyor (GMS'siz)** → asıl güvenilir yol o.

**Mehmet kararı:** "Burada bırakalım, yarın aynen buradan devam." ML Kit/GMS PARK EDİLDİ (kod doğru, cihaz sorunu).

**Bıraktıklarım:** **KOD DURUMU: NLLB tüm yüzeylerde + ML Kit readiness audit + WiFi fix = TAMAM, analyze temiz, 150/150 test, APK Poco'da. AÇIK KOD İŞİ YOK ama 4 bekleyen var.** ML Kit Mehmet'in cihazında inmiyor (GMS) → onun cihazında NLLB kullanılır; ML Kit normal/sağlıklı-GMS cihazlarda çalışır.

**Sıradaki modele not — YARIN İLK İŞLER (öncelik sırasıyla):**
1. **ML Kit/GMS testi (Mehmet):** Google Çeviri uygulamasında TR offline indir + MIUI pil "kısıtlama yok" (GMS + Hermes) → tekrar dene. İnerse MIUI ayarı çözüm; inmezse cihaz GMS. **Sonra kodda:** ML Kit indirmesine **timeout + net hata** ("Google Play modeli indiremedi, NLLB kullan") ekle (sonsuz "indiriliyor" yerine) — bu küçük iş henüz YAPILMADI.
2. **F1 — Cihaz RAM uyarısı (OOM):** full/NLLB seçilince düşük-RAM'de "uyar + yine de izin ver" dialogu (Bas Konuş OOM). `device_info_plus` (yok, eklenecek) ile RAM tespiti veya MainActivity'ye küçük MethodChannel. Eşik öneri: <~11-12GB uyar. **YAPILMADI.**
3. **F2 — Hands-free 3-katman:** fast=MLKit+Vosk / full=Whisper+MLKit / full+=Whisper+NLLB. `smalltalk_handsfree_setup` 2→3 seçenek + `smalltalk_screen` motor seçimi (`SessionQuality` 2-değerli → 3 katmana genişlet). **YAPILMADI.**
4. **Faz 4 — UI:** Konferans tasarım dilini app geneline (Mehmet: "sadece beyaza boya değil, genel dizayn"). `ConferenceColors/Theme`→`lib/core/theme/app_theme.dart` global + paylaşılan widget'lar + kullanıcı ekranları (dev/test hariç). **YAPILMADI.**
- **Bekleyen cihaz testleri:** crunch (Phi kurulu olmalı), Hands-free full (R1, internet olunca), OCR detaylı (Mehmet ayrıca).
- Plan: `~/.claude/plans/indexed-zooming-wilkinson.md`. `_scratch` proje kökünde (`Hermes/_scratch`). NLLB int8 zaten Poco'da app-owned.

---

## 2026-06-08 — Claude Opus 4.8 — NLLB TÜM YÜZEYLERE: canlı full (Konferans/Hands-free) + crunch final çeviri (NLLB→Phi) + Poco'ya doğru int8 push

**Devraldım:** NLLB yalnız Bas Konuş Akıllı/Manuel/OCR/Ayarlar'daydı. Mehmet tam matris istedi (birebir): her modda **fast=MLKit / full=NLLB canlı**; oturum sonu crunch'ta **NLLB final çeviri → Phi özet** (Phi zaten `crunch=phi4`); ML Kit her yerde korunur (düşük-RAM). Ayrıca: NLLB wiring'den SONRA tüm kullanıcı ekranlarını Konferans'ın beyaz tasarım diline getir (Faz 4, henüz YAPILMADI). Plan: `~/.claude/plans/indexed-zooming-wilkinson.md`.

**Yaptıklarım (analyze temiz, 150/150 test, arm64 APK Poco'da kurulu):**
- **Faz 1 — Crunch NLLB:** `crunch_service.dart` iki faza ayrıldı — Faz A tüm parçaları **NLLB** (`translate` enjekte) ile çevir → `afterTranslate` callback ile NLLB `dispose` (RAM) → Faz B **Phi** (`run`) not/reduce/title. `crunch_runner.dart` hem NLLB hem Phi hazırlık kontrolü + iki motor wiring (`translate:`→NllbEngine, `run:`→LlmHost phi, `afterTranslate:`→nllb.dispose). Test güncellendi (faz sırası + afterTranslate doğrulanıyor).
- **Faz 2 — Konferans fast/full:** `conference_setup_screen.dart`'a 3. adım **quality** (Hızlı=MLKit / Akıllı=NLLB). `conference_screen.dart` `tier` param + `createTranslationEngine(tier)` (hardcoded MLKit kalktı) + NLLB upfront hazırlık kapısı.
- **Faz 3 — Hands-free full:** `smalltalk_screen.dart` `_warmUp` `widget._isFast ? MLKit : NllbTranslationEngine()` + NLLB kapısı. (Bas Konuş canlı zaten NLLB ✅, OCR/Manuel ✅.)
- **Poco DAĞITIM FIX (önemli):** Poco'daki NLLB **eskiydi** (06-06: `tokenizer.json` + fp16 onnx 772/1136/1085MB) → kod `sentencepiece.bpe.model` + int8 (419/470/445) bekliyor → "hazır" görünmezdi. Doğru int8'ler **`Hermes/_scratch/nllb600_int8/`** + `Hermes/_scratch/sentencepiece.bpe.model`'de bulundu (proje kökü, `hermes/` değil!), `adb push` ile Poco'ya yazıldı (üzerine). Artık NLLB Poco'da hazır.

**Bıraktıklarım:** **KOD TAMAM + APK Poco'da + NLLB int8 Poco'da hazır. CİHAZ TESTİ BEKLİYOR (Mehmet).** Test matrisi: (1) Bas Konuş Akıllı / Manuel NLLB / OCR full re-verify, (2) **Konferans full** canlı NLLB + RAM(NLLB+Vosk) OOM?, (3) **Hands-free full** Whisper+NLLB, (4) **crunch** her modda NLLB çeviri+Phi özet — **Phi kurulu olmalı** (Ayarlar→Çeviri Modelleri, yoksa "Özet modeli gerekli" der). fast modlar (MLKit) de denenli. **OCR detaylı testi de bekliyor** (Mehmet ayrıca yapacak).

**Sıradaki modele not:** İLK İŞ Mehmet'in cihaz testini bekle. Sonra **Faz 4 (UI beyazlaştırma) HENÜZ BAŞLAMADI** — `ConferenceColors/Theme`→`lib/core/theme/app_theme.dart` global + paylaşılan widget'lar + kullanıcı ekranları (home/language_select/model_tier_selector/push_to_talk/smalltalk_screen/ocr/settings/manuel) Konferans tasarım diline; dev/test 🧪 ekranları hariç. Mehmet: "sadece beyaza boya değil, genel dizaynı kullan". **KRİTİK:** crunch RAM = NLLB→dispose→Phi (Poco 8GB); canlı full NLLB+ASR eşzamanlı OOM riski cihaz testinde görülecek. `_scratch` proje kökünde (`Hermes/_scratch`, gitignore). Faz B (in-app indirme host'u, GH Release) hâlâ açık — URL'ler boş, model adb-push'la geliyor.

---

## 2026-06-07 (gece) — Claude Opus 4.8 — NLLB ANA AKIŞA BAĞLANDI (Bas Konuş/Manuel/OCR/Ayarlar) + in-app indirme altyapısı

**Devraldım:** Aynı gün NLLB-600M cihazda çözülmüştü (int8 + tokenizer fix, S25'te "kalite ve hız harika") ama yalnız 🧪 de-risk ekranındaydı. Mehmet: ana akışa bağla (her yere) + in-app indirmeyi çöz.

**Yaptıklarım (analyze temiz, 150/150 test, S25'e kuruldu):**
- **`NllbTranslationEngine`** (`lib/core/engines/translation/nllb_translation_engine.dart`): `TranslationEngine` wrapper, **paylaşılan static singleton** (1.3GB tek kopya), BCP-47↔NLLB kod eşleme (tr→tur_Latn…), context yok sayar (saf NMT), readiness=`NllbModelManager.allDownloaded()`.
- **`TranslationTier.nllb`** eklendi (`translation_tier.dart`): label 'NLLB', isLlm=false, ~1334MB; `createTranslationEngine`→NllbTranslationEngine. **"Akıllı"=NLLB** (LLM çeviri bırakıldı; gemma/qwen enum'da kalır, crunch için).
- **`ModelTierSelector` genelleştirildi:** `showMlkit` bool → **`tiers` listesi** (varsayılan [mlkit,nllb]); readiness/indirme tier-tipine göre (mlkit hep hazır / nllb→NllbModelManager + 4-dosya birleşik %ilerleme / llm→mevcut+token). Çağıranlar güncellendi.
- **Bağlandı:** Bas Konuş (`language_select` full→NLLB), **Manuel** (`main.dart` TranslationTestScreen'e selector + `createTranslationEngine`), OCR (varsayılan selector zaten), **Ayarlar** (`managed_model.dart` `_NllbManagedModel`, kategori "Çeviri Modelleri (NMT)").
- **CİHAZ (Mehmet birebir):** "her şey yerli yerinde görünüyor ancak son detaylı bir test daha yaparız daha sonra" → görsel onay var, **detaylı çeviri/crash testi BEKLİYOR**.

**Bıraktıklarım:** **NLLB Bas Konuş/Manuel/OCR/Ayarlar'da KOD TAMAM + S25'te kurulu** (model zaten cihazda app-owned → "hazır" görünüyor). **AÇIK İŞLER (sıradaki tur):** (1) **Mehmet'in detaylı cihaz testi** (4 yüzeyde NLLB çeviri kalite+crash). (2) **Konferans + SmallTalk canlı streaming** henüz NLLB'siz (hâlâ hardcoded `GoogleMLKitEngine()` `conference_screen.dart:136`+`smalltalk_screen.dart:156`) — setup'a kalite seçimi + warmup'ta NLLB indirme kapısı + session'a engine geç. **ÖNERİM:** canlı=MLKit-hızlı kalsın (kasıtlı), NLLB'yi **crunch'ın "tam çeviri"sine** koy (`crunch_runner.dart` Qwen→NLLB) — daha değerli. Mehmet'e sor. (3) **Faz B — in-app indirme host'u:** model GitHub Release'e yüklenmeli (Mehmet, `gh` kurulu değil → web'den repo `Runomm/MOBS-Hermes`); sonra `NllbModelManager.files` URL'leri girilip `download()` aktif (şu an URL='' adb-push'a bağlı). App indirince app-owned olur (FUSE sorunu yok).

**Sıradaki modele not:** İLK İŞ Mehmet'in detaylı testini bekle. **KRİTİK (önceki entry'den):** dart_sentencepiece JSON-loader NLLB'de BOZUK→ham `.model`+offset; on-device fp16=OOM→int8; Android15 adb-push=app-owned yap (run-as). Streaming/crunch bağlama + Faz B host kaldı. Mehmet'in asıl cihazı Poco 8GB (S25 ödünç). `_scratch/` repo-dışı. Plan: `~/.claude/plans/joyful-knitting-lynx.md`. Token bu turda bitti, subset kuruldu+test edildi (görsel ✓).

---

## 2026-06-07 (akşam) — Claude Opus 4.8 — ✅ NLLB-600M CİHAZDA ÇÖZÜLDÜ — gerçek bug = BOZUK TOKENIZER (S25 Ultra: "kalite ve hız harika")

**Devraldım:** Aynı gün OCR + NLLB PC testi bitmişti. Mehmet arkadaşının **S25 Ultra**'sını ödünç aldı: "NLLB mobilde PC kadar iyi değildi, implementasyon hatalıydı, düzgün/tam yap + S25'te test."

**🔑 GERÇEK KÖK NEDEN (uzun de-risk turundan sonra bulundu):** Sorun **int8 değil, TOKENIZER**'dı. `dart_sentencepiece_tokenizer`'ın `tokenizer.json` loader'ı NLLB'yi yanlış parçalıyor (bol `<unk>`) → model çöp girdi → "orta" kalite. **Çözüm: ham `sentencepiece.bpe.model` + `fromModelFile` + (+1 fairseq offset).** PC parite testi: SP+1 == HF birebir; JSON-loader ≠ HF.

**Yaptıklarım (analyze temiz, 147/147 test):**
- **Teşhis zinciri (hepsi `_scratch/`, gitignore):** (1) PC decode teşhisi: greedy ≈ beam → decode sorun değil. (2) fp16 export + kalite doğrulama (Dart decode'unu onnxruntime'da taklit) → fp16 = PC. (3) fp16 ORT yükleme crash'i (`SimplifiedLayerNormFusion`) → offline ORT-BASIC optimize ile çözüldü. (4) **Cihazda fp16 OOM** (3.7GB; S25 12GB bile LMK öldürdü) → fp16 elendi. (5) int8 kalite ölçümü → **int8 ≈ fp16 ≈ PC** (hatta bazı yerde daha iyi), ~0.3s. (6) **Tokenizer parite testi → BUG bulundu** (JSON-loader çöp, SP-model+offset doğru).
- **Kalıcı FIX:** `nllb_onnx_translator.dart` ham SP model + offset + sabit `_langIds` haritası + decode HF→SP(-1). `nllb_model_manager.dart` → int8 quantized + sp model (~1.3GB). `nllb_test_screen.dart` param `spModelPath`.
- **⚠️ Android 15 FUSE tuzağı:** adb-push edilen dosyalar shell-sahipli → app **göremez** ("indir" der). **run-as ile app-sahipli kopya** şart (klasör + dosyalar u0_a146). Yöntem: tmp push → chmod 755 → `run-as cp` app dizinine.
- **Cihaz dağıtımı:** int8+sp app-owned push (run-as), tokenizer-fix'li arm64 APK kuruldu. **CİHAZ TESTİ GEÇTİ (Mehmet birebir): "kalite ve hız harika".**

**Bıraktıklarım:** **NLLB-600M cihazda PC kalitesinde çalışıyor (int8, doğru tokenizer, S25 Ultra).** Açık KOD işi yok ama **NLLB ana akışa BAĞLI DEĞİL** — yalnız 🧪 de-risk ekranı. Sıradaki büyük iş: NLLB'yi `TranslationEngine`'e wrap + fast/full'e bağla + **son-kullanıcı model dağıtımı** (de-risk'te adb-push kullandık; gerçek kullanıcıda `download()` ile app kendi indirmeli → app-owned otomatik çözülür, ama Xet CDN engeli var → çözüm gerek).

**Sıradaki modele not:** İLK İŞ: Mehmet NLLB'yi ana akışa bağlamak ister mi sor (yoksa de-risk yeterli olabilir). **KRİTİK BİLGİLER:** (1) dart_sentencepiece JSON-loader NLLB'de BOZUK → her zaman ham `.model`+offset kullan. (2) on-device CPU'da fp16 ≈ fp32 RAM (OOM) → **int8 kullan** (Poco 8GB gerçeği). (3) Android 15+ (S25): adb-push dosyaları app-sahipli yap (run-as), yoksa app görmez — Poco/eski Android'de bu sorun yok. (4) int8 kalite = fp16 = PC (ölçüldü). Mehmet'in asıl cihazı Poco X3 Pro 8GB; S25 ödünç/geçici test cihazı. `_scratch/` repo-dışı silinebilir. Çok uzun oturum (OCR + NLLB PC + NLLB cihaz tam zincir).

---

## 2026-06-07 — Claude Opus 4.8 — GÖRSEL ÇEVİRİ (OCR) MODU Faz 1 + NLLB PC kalite testi (cihazsız oturum)

**Devraldım:** Opus-MT tr→en de-risk cihazda test bekliyordu (ONNX pivot). Ama Mehmet **Poco'yu yanında getirmemiş** → cihaz testi yapılamadı; cihazsız iki yeni hedef verdi: (1) NLLB 600M+1.3B'yi PC'de çevir kaliteyi gör, (2) yeni mod: localde AI ile OCR çeviri.

**Yaptıklarım (plan onaylı, analyze temiz, 147/147 test = 143 + 4 OCR):**
- **NLLB PC kalite testi (Bölüm A):** `_scratch/nllb_quality_test.py` (transformers fp32/CPU — torch CPU-only doğrulandı; modeller HF cache'e indi 600M+1.3B). 14 turist/Erasmus cümlesi çift yönlü tr↔en → `_scratch/nllb_quality_results.md` yan yana tablo. `_scratch/` gitignore'lu (throwaway). **BULGU:** **1.3B daha sadık** (clause düşürmez); **600M bazen tüm cümleyi atlıyor** (#13 "Please keep the change" → tamamen kayboldu, #9 "check in" düştü); ikisi de deyimde kusurlu ("keep the change"→"değişikliği al"). fp32=kalite tavanı, 1.3B OOM gerçeği değişmedi.
- **Görsel Çeviri (OCR) modu — Faz 1 (Bölüm B):** Mehmet kararı OCR=ML Kit Text Recognition (cihaz-içi/offline/Latin gömülü), akış foto/galeri Faz 1 + canlı kamera Faz 2.
  - Strategy Pattern: `lib/core/engines/ocr/text_recognizer_engine.dart` (`TextRecognizerEngine`+`OcrResult`+`OcrLine`) + `mlkit_text_recognizer.dart` (`MlKitTextRecognizer`, Latin script).
  - `lib/features/ocr_translate/ocr_translate_screen.dart` — kaynak("Otomatik algıla"=`MlKitLanguageDetector`)→hedef + `ModelTierSelector` → "Fotoğraf çek"/"Galeri" (image_picker) → recognize → `createTranslationEngine(tier)` çevir → orijinal+çeviri kart (kopyala). Boş OCR/dil-tespiti-fail → OK'li dialog. Bağımlılıklar enjekte edilebilir (typedef `ImagePickFn`/`TranslationEngineFactory` + recognizer/detector) → 4 Fake test.
  - `home_screen` "Görsel Çeviri" kartı; AndroidManifest CAMERA izni; pubspec `google_mlkit_text_recognition: ^0.15.0` (0.13.x commons çakışıyordu) + `image_picker: ^1.1.2`.
  - **Tuzak çözüldü:** `_showInfo` dialog'unu `_busy` spinner açıkken `await` etmek pumpAndSettle'ı kilitliyor → busy'yi kapat, sonra `unawaited(_showInfo)`.

**Bıraktıklarım:** **OCR Faz 1 + NLLB PC testi KOD/İŞ TAMAM, analyze temiz, 147/147 test. Açık KOD işi yok.** Bekleyen = tamamen CİHAZ (Poco gelince): (a) **Görsel Çeviri cihaz smoke** (foto/galeri→OCR→çeviri), (b) **Opus-MT tr→en de-risk** (hâlâ bekliyor), (c) NLLB kalite kararı (`_scratch/nllb_quality_results.md` Mehmet'le). OCR ana akışa bağlı ve çalışır durumda (mevcut çeviri pipeline'ı yeniden kullanıyor).

**Sıradaki modele not:** İLK İŞ Poco gelince Görsel Çeviri cihaz smoke + Opus-MT de-risk. **Görsel Çeviri Faz 2 = canlı kamera overlay** (`camera` paketi, `TextRecognizerEngine` arayüzü değişmeden — aynı `recognize`). ONNX çeviri hâlâ ana akışa BAĞLI DEĞİL (de-risk ekranları); "hangi NMT" kararı açık (Opus-MT en umutlu + NLLB 1.3B kalite iyi ama OOM). `_scratch/` repo-dışı (silinebilir). Mehmet kısa/net; cihazsızken cihaz-gerektirmeyen işe yönelt (bu oturum böyle yapıldı).

---

## 2026-06-06 (2. blok) — Claude Opus 4.8 — ÇEVİRİ: ONNX PİVOT + NMT model arayışı (SMaLL-100✗ NLLB-600M~ NLLB-1.3B✗OOM → Opus-MT test bekliyor)

> ## ⭐ DEVAM EDEN İŞ (SIRADAKİ OTURUM İLK İŞ: Opus-MT test)
> **Çeviri kalitesi krizi → Mehmet kararı: LLM çeviriyi bırak, ONNX NMT'ye geç.** Hangi NMT modeli? — de-risk turu devam ediyor:
> - **🎯 ŞU AN BEKLEYEN: Opus-MT (Helsinki/Marian) de-risk — KOD+MODEL CİHAZDA, Mehmet TEST ETMEDEN bıraktı.** 🧪 → "Opus-MT de-risk" → tr→en çevir. Çift-özel küçük (~156MB int8), OOM yok, hızlı olmalı. **İLK İŞ: kaliteyi gör.** İyiyse en-tr'yi de export et (Xenova'da en-tr int8 YOK → `optimum` ile Helsinki-NLP/opus-mt-tc-big-en-tr veya opus-mt-en-tr kendim export) → çift yönlü → fast moda bağla.
> - **SMaLL-100 ELENDİ:** KV-cache'li düzgün PC-export'la bile gerçek cümlede saçmalıyor (yalnız basit selamlama). 330M zayıf.
> - **NLLB-600M:** SMaLL-100'den belirgin iyi ama "yeterli değil".
> - **NLLB-1.3B ELENDİ (OOM):** kalite için denendi ama 2.75GB int8 → cihaz **çöküyor** (8GB RAM yetmiyor). On-device'da 1.3B çok ağır.
> - **Sıralama (kalite/feasibility):** Opus-MT(tr-en özel, test bekliyor) → yetmezse NLLB-600M (çalışıyor, orta) → daha iyisi on-device zor (1.3B OOM, Madlad-3B daha ağır) → en üst kalite = online (Gemini) "best" mod ayrı iş.

**ÖNEMLİ DEV ALTYAPISI (bu blokta kuruldu — ONNX de-risk için):**
- **Model dosyaları Xet CDN'de → in-app dart http TLS patlar.** Çözüm: PC'de `curl`/optimum export → `adb push` ile **harici app dizinine**. Manager'lar (`Small100ModelManager`/`NllbModelManager`/`OpusMtModelManager`) `getExternalStorageDirectory()` kullanır (adb-yazılabilir + app izinsiz okur). Cihazdaki dizinler: `/sdcard/Android/data/com.mobstudios.hermes/files/{small100, nllb, opus/tr-en}/`. **MSYS_NO_PATHCONV=1 + yerel yolu Windows formatında ver** (Git Bash `/sdcard`'ı Windows yoluna çeviriyor; her ikisi de düzgün olmalı).
- **PC export toolchain (kurulu):** `pip install optimum[exporters,onnxruntime] torch onnx onnxruntime`. `optimum-cli` PATH'te yok → `python -m optimum.exporters.onnx --model <id> --task text2text-generation-with-past [--trust-remote-code] <out>/`. Quantize: `onnxruntime.quantization.quantize_dynamic(QInt8)` (script: `/tmp/quant.py`, `/tmp/quant13.py`). 1.3B fp32 ONNX **external data** (`.onnx_data`) kullanır (>2GB protobuf); int8 quantize tek dosyaya indiriyor. optimum post-process (merge) hatası ÖNEMSİZ — 3 ayrı model (encoder/decoder/decoder_with_past) zaten üretiliyor (merged kullanmıyoruz).
- **PC export artefaktları (silinebilir):** `/tmp/{small100,small100_q,nllb,nllb13_exp(~12GB!),nllb13_q,opus_tr_en}`. nllb13_exp BÜYÜK, temizlenebilir.
- **ONNX I/O adları (optimum seq2seq, hepsi aynı):** encoder `input_ids,attention_mask→last_hidden_state`; decoder(step0) `input_ids,encoder_attention_mask,encoder_hidden_states→logits,present.*`; decoder_with_past `...,past_key_values.*→logits,present.*.decoder.*` (encoder KV re-emit YOK, cache'te sabit). Translator'lar bunu kullanır.
- **Marian/Opus-MT protokol farkı:** dil tokenı YOK (çift-özel), encoder=`subwords+[eos]`, decoder_start=pad (tr-en=62388), eos=0, forced_bos yok. M2M/NLLB: dil tokenı var. SMaLL-100: hedef-dil token'ı KAYNAĞA + forced_bos yok.
- **MIUI temiz kurulum:** uygulama kaldırılıp yeniden kurulurken `adb install` ilk seferde `INSTALL_FAILED_USER_RESTRICTED` → telefonda "USB ile yükleme" + çıkan onay dialogunu Mehmet **kabul etmeli** (reddederse iptal). Güncelleme (zaten kuruluysa) sorunsuz.
- **Cihaz 21GB doldu → Mehmet Hermes'i kaldırıp temiz kurdu** (eski LLM'ler/xnnpack/yarım indirmeler birikmişti). Şimdi 26GB boş.

**YENİ KOD (bu blok, analyze temiz, 143/143 test — ONNX kısmı hariç hepsi cihazda çalışıyor):**
- **Çeviri context'i:** `TranslationEngine.translate`'e opsiyonel `context: List<TranslationTurn>` (LLM referans+mishearing düzeltme; MLKit yok sayar). Manager son 8 turu tutar/geçer. **Sade few-shot prompt** (uzun kural bloğu Gemma'yı karıştırıyordu). LLM çeviri yine de yetersiz çıktı → ONNX pivot.
- **Bas Konuş fast/full:** `language_select_screen` "Çeviri kalitesi: Hızlı(MLKit)/Akıllı(LLM)" segmenti; `ModelTierSelector(showMlkit:false)` full'de yalnız LLM. **ONNX'e geçince bu fast=SMaLL-100/NLLB olacak (henüz bağlanmadı — ONNX motorları TranslationEngine'e wrap edilip fast/full'e takılacak).**
- **Hata UX:** Bas Konuş boş transkript → motor-agnostik "Ses algılanamadı" + **OK'li dialog** (kalıcı banner yok). `kPttDevOverlay` DEV şeridi (STT/çeviri motoru+model). Manager drop mesajları motor adı sızdırmıyor.
- **ONNX de-risk motorları/ekranları (3 motor, hepsi 🧪 menüde, KV-cache):**
  - `small100_onnx_translator.dart` + manager + test (ELENDİ, kod duruyor — negatif bulgu).
  - `nllb_onnx_translator.dart` (önceden vardı) + `nllb_model_manager` (artık external storage) + `NllbTestScreen`. 600M çalışıyor, 1.3B OOM.
  - `opus_mt_onnx_translator.dart` + `opus_mt_model_manager.dart` (çift listesi, şimdilik tr-en) + `opus_mt_test_screen.dart`. **TEST BEKLİYOR.**

**Bıraktıklarım:** **ONNX çeviri henüz ana akışa BAĞLANMADI** — yalnız de-risk test ekranları. Cihazda: NLLB-600M (çalışır/orta), Opus-MT tr-en (test bekliyor). NLLB-1.3B OOM (cihazdaki dosyalar duruyor ama çöküyor — silinebilir). Karar (hangi NMT) verilince: seçilen ONNX motorunu **`TranslationEngine`'e wrap et** (signature'lar farklı: NllbOnnx `translate(text,{srcLang,tgtLang})`, OpusMt `translate(text)` → adapter sınıfı), fast/full'e bağla (`createTranslationEngine`/`ModelTierSelector`), Ayarlar'a model yöneticisi ekle. **Crunch ayrı = Phi-4-mini (NS kararı).** Bu blokun LLM/UX işleri (context, fast/full, hata dialog, DEV overlay) cihazda çalışıyor — ONNX bağlanınca fast/full'ün "full"u ONNX olur.

**Sıradaki modele not:** **İLK İŞ: Opus-MT tr-en kalitesini test ettir** (🧪, cihazda hazır). İyiyse en-tr ekle (export) → çift yönlü → ana akış. Çeviri motor seçimi henüz AÇIK — Opus-MT en umutlu (çift-özel, küçük, OOM yok). On-device kalite tavanı gerçek: SMaLL-100 çöp, NLLB-600M orta, 1.3B OOM. En üst kalite isteniyorsa online (Gemini) "best" mod ayrı iş. ONNX modelleri PC'den adb-push (Xet engeli); altyapı + protokoller yukarıda. SMaLL-100/NLLB-1.3B = negatif bulgu (kod silinmedi). Mehmet kısa/net; bu oturum ÇOK uzundu (NS-1..5 + context/prompt + fast/full + hata UX + ONNX pivot + 3 NMT de-risk).

---

## 2026-06-06 — Claude Opus 4.8 — LLM Model Yönetimi NS-1/2/3/5

> ## ⭐ SIRADAKİ OTURUM — İLK İŞ (cihaz, Mehmet)
> - **NS-4:** Ayarlar (sağ üst dişli) → **Çeviri Modelleri (LLM)** → Qwen + Gemma yeniden indir (yer var). Gemma'da token dialog'u çıkar (kayıtlı token otomatik dolu gelir). İnince **crunch + Bas Konuş LLM çevirisi geri çalışır.**
> - **NS-6:** SmallTalk → Hands-free **fast/full** cihaz smoke + **Bas Konuş Gemma/Qwen** kök fix doğrula (artık model gerçekten inince çeviri gelmeli; gelmiyorsa kırmızı hata banner'ı çıkacak → metniyle kök fix).
> - **Doğrula:** Bas Konuş'ta Qwen seç → indir değilse artık "Model hazır" yalan göstermez (NS-2), inmemişse indir butonu çıkar.
> - **İleri keşif:** Konferans büyük-Vosk, full+ diarizasyon, gürültü için Android NoiseSuppressor/AEC.

**Devraldım:** SmallTalk S1+S2+S3+fast/full kod tamamdı; NS-1..6 iş listesi açıktı. Kök neden: Qwen modeli cihazdan silinmiş + `ModelTierSelector` silinen modeli yanlışlıkla "indirili" gösteriyordu (warmup geçip çeviri/crunch sessiz patlıyordu).

**Yaptıklarım (NS-1/2/3/5 — hepsi kod, analyze temiz, 143/143 test, arm64 debug APK Poco'da kurulu):**
- **NS-2 (yanlış-indirili fix):** `llm_translation_engine.dart` `_installedId` artık metadata id'sini bulduktan sonra **diskteki dosyayı doğruluyor** (`_fileExistsFor`: `getApplicationDocumentsDirectory()/{filename}` var + ≥1MB). Yoksa stale metadata `uninstallModel` ile temizleniyor → yanlış pozitif bitti.
- **NS-1 (Ayarlar'a LLM):** `managed_model.dart` `_LlmManagedModel` (Qwen+Gemma) + `ManagedModel.requiresToken` getter (alt sınıflar `implements`→`extends`, default'u miras alsın). `settings_screen.dart` Gemma indirmede `_ensureToken` token dialog'u. Dişli zaten `SettingsScreen`'e gidiyordu.
- **NS-3 (token persistence):** yeni `hf_token_store.dart` `HfTokenStore` (`shared_preferences` 2.5.5 eklendi). `model_tier_selector.dart` token kutusunu kayıtlıdan doldurur + indirmede kaydeder. 3 yeni unit test. RELEASE_CHECKLIST'e düz-metin uyarısı eklendi.
- **NS-5:** Zaten karşılanıyordu — Bas Konuş `ModelTierSelector` ile 3 katmanı gösteriyor; dokunmadım. NS-2 fix'iyle çalışır hale geldi.

**Bıraktıklarım:** **NS-1/2/3/5 KOD TAMAM + APK Poco'da kurulu. Açık kod işi yok.** Kalan tamamen cihaz: NS-4 (modelleri Ayarlar'dan yeniden indir) + NS-6 (fast/full smoke + Bas Konuş LLM doğrula). Crunch + Bas Konuş LLM, Qwen yeniden inene kadar boş döner (model hâlâ cihazda yok — ama artık "hazır" yalanı yok, indir butonu çıkar).

**Sıradaki modele not:** İLK İŞ Mehmet'in cihaz testini bekle (NS-4 indirme + NS-6 smoke). HF token [[ref-hf-token]] memory'de (repo'ya GÖMME; pre-commit hook token kalıbını engelliyor). Token artık `HfTokenStore` ile shared_preferences'a düz metin yazılıyor — release'de secure storage/self-host (RELEASE_CHECKLIST). Mehmet kısa/net, kararları roadmap+memory'den oku.

---

## 2026-06-05 (3. oturum) — Claude Opus 4.8 — SmallTalk (eski Voice Translator) S1+S2+S3 + fast/full

> ## ⭐ SIRADAKİ OTURUM — İLK İŞ LİSTESİ (Mehmet istedi, birebir)
> - **NS-1:** Ana menü Ayarlar'a (sağ üst dişli — var ama LLM göstermiyor) **Gemma+Qwen ekle**: gör/indir/sil + Gemma için HF token alanı.
> - **NS-2:** Yanlış "indirili" tespitini düzelt (gerçek dosya kontrolü).
> - **NS-3:** HF token'ı kalıcı kıl (kayıtlı token'ı tekrar yapıştırma).
> - **NS-4:** Qwen + Gemma'yı yeniden indir (yer var) → crunch + Bas Konuş geri çalışır.
> - **NS-5:** Bas Konuş'ta MLKit + Gemma + Qwen üçü de seçilebilir kalsın.
> - **NS-6:** fast/full hands-free cihaz smoke.
> - **İleri keşif:** Konferans büyük-Vosk, full+ diarizasyon, gürültü için Android NoiseSuppressor/AEC.

**Devraldım:** Konferans polish bitti (cihazda ✅). Yeni iş: Voice Translator→**SmallTalk** (çift yönlü, Konferans mimarisi üzerine). Mehmet AFK + token az → her aşamada bu entry güncellenir.

**Plan (onaylı, `~/.claude/plans/temporal-sprouting-prism.md`):** 3 faz. Kararlar: (1) Bas Konuş = eski bölünmüş 180° ekran KALIR (yalnız Hands-free yeni chat UI); (2) Hands-free konuşmacı tespiti = **otomatik dil tespiti** (iki Vosk recognizer tek mic + MLKit LangID); (3) **ses kanal yönlendirme (kulaklık↔hoparlör) DEFERRED** (native Kotlin sonra, bu turda TTS varsayılan çıkış). 3-katman çeviri silinmedi (Mehmet "şimdilik kalsın").

**İlerleme:**
- **S1 (menü+yapı) — ✅ KOD TAMAM, analyze temiz + 123/123 test (cihaz smoke bekliyor):** `home_screen` SmallTalk kartı (Konferans altında) + folder; eski "Bas Konuş" + "Voice Translator" ana kartları kaldırıldı. Yeni `lib/features/smalltalk/smalltalk_setup_screen.dart` (alt-mod picker: Bas Konuş→`LanguageSelectScreen(pushToTalk)`, Hands-free→placeholder) + `smalltalk_archive_screen.dart` (folder, `listSessionsForModes([voiceTranslator,pushToTalk])`). repo `listSessionsForModes` eklendi. `title_generator` modeName voiceTranslator→'smalltalk' (+ test güncellendi). widget_test 'SmallTalk' kartı. Konferans tema/detay/crunch_runner yeniden kullanıldı.
- **S2 (Bas Konuş'a warmup+crunch+folder) — ✅ KOD TAMAM, analyze temiz + 123/123 test (cihaz smoke bekliyor):** `push_to_talk_screen` faz yapısına çevrildi (warmup ısınma butonu → running eski split 180° UI → ended crunch now/later). `_warmUp()` manager.prepare(), `_start()` manager.start(), center kontrol X→`_end()` (ended faz), `runConferenceCrunch` + `ConferenceDetailScreen` bağlandı. mode=pushToTalk (folder S1'de zaten gösteriyor). Accent yeşil (#50C878). Yeni unit test yok (UI).
- **S3 (Hands-free çift yönlü streaming) — ✅ KOD TAMAM, analyze temiz + 135/135 test (cihaz smoke bekliyor):** `dual_vosk_streaming_controller.dart` (tek mic + VAD + **iki Vosk `Recognizer`** `acceptWaveformBytes`; SpeechService DEĞİL; `setWords` ile kelime `conf`; `DualTranscript{masterText/Conf, localText/Conf}`; `DualTranscriber` arayüzü). `smalltalk_streaming_session.dart` orkestratör: **konuşmacı = akustik güven skoruna göre** (`route()` saf+test, eşitlik→master öncelik; MLKit LangID KULLANILMADI çünkü her model kendi dilinde metin üretir → ayırt edemez!). Çeviri MLKit, DB mode=voiceTranslator, narration local→master oto (açıksa), master→local play ile, local play narration kapatır. `smalltalk_handsfree_setup_screen` (dil+narration) + `smalltalk_screen` (warmup + iki-model indirme kapısı + master sağ/local sol baloncuk + play + canlı partial + Bitir→crunch). setup picker Hands-free→gerçek setup'a bağlandı. **12 yeni session testi geçti** (route + pipeline). Ses kanal yönlendirme DEFERRED (TTS varsayılan çıkış).
- **S1+S2+S3 APK Poco'da kurulu** (arm64 debug, `adb install -r -d` Success). Cihaz smoke Mehmet'te.
- **⚠️ S3 DE-RISK CİHAZDA:** güven-skoru yönlendirme doğru mu (master/local karışıyor mu) + iki recognizer SD860 hız/RAM. Yetmezse ara çözüm (master-öncelik ağırlığı / Vosk endpoint).

**S3 CİHAZ TESTİ + YENİ KARARLAR (2026-06-05, 3. oturum devam, Mehmet birebir):**
- Cihaz: "bas konuşta gemma ve qwen çalışmıyor (başlıyor ama konuşunca çeviri hiç gelmiyor)"; "hands-free'de kim konuştu kararı iyi ama yeterli değil, whisper'a dönüş?".
- **Mehmet kararları:** (1) Bas Konuş Gemma/Qwen'i **DÜZELT** (özet değil, kısa cümle çevirisi bekliyor) — hatalar yutuluyordu, **görünür yapıldı** (kırmızı banner, `_notice`); sonraki cihaz testinde çıkacak hata metniyle kök fix. (2) Hands-free = **fast/full**: **fast=Vosk** (mevcut, histerezisle iyileştirildi), **full=Whisper auto+MLKit dil tespiti**. (3) **full+ (ileride)** = diarizasyon(voiceprint)+Vosk. (4) **Büyük Vosk'u Konferans'ta test et** (doğruluk↑; hands-free routing'i ÇÖZMEZ + 2 büyük model eşzamanlı SD860'a ağır). (5) Gürültü: büyük model temizlemez, doğruluğu artırır; gerçek çözüm Android NoiseSuppressor/AEC veya RNNoise (ayrı iş).
- **✅ KOD (fast/full) TAMAM:** `whisper_langid_transcriber.dart` (DualTranscriber; Whisper auto→MLKit LangID→master/local slot; `slotFor` saf+test; partial yok). `smalltalk_streaming_session` route'a **histerezis** (yakın güvende son konuşanda kal). Setup'a fast/full adımı. `SmallTalkScreen` quality param + motor seçimi + mod-başı indirme kapısı (fast=Vosk×2, full=Whisper small ~466MB). analyze temiz, **140/140 test**.
- **APK Poco'da kurulu** (fast/full + Bas Konuş hata-banner'ı; `adb install -r -d` Success).
- **AÇIK İŞLER:** (a) Bas Konuş Gemma/Qwen hata metni → kök fix (cihaz). (b) S3 fast/full cihaz smoke (fast routing + full doğruluk/hız). (c) Konferans'a büyük Vosk opsiyonu (yeni iş). (d) full+ diarizasyon (keşif). (e) gürültü NS/AEC (keşif).

**🔑 SESSION SONU KÖK NEDEN + SIRADAKİ İŞLER (Mehmet cihaz, birebir):**
- **Qwen modeli cihazdan SİLİNMİŞ** (yer içindi) → **crunch DA çalışmıyor artık** (eskiden çalışıyordu çünkü Qwen o zaman vardı). Bas Konuş LLM çevirisi de bu yüzden boş ("çeviri gelmiyor"). Cihazda artık yer var.
- **BUG: "Çeviri motoru" seçicisi modeli 'indirili/Model hazır' gösteriyor ama dosya YOK (yanlış pozitif)** → warmup geçiyor, çeviri/crunch sessizce patlıyor. `LlmTranslationEngine.isLanguageReady`/`_installedId` (`flutter_gemma listInstalledModels`) silinen modeli hâlâ listeliyor; **dosya varlığını doğrulamıyor.**
- **Mehmet istekleri (SIRADAKİ OTURUM):**
  - **NS-1: Ana menü Ayarlar'a (sağ üst dişli, `SettingsScreen`/`ModelRegistry` zaten var ama yalnız Whisper/Vosk/MLKit) Gemma + Qwen EKLE** — gör/indir/sil + Gemma HF token alanı. (`managed_model.dart`'ta LLM yok — `_LlmManagedModel` ekle.) Mehmet: "eskiden vardı geri getir, yoksa ekle."
  - **NS-2: Yanlış 'indirili' tespiti FIX** — LLM hazırlık kontrolü gerçek dosya varlığını doğrulasın (silinen model 'hazır' görünmesin).
  - **NS-3: HF token persistence** — kayıtlı token tekrar yapıştırılmadan kullanılsın (dart-define `HF_TOKEN` veya `flutter_secure_storage`; token kutusu otomatik dolsun). Token: memory [[ref-hf-token]] (repo'ya GÖMME). RELEASE_CHECKLIST'e dikkat.
  - **NS-4: Modelleri yeniden indir** — Qwen (crunch + Bas Konuş opsiyonu), Gemma (token ile). Yer var.
  - **NS-5: Bas Konuş motor seçimi** — MLKit + Gemma + Qwen üçü de seçilebilir kalsın (ModelTierSelector'da MLKit dahil). Mehmet: canlı kısa-cümle çevirisi bekliyor (özet değil).
  - **NS-6: S3 fast/full hands-free cihaz smoke** (henüz yapılamadı — model sorununa takıldı).

**Bıraktıklarım:** SmallTalk **S1+S2+S3 + fast/full KOD TAMAM, analyze temiz, 140/140 test, APK Poco'da kurulu.** Açık KOD işi yok ama **iki gerçek bug/eksik var (NS-1, NS-2)** + cihaz smoke'ları bekliyor. Crunch + Bas Konuş LLM, Qwen yeniden inene kadar çalışmaz (model silinmiş).

**Sıradaki modele not:** İLK İŞ = NS-2 (yanlış 'indirili' tespiti fix — küçük, `LlmTranslationEngine` dosya doğrulaması) + NS-1 (Settings'e LLM yöneticisi). Sonra NS-3 token persistence → NS-4 modelleri indir → NS-5/NS-6 cihaz testi. Konferans büyük-Vosk, full+ diarizasyon, gürültü NS/AEC = ileri keşif (roadmap'te). Mehmet kısa/net, kararları plan(`~/.claude/plans/temporal-sprouting-prism.md`)+roadmap+memory'den oku. SmallTalk fast=Vosk×2+histerezis, full=Whisper auto+MLKit LangID; ses kanal yönlendirme (kulaklık↔hoparlör) DEFERRED.

**Bıraktıklarım:** **S1+S2 KOD TAMAM + cihazda kurulu, cihaz smoke Mehmet'te bekliyor.** Açık kod işi: S3 (başlanmadı). Cihaz smoke: (S1) menü→SmallTalk→alt-mod seçimi + folder açılıyor mu; (S2) SmallTalk→Bas Konuş→dil→warmup→karşılıklı bas-konuş→Bitir→crunch now/later→SmallTalk folder'da görünüyor mu.

**Sıradaki modele not — İLK İŞ: S3 (Hands-free), en zor parça.** Plan dosyası (`~/.claude/plans/temporal-sprouting-prism.md`) Faz S3 tam detay. Özet: (1) tek mic akışı (`record.startStream` PCM16/16k, `StreamingMicAudioInput`/`push_to_talk_audio_input` kalıbı) → **iki Vosk `Recognizer`** (master dili + local dili) `acceptWaveformBytes`+`getPartialResult`/`getFinalResult` ile beslenir (SpeechService DEĞİL — sabit EventChannel adı yüzünden iki SpeechService çakışır; `VoskSttEngine` kalıbı mevcut). (2) Her final iki tanıyıcıdan iki metin → **MLKit Language ID** (`lib/core/engines/language_id/MlKitLanguageDetector`, kayıtlı) ile kendi diliyle eşleşen+güvenli olan kazanır → master(sağ)/local(sol) yönlendirme. (3) Yeni chat ekranı (`SmallTalkScreen`, Konferans `conference_screen`+`ConferenceTheme` kalıbı): master sağ baloncuk (transkript beyaz/büyük + çeviri gri/küçük + play), local sol (transkript gri/küçük + çeviri beyaz/büyük + play), canlı partial satırı, warmup, Bitir→crunch. (4) `ConferenceStreamingSession`/`VoskStreamingController` genişletilebilir veya yeni `smalltalk_streaming_session`. **Setup akışı:** SmallTalk→Hands-free şu an `_HandsFreePlaceholder`'a gidiyor (`smalltalk_setup_screen.dart`) — onu gerçek setup'a (dil + narration sorusu + warmup) bağla. **DE-RISK ÖNCE:** çift-recognizer+LangID doğruluk/hız SD860'ta (ara çözüm: Vosk confidence skoru / master-öncelikli heuristik). **DEFERRED:** seçici ses kanal yönlendirme (kulaklık↔hoparlör) — native Kotlin, sonra; bu fazda TTS varsayılan çıkış. Mehmet kısa/net, kararları plan+dokümandan oku.

---

## 2026-06-05 (2. oturum) — Claude Opus 4.8

**Devraldım:** Konferans Modu K1–K4 kod tamam + cihazda çalışıyor; KALAN = 2 polish (#1 transkript hızı EN KRİTİK, #2 Qwen bozuk karakter). Mehmet "ilk iş tartış" demişti.

**Yaptıklarım (Mehmet kısa süre sonra AFK oldu → plan modunda ilerledim, onay verdi, kod-only kısımları bitirdim):**
- **Kararlar (AskUserQuestion, Mehmet):** hız çözümü = **direkt Vosk native streaming** (ara çözüm değil); **önce #2** sanitize.
- **#2 ✅ KOD:** `lib/core/utils/llm_text.dart` `sanitizeLlmOutput` (byte-fallback `<0xNN>`→UTF-8 / özel token / metaspace ▁ / kontrol karakteri) → `LlmHost.generate` tek choke-point. 13/13 test.
- **#1 ✅ KOD:** Manager bypass eden streaming pipeline — `vosk_streaming_controller.dart` (`StreamingTranscriber` + `VoskStreamingController`, native `SpeechService` onPartial/onResult, VoskTestScreen kalıbından) + `conference_streaming_session.dart` (orkestratör: final→filler→MLKit→DB→çeviri; partial yalnız livePartial; crunch uyumlu) + `conference_screen.dart` streaming'e geçti (model indirme kapısı + ısınma + soluk canlı partial satırı). 8/8 orkestratör testi.
- **analyze temiz, 121/121 test.** Roadmap + memory güncellendi. arm64 debug APK derlendi + Poco'ya kuruldu.
- **CİHAZ TESTİ ✅ GEÇTİ (Mehmet döndü):** ilk tur "harika çalışıyor ancak aynı çeviriyi 4 kere tekrarlıyor" → BUG fix: Vosk EventChannel aynı finali art arda yayıyor → `ConferenceStreamingSession._onFinal` ardışık aynı finali atlar (`_lastFinal`, 2 yeni test, 123/123). APK yeniden kuruldu. Fix sonrası Mehmet: **"aynı çeviri artık tekrar etmiyor, bozuk karakterler artık ortadan kalktı."** + canlı partial satırı "çok güzel dokunuş kalsın", EN Vosk "şimdilik yeterli, sonra değerlendiririz."

**Bıraktıklarım:** **KONFERANS MODU POLISH TAMAMEN BİTTİ — #1 hız/streaming + tekrar fix + #2 bozuk karakter hepsi cihazda geçti.** Açık iş YOK. Canlı partial satırı kalıcı. analyze temiz, 123/123 test, APK cihazda kurulu.

**Sıradaki modele not:** **SIRADAKİ BÜYÜK İŞ = önceki turun KALANI: 3-katman çeviri** — (1) **Manuel Çeviri** (main.dart) `ModelTierSelector` bağlanmadı; (2) **tier seçim kalıcılığı** (prefs/Drift — şimdilik mod açılışında varsayılana döner). Detay roadmap Polish "🌐 3-KATMAN" + memory "SIRADAKİ 3 BÜYÜK İŞ". Konferans streaming **TTS feedback guard'ı hafif** (narration kulaklığa varsayımı) — hoparlörden seslendirmede mic'e TTS kaçabilir, ileride gözle. EN Vosk doğruluğu sonra değerlendirilecek (Whisper EN'e dönüş opsiyonu açık). Mehmet kısa/net, kararları dokümandan oku.

---

## 2026-06-05 — Claude Opus 4.8

**Devraldım:** 3-katman çeviri çekirdeği + Ders/Bas Konuş model seçimi cihazda kuruluydu, cihaz testi bekliyordu. KALAN: Manuel selector + seçim kalıcılığı. (Bunlara bu oturumda GİRİLMEDİ — Mehmet yeni iş verdi.)

**Yaptıklarım (uzun, üretken oturum — Konferans Modu baştan + 2 cihaz bug fix):**
- **Mehmet "Ders Modu"nu KONFERANS MODU olarak baştan tasarlattı.** Detaylı spec verdi → plan modunda 3 soru netleştirildi (motor seçici kaldır=canlı MLKit/crunch Qwen, açık tema tüm akışa, crunch=tam çeviri+özet+başlık) → 4 sub-step (K1–K4), her biri cihaz testi geçti:
- **K1 ✅:** rename + açık/beyaz tema akışı (`lib/features/conference/`: setup=2 dil+seslendirme, screen=warmup gri yuvarlak buton+halka+"Isınıyor"→running) + `Manager.prepare()/start()` ayrımı (ısınma için). Eski `lecture_screen` silindi. Mehmet: "her şey çalışıyor" + polish notu: transkript biraz hızlı olmalı.
- **K2 ✅ (K1'e foldlandı):** running ekranı yalnız çeviri alt alta (transkript gizli, DB'ye kayıtlı) + "Konferansı Bitir".
- **K3 ✅:** DB v3 (crunchedAt/Title/Translation/Summary + migration + codegen) + repo (setCrunchResult/listSessionsForMode/deleteSession) + arşiv klasörü (ana ekran kart yanı klasör butonu) + detay ekranı. Mehmet: "k3 başarılı".
- **K4 ✅:** `CrunchService` (Qwen, **bağlam-güvenli map-reduce**) + `crunch_runner` ilerleme dialogu + `LlmHost.generate` maxTokens param + 3 tetikleyici (oturum sonu/arşiv/detay). Mehmet: "her şey doğru çalışıyor".
- **2 CİHAZ BUG'ı düzeltildi:** (a) uzun konuşmada "Bitir" takılması → `_stopping` bayrağı (in-flight `setState(listening)` `ending`'i eziyordu) + backpressure cap=3. (b) **crunch native ÇÖKME** (logcat crash buffer ile doğrulandı: MediaPipe `nativePredictSync` JNI abort = bağlam taşması) → ilk "rolling summary" tasarımı büyüyen özeti besliyordu → **bağlam-güvenli map-reduce**'a çevrildi (her LLM girdisi küçük/sınırlı). **100/100 test, analyze temiz.**

**Bıraktıklarım:** **Konferans Modu K1–K4 KOD TAMAM + cihazda çalışıyor (crunch dahil, çökme yok).** Açık iş YOK. **KALAN = Konferans Modu polish (2 iş, Mehmet birebir kapanışta):** **#1 ⚡ TRANSKRİPT HIZI (EN KRİTİK)** — konuşma sürerken çeviri çok geride kalıyor, Gemini çok daha hızlı; hız yetmeyince backpressure cümle/kelime atlıyor → context kaybı. On-device cevap = **Vosk native streaming** (`SpeechService.onPartial`; büyük iş, Manager pipeline bypass). **#2 🔣 Qwen crunch çıktısında bozuk karakterler** (sanitize gerek). İkisi de roadmap Polish "🎤 KONFERANS MODU"da birebir.

**Sıradaki modele not:** İLK İŞ tartış: Konferans transkript hızı (#1) — Vosk native streaming'e geçiş mi yoksa ara çözüm (chunk küçült 5sn→2-3sn, Whisper full→base/tiny) mi? Mehmet "Gemini hızı" istiyor; gerçek cevap streaming ASR ama büyük iş, önce Mehmet'le kapsamı netleştir. Sonra #2 Qwen bozuk karakter (çıktı sanitize — özel token/UTF-8). **Önceki tur'un KALANI hâlâ açık** (3-katman: Manuel Çeviri selector + tier seçim kalıcılığı) — Konferans polish'i Mehmet öncelikledi, o bitince dön. Mehmet kısa/net konuşur, kararları dokümandan oku. Cihaz: Qwen kurulu (ilk yükleme yavaş, xnnpack_cache regen), `adb install -r -d` (`~/AppData/Local/Android/Sdk/platform-tools/adb.exe`, ID cd61ba57), arm64-only debug APK.

---

## 2026-06-04 — Claude Opus 4.8

**Devraldım:** Açık iş yok; sıradaki büyük iş 3-katman çeviri entegrasyonu (Tier3=Qwen kararlı, Tier2 orta-NMT araştırılacak). STT tamam, 89/89 test.

**Yaptıklarım (çok uzun, üretken oturum — Tier2 araştırması → NLLB de-risk → eleme → 3-katman mimari):**
- **Tier2 araştırması:** opus-mt≈MLKit (sıçrama yok), Bergamot devasa native emek → elendi. **NLLB-200-distilled-600M** = MLKit'ten +44% FLORES + Qwen'den hafif. KRİTİK: NLLB saf çevirmen (mantık yürütmez) → Qwen yerine değil = Tier2.
- **NLLB de-risk BAŞTAN SONA yazıldı + cihazda test edildi:** `flutter_onnxruntime` + `dart_sentencepiece_tokenizer` + Xenova NLLB ONNX. `NllbOnnxTranslator` (seq2seq, tokenizer.json'dan dil id'leri, önce past'sız sonra **KV-cache/decoder_with_past** — tensor adları ASCII-grep ile doğrulandı, OrtValue native passthrough). Modeller PC'de curl→adb push (in-app indirici HF **Xet CDN**'de TLS handshake patlıyor).
- **NLLB ELENDİ (Mehmet cihaz, birebir):** "kabul edilemez ... nllb'den kurtul yerine gemma'yı koyalım". KV-cache'e rağmen ~12sn(>20). `<5sn gerçekçi değil` (Dart-orkestralı decode loop; Gemma hızlı çünkü MediaPipe native). "_" metaspace bug + RAM dispose butonu da eklendi (Mehmet istedi).
- **✅ SON KARAR: 3-KATMAN = Tier1 MLKit/Tier2 Gemma/Tier3 Qwen + her modda model seçimi** (varsayılan Ders=Qwen, diğerleri MLKit). **Çekirdek + 2 mod yazıldı:** `LlmHost` (tek-LLM-RAM) + `LlmTranslationEngine` + `TranslationTier` factory + `ModelTierSelector` widget; **Ders+Bas Konuş** `LanguageSelectScreen`'den bağlandı. analyze temiz, 89/89, arm64 APK cihazda.

**Bıraktıklarım:** 3-katman çekirdek + Ders/Bas Konuş model seçimi cihazda kurulu, **cihaz testi bekliyor**. **KALAN:** (1) **Manuel Çeviri** (main.dart) selector — bağlanmadı, ayrı yapı. (2) **Seçim kalıcılığı** (prefs/Drift — şimdilik mod açılışında varsayılana döner). (3) Cihaz testi: Ders=Qwen (cihazda, xnnpack_cache silindi→ilk yükleme yavaş), Bas Konuş=MLKit, tier değiştir + **Gemma indir** (selector token kutusu, [[ref-hf-token]]).

**Sıradaki modele not:** İLK İŞ: Mehmet'in cihaz testini bekle (Ders/Bas Konuş model seçimi + Gemma re-download). Sonra Manuel selector + kalıcılık. **Telefon ~%95 doluydu** — yer için Qwen xnnpack_cache (regen) + Gemma .task + NLLB 1.3GB silindi; Qwen modeli sağlam. **APK arm64-only** (`flutter build apk --debug --target-platform android-arm64`, ~626MB; full-ABI 646MB cihaza SIĞMIYOR), `adb install -r -d`. **NLLB kodu/paketleri (flutter_onnxruntime, dart_sentencepiece_tokenizer) deney/negatif-bulgu — başka kullanım yoksa pubspec'ten çıkarılabilir.** Mehmet kısa/net konuşur; kararları dokümandan oku.

---

## 2026-06-03 — Claude Opus 4.8

**Devraldım:** Önceki oturum (2026-06-01) iki açık iş bıraktı: (1) iki cihaz testini Mehmet'e hatırlat (Ders Modu chunk/ilk-kelime/STT rozeti + LLM Çeviri Test Qwen), (2) Mehmet Qwen yerine GEMMA istiyor → token+lisans+kod değişimi. STT katmanı tamam, 89/89 test.

**Yaptıklarım (kısa, odaklı oturum — LLM çeviri kıyas):**
- **Durumu doğruladım:** analyze temiz, 89/89 test, kilit dosyalar yerinde, kod punch board state'iyle tutarlı.
- **Gemma lisansını + ücretsiz HF token alma adımlarını açıkladım** (Mehmet sordu). Önemli: Gemma "Gemma Terms of Use" (gated, dağıtımda ToU/Prohibited-Use bildirim yükümlülüğü, kişisel token APK'ya gömülemez → production self-host). Qwen Apache-2.0 = sıfır sürtünme.
- **LLM test ekranını Qwen↔Gemma yan yana KIYASa dönüştürdüm** (`llm_translate_test_screen.dart` baştan yazıldı): tek girdi, her model **kendi "Çevir" butonu/SIRAYLA** (Mehmet "cihaz ikisini taşıyamaz" → translate sonrası `close()`, asla 2 model RAM'de), **üretim+yükleme süresi ölçer**, HF token kutusu, hatalar kırmızı. `_ModelDef`+`fileType`.
- **URL tuzağı çözdüm:** "model not found"=guess'lenen Gemma URL'i 404 (WebFetch'le doğru dosya adı bulundu). Mehmet Gemma-4-E2B (2.59GB litertlm) istedi → SD860'a fazla ağır uyarısı → Mehmet "vazgeçtim kendi bildiğin sistemi kullan" → **Gemma3-1B-IT q4 (555MB .task)** kullandım.
- **✅ CİHAZ TESTİ KARARI (birebir):** "qwen kesinlikle daha iyi ve sadece 3.2sn daha yavaş ki bu şimdilik kabul edilebilir bence." → **Tier-3 LLM = Qwen2.5-1.5B, Gemma geçişi İPTAL.**
- **HF token kaydedildi** ([[ref-hf-token]] memory, repo dışı) + Mehmet hatırlatılmasını istedi. Roadmap "Son güncelleme"+Polish "🤖 LLM ÇEVİRİ KIYAS", memory project_hermes + index güncellendi.

**Bıraktıklarım:** Açık iş yok, kod cihazda kurulu (Qwen+Gemma3-1B `.task`), analyze temiz, 89/89 test (test ekranının kendi unit testi yok — throwaway de-risk harness). **SIRADAKİ BÜYÜK İŞ: 3-katman çeviri entegrasyonu** — Tier3=Qwen'i gerçek pipeline'a bağla + Tier2 orta-NMT motoru araştır (opus-mt/Argos/NLLB) + `TranslationEngine` selector + SessionQuality bağlama. (Detay: roadmap Polish "🌐 ÇEVİRİ MOTORU ZAYIF" madde 1 + project_hermes "SIRADAKİ 3 BÜYÜK İŞ".)

**Sıradaki modele not:** Token ([[ref-hf-token]]) şu an pasif (Qwen token istemiyor) — Mehmet ileride Gemma/gated isterse hazır, açılışta hatırlat. flutter_gemma APK'yı ~656MB yapıyor; Tier3 kalıcı oldu. Önceki oturumun "Ders Modu chunk/ilk-kelime" cihaz testi bu oturumda yapılmadı (Mehmet LLM kıyasına odaklandı) — hâlâ açık, fırsatta doğrula. KURULUM: `adb install -r -d <apk>` (MIUI flutter install takılır). Mehmet kısa/net konuşur, kararları dokümandan oku.

---

## 2026-06-01 — Claude Opus 4.8

**Devraldım:** Önceki oturum sonu "İLK İŞ: Vosk Türkçe ASR de-risk" (vosk_flutter ağ hatasıyla eklenememişti). Step 6 ✅, Step 7 UI'ları büyük ölçüde ✅, transkript+streaming çözülmüş, Türkçe Whisper zayıf → ASR pivotu açık.

**Yaptıklarım (ÇOK uzun, üretken oturum):**
- **Vosk de-risk ✅ GEÇTİ:** `vosk_flutter` permission_handler çakışması → fork **`vosk_flutter_2`**. Android fix'leri (minSdk 30 + reflection ile namespace enjeksiyonu + alphacephei maven). `VoskTestScreen` (TR). İndirme yavaştı (alphacephei 30KB/s) → **HuggingFace aynası `rhasspy/vosk-models` ~8MB/s**. Mehmet "kalite çok daha iyi".
- **Model yönetimi UX:** Vosk indirme onay+ilerleme; **Ayarlar ekranı** (`lib/features/settings/`, `ManagedModel`+`ModelRegistry`) tüm modeller gör/indir/sil. Dil-başına Vosk (`vosk_models.dart` registry: en/tr/es/fr/de/it). Cihaz ✅ "hepsi indirilip silinebiliyor".
- **Vosk = ANA STT + Whisper fallback (Mehmet kararı):** `VoskSttEngine` + `HybridSttEngine` router (dil→Vosk varsa Vosk, yoksa Whisper; initialize TEMBEL). lecture/push_to_talk/session_test bağlandı. Cihaz ✅ "transkript gayet yeterli" → **STT KATMANI TAMAM.**
- **Ders Modu chunk + ilk-kelime (cihaz testi bekliyor):** `StreamingAudioInput` (AudioInput adapter, ~5sn commit, susmayı beklemez) + StreamingMicAudioInput'a **pre-roll buffer** (~400ms). STT rozeti üst barda (Vosk/Whisper görünürlüğü — Mehmet "hangi model çalışıyor görünmüyordu" diye fallback test edemiyordu).
- **LLM çeviri (Tier 3) spike (cihaz testi bekliyor):** `flutter_gemma` build ✅ (APK 656MB). Gemma gated (401) → **Qwen2.5-1.5B non-gated**. `LlmTranslateTestScreen` (indir+çevir+süre). **3-KATMAN kararı:** MLKit/orta-NMT/LLM.

**Bıraktıklarım:** Mehmet oturumu bilinçli kapattı ("aceleye getirmeyelim"). Son düzeltmeler de cihazda: `FlutterGemma.initialize()` main()'e eklendi (init hatası fix), 8 dev test ikonu tek 🧪 PopupMenuButton'a toplandı (AppBar overflow fix). analyze temiz, 89/89 test. **İKİ CİHAZ TESTİ HENÜZ YAPILMADI (Mehmet sonraki oturumda yapacak — HATIRLAT):** (1) Ders Modu chunk'lı transkript + ilk-kelime + STT rozeti, (2) LLM Çeviri Test (Qwen kalite+hız, SD860).

**Sıradaki modele not — ⚠️ İLK İŞ İKİ HATIRLATMA (Mehmet açıkça istedi):**
1. **Mehmet'e iki cihaz testini hatırlat** (yukarıda): Ders Modu + LLM Çeviri Test. Henüz yapmadı.
2. **Mehmet Qwen YERİNE GEMMA kullanmak istiyor.** LLM tier'ı Gemma'ya çevir. ENGEL: Gemma3-1B-IT litert-community **gated** (anon HTTP 401). Çözüm: ücretsiz HF token (huggingface.co/settings/tokens) + Gemma lisansını bir kez onayla → token'ı `FlutterGemma.initialize(huggingFaceToken: ...)` VE/VEYA `installModel().fromNetwork(url, token: ...)`'e ver + `_modelUrl`'i `Gemma3-1B-IT_..._q4_..._ekv1280.task`'e, `ModelType.qwen`→`ModelType.gemmaIt`'e çevir (`LlmTranslateTestScreen`). Mehmet token'ı sağlayacak/onaylayacak.

**KURULUM:** `flutter install` MIUI'de `INSTALL_FAILED_USER_RESTRICTED` → **`adb install -r -d <apk>` GÜVENİLİR** (adb: `~/AppData/Local/Android/Sdk/platform-tools/adb.exe`). **İŞ (testler sonrası):** LLM kalite/hız sonucuna göre → Tier2 orta-NMT (argos_translator_offline=NLLB/opus-mt aday) + 3-motor selector (TranslationEngine swappable + SessionQuality bağla). **flutter_gemma APK'yı 656MB yapıyor** — Tier3 tutulmazsa kaldır. **Roadmap Polish "🌐 ÇEVİRİ MOTORU ZAYIF" + "🔤 Vosk" güncel; memory project_hermes güncel.**

---

## 2026-05-31 (akşam, 2. oturum) — Claude Opus 4.8

**Devraldım:** 6r-d (dual-mic) cihazda başarısız → pivot kapandı. Sıradaki: 6r-e (Bas Konuş push-to-talk + Ders Modu, dual-mic'siz), açılışta Mehmet'e `PushToTalkAudioInput`'un `AudioInput` interface'ine oturuşunu sun.

**Yaptıklarım (uzun, üretken oturum — Step 6 bitti + Step 7 başladı):**
- **6r-e:** `PushToTalkAudioInput` (record ham PCM16, VAD yok, ek `pressTalk`/`releaseTalk`, `PttRecorder` abstraction) + **Manager çift yönlü** (`event.source` routing) + portre kilidi. PTT test ekranı (iki-yarı 180°) ile cihaz smoke ✅ ("2 test de başarılı").
- **6r-f:** `TitleGenerator` (timestamp fallback + hybrid online-seam; Gemini Step 9) + Manager `end()`'de başlık + repository `setTitle`.
- **6r-g:** DB Test ekranı başlık üretip gösterir, cihaz smoke ✅.
- **6r-h:** `SessionTestScreen` Manager tam pipeline gerçek motorlarla — cihaz smoke ✅ ("her şey harika"). **→ Step 6 refactor BİTTİ, 88/88 test.**
- **Step 7 burst-1:** `HomeScreen` mod kartları → `LanguageSelectScreen` → placeholder; Manuel→TranslationTestScreen. main.dart home değişti. Cihaz ✅ ("her şey çalışıyor", dil listesi ileride genişletilecek).
- **Step 7 burst-2:** **Bas Konuş gerçek ekranı** (`lib/features/push_to_talk/push_to_talk_screen.dart`) — iki yarı + üst 180° + şeffaf/sadece-basılınca butonlar + DM-box chat + çeviri karşı tarafa + gerçek Manager + TTS + turn-based. Cihaz ✅. Revize: AppBar→ortada minimal pill, immersive tam ekran, bottom overflow + üst boşluk (`primary:false`) fix.
- **Step 7 burst-3:** **Ders Modu ekranı** (`lib/features/lecture/lecture_screen.dart`) — pre-start TTS toggle (default kapalı=`SilentTtsEngine`), sürekli dinleme + canlı altyazı + auto-scroll. UI "yeterli" → **Mehmet UI'ı erteledi, kaliteye geçildi.**
- **Whisper kalite+hız:** KÖK NEDEN: Manager `quality`'yi Whisper modeline bağlamıyordu → Ders tiny kullanıyordu. Fix: `Manager.start()` → `stt.setSpeedMode(full→small)`. Cihaz: "çok daha doğru" ama yavaş → **hız tuning**: `WhisperCppEngine` `WhisperController` bypass, `Whisper` doğrudan `noFallback:true`+8 thread → "fark edilir daha hızlı". 88/88 test.
- **STREAMING (sorun #3) ✅:** `StreamingMicAudioInput` (record.startStream + VAD audioStream, ~2sn partial + ~5sn `maxSegmentDuration` commit + sessizlik tail) + `StreamingTestScreen`. Cihaz "her şey yolunda".
- **‼️ TÜRKÇE TANIMA → ASR PİVOTU:** Mehmet TR "aşırı saçmalıyor" (EN mükemmel), iki-model OOM crash → "daha akıllı model, mini LLM?". Açıkladım: TR saçmalama=STT(Whisper), LLM transkript yapmaz. Araştırma: flutter_gemma mini-LLM çeviri mümkün ama transkripti çözmez; online Gemini multimodal çözer (online). **KARAR: alternatif offline ASR (Vosk/sherpa), önerim Vosk TR.** streaming_test dual-engine→tek motora indirildi (crash fix).

**Bıraktıklarım:** **Step 6 ✅ + Step 7 navigasyon/Bas Konuş/Ders ekranları ✅ + transkript doğruluk&hız ✅ + streaming ✅.** analyze temiz, 88/88 test, pubspec temiz. **AÇIK İŞ YOK ama AÇIK KARAR/PİVOT VAR: Türkçe için alternatif ASR (Vosk).** `flutter pub add vosk_flutter` **ağ hatası verdi** (pub.dev erişilemedi — internet/proxy sorunu) → eklenemedi, pubspec'e dokunmadı. Step 7 UI Mehmet'çe ertelendi (kaliteye odak). Bas Konuş son fix'leri (overflow+üst boşluk) deploy edildi, Mehmet teyit etmedi.

**Sıradaki modele not — İLK İŞ: Vosk Türkçe ASR de-risk.** (1) İnternet düzelince `flutter pub add vosk_flutter` (bu oturumda ağ hatasıyla eklenemedi). (2) Türkçe model `vosk-model-small-tr-0.3` (indir veya asset). (3) `VoskTestScreen` de-risk: vosk native streaming `SpeechService.onPartial/onResult`, sadece Türkçe — Whisper/çeviri YOK. Cihazda TR Vosk doğruluğunu Whisper'a karşı kıyasla (6r-d gibi de-risk, cihaz sürpriz riski). Vosk yetmezse sherpa-onnx. **KRİTİK ANLA:** TR sorunu STT katmanı; LLM/çeviri değişikliği TR'yi DÜZELTMEZ. Whisper EN için + hız tuning (small/noFallback/8-thread) KALIYOR. **Çalışma ritmi SHORT BURSTS.** **Açık kararlar (roadmap Polish birebir):** 🎨 Step 9 tasarım baştan ("liquid glass"); çeviri MLKit şimdilik, akıllı çeviri (flutter_gemma/Gemini) sonra; canlı transkript Ders Modu entegrasyonu (burst-1b, StreamingMicAudioInput hazır). Throwaway test ekranları (push_to_talk_test, session_test, dual_mic_test, streaming_test) Step 7/ASR netleşince silinebilir. build/install arka planda + bekçi until-loop (bu oturumda 12+ deploy sorunsuz).

---

## 2026-05-31 (akşam) — Claude Opus 4.8

**Devraldım:** Önceki oturum (kapatıldı, "çok uzun sürüyordu") 6r-d-faz1 kodunu yazmıştı (transport+RMS, VAD yok) ama cihaz smoke'u yapılmamıştı. Diskte HermesDualMicPlugin.kt + dual_mic_channel.dart + dual_mic_test_screen.dart vardı, analyze clean, 69/69 test ✅.

**Yaptıklarım:**
- Dosyaların diskte sağlam olduğunu doğruladım, cihaza build + kurulum yaptım (MIUI "USB ile kurulum" iznini Mehmet telefondan onayladı — ilk denemede `INSTALL_FAILED_USER_RESTRICTED` aldık).
- **6r-d-faz1 cihaz smoke testi yapıldı → ❌ BAŞARISIZ.** İlk MIC/MIC testleri: kablolu→sadece A canlı, BT→sadece B canlı, kulaklık yok→iki bar birlikte. Tek route şüphesi üzerine **AudioSource'u parametrik yaptım** (Kotlin `MicRecorder` audioSource param + method channel `primarySource`/`secondarySource`; Dart `DualMicSource` enum; test ekranına 2 dropdown). 5 kombinasyon × kablolu+BT denendi: **hiçbirinde kulaklık mic + dahili mic eş zamanlı bağımsız canlı değil.**
- **Kök neden netleşti:** Poco X3 Pro tek giriş route'u servis ediyor. İnternetteki stereo `CAMCORDER` numarasının iki **dahili** mic verdiğini (kulaklık+telefon değil) Mehmet'e açıkladım.
- **Mehmet pivot kararı: Voice Translator (Yöntem B) → Faz 2.** Faz 1 = Ders Modu + Bas Konuş + Manuel.
- Roadmap baştan güncellendi: Son güncelleme, Aktif İş, "Sıradaki tur açılışında" (eski 6r-d planı ARŞİV'e alındı, yeni dual-mic'siz 6r-e/f/g/h tanımlandı), Risk tablosu (dual mic ❌ KAPANDI), Faz 2 listesi (Voice Translator eklendi), **Polish Notları'na birebir geri bildirimli "6r-d-faz1" entry**. Memory `project_hermes` Son durum + Konuşma Modu mimarisi satırı güncellendi.

**Bıraktıklarım:** 6r-d kapandı (kod silinmedi, deney/negatif-bulgu + Faz 2 başlangıcı olarak duruyor, ana akışa bağlı DEĞİL). analyze clean, 69/69 test ✅ (dual_mic deney kodunun testi yok — geçici harness). Açık iş yok. **Sıradaki: 6r-e — Manager mod davranışları (Bas Konuş turn-based tek mic + Ders Modu sürekli dinleme), dual-mic'siz.**

**Sıradaki modele not:** 6r-e'ye girmeden Mehmet'e `PushToTalkAudioInput`'un mevcut `AudioInput` interface'ine nasıl oturacağını sun (buton state → utterance). Mevcut `SingleMicAudioInput` Ders Modu için zaten hazır. Mod UI tasarımı (Bas Konuş ekran bölme + üst yarı 180° + Ders live subtitle) Step 7'de Mehmet ile birlikte. **Token ekonomisi uyarısı:** Mehmet bu oturumu ve öncekini "çok uzun sürüyor" diye kapattı — kısa tut, gereksiz dosya okuma yapma, kod ağırlıklı ilerle. Build/install komutlarını arka planda çalıştır (bloke etme), `until`-loop bekçisiyle sonucu yakala.

---

## 2026-05-31 — Claude Opus 4.8

**Devraldım:** 2026-05-30 akşam entry'sinden — 6r-a/b/c ✅, 69/69 test. Sırada **6r-d (DualMicAudioInput native Kotlin plugin) — KRİTİK kontrol noktası**.

**Yaptıklarım:** Bu bir **keşif/hazırlık turu oldu, KOD YAZILMADI.** (Bir tool batch'i bash hatasından iptal olunca Kotlin plugin + MainActivity taslakları diske düşmedi — `git status` ile doğruladım, 6r-d'ye ait hiçbir dosya yok, sadece önceki turun değişiklikleri duruyor.) Tur boyunca:
- Starter kit + roadmap + memory + `audio_input.dart` + `single_mic_audio_input.dart` + `vad_controller.dart` okundu, bağlam tazelendi.
- **`vad: ^0.0.7+1` paket kaynağı incelendi** → kritik keşif: `VadHandler.startListening(audioStream: Stream<Uint8List>?)` ham PCM16/16kHz/mono stream kabul ediyor, dahili recorder'ı bypass ediyor (`vad_handler.dart:147,163,270-283`). Native plugin çıktısını doğrudan VAD'e besleyebiliriz. (Paket yapısı `lib/src/core/...` altında; eski sandığım `vad_handler_non_web.dart` yok.)
- Mehmet 2 karar verdi: **(1)** 6r-d'yi 2 faza böl — önce transport+RMS yaz, cihazda concurrent capture'ı doğrula, SONRA VAD'li tam hali (varsayım üstüne kod yığma); **(2)** kulaklık = USB/kablolu öncelik + Bluetooth SCO fallback.
- **Roadmap güncellendi:** "Son güncelleme" + "Sıradaki tur açılışında" bölümüne 4 maddelik (A faz bölme, B vad audioStream keşfi, C kulaklık sırası, D bağlama noktaları) ⚠️ blok eklendi. Bir sonraki tur bunu okuyup sıfırdan yazsın.
- TaskCreate ile 8 alt-task açıldı (6r-d.1…8), hepsi pending.

**Bıraktıklarım:** 6r-d kodu HİÇ başlamadı, tertemiz başlangıç. Kulaklık şu an Mehmet'te yok → cihaz smoke (concurrent capture, asıl karar anı) ertelendi. Kod (faz1 transport+RMS) kulaklık olmadan da yazılabilir, ama smoke testi kulaklık gelince yapılır. **6r-d ✅ ancak cihaz smoke geçince olur — kod yazılması yeterli değil.**

**Sıradaki modele not:** Roadmap "Sıradaki tur açılışında" ⚠️ bloğunu (A/B/C/D) MUTLAKA oku — bu turun tüm değeri orada. Mehmet'in faz kararına sadık kal: **faz1 (transport+RMS, VAD YOK) → cihazda concurrent capture doğrula → faz2 (VAD'li DualMicAudioInput).** vad paketinin `audioStream` parametresi faz2'yi kolaylaştırır (iki ayrı VadHandler, recorder bypass). `MainActivity.kt` hâlâ boş tek satır (`class MainActivity : FlutterActivity()`) — `configureFlutterEngine` override + plugin register lazım. Test ekranı AppBar bağlama pattern'i `main.dart:267` (VAD/DB IconButton'ları örnek). Token ekonomisi: Mehmet bu turu bilinçli kısa kapattı, sıradaki tur kodla başlasın.

---

## 2026-05-30 (akşam) — Claude Opus 4.7

**Devraldım:** 2026-05-17 akşam entry'sinden — Step 6 kod tarafı 6a-6d bitmiş, tasarım pivotu açık (Headset Mode Yorum X/Y/Z?). Proje konumu MOBS-Hermes git repo'su altına taşınmış (Mehmet daha önce yapmış). Hafıza dosyaları eski projects/ klasöründeydi — yeni konuma kopyaladım ve içlerindeki proje yollarını güncelledim.

**Yaptıklarım:**

Bu uzun bir tasarım + refactor oturumuydu. Sırayla:

**Tasarım konsolidasyonu (Mehmet kararları):**
- Headset Mode tartışması kapandı — Mehmet 3. yorum verdi: **sıralı (turn-based) konuşma + dil tabanlı veya çift mic kimlik tespiti**, sonra **Yöntem B'yi** (kulaklık + telefon çift mic eş zamanlı dinleme) seçti. POC öncesi yapmayacağız, sorun çıkarsa o zaman düşüneceğiz.
- **3 mod kesinleşti** (isimler subject-to-change ama development boyunca korunacak):
  - **Ders Modu** — tek yönlü, live subtitles + transkript + Gemini özet, opsiyonel kulaklığa sesli çeviri
  - **Voice Translator** — kulaklık zorunlu, çift mic (A=kulaklık→sağ, B=telefon→sol), kulaklıktan otomatik TTS, sağ taraf play butonu telefon hoparlöründen seslendirir, başlık otomasyonu (Gemini varsa içerikten, yoksa timestamp)
  - **Bas Konuş Modu** — kulaklıksız, portrait, ekran ortadan yatay ikiye bölünür, ortada görünür buton **YOK** — her yarı kendi tarafının görünmez bas-konuş alanı, üst yarı içerik 180° döndürülmüş (`RotatedBox(quarterTurns: 2)`). Mehmet "ahize modu" derken oryantasyona değil içerik akışına atıf yapıyordu — TÜM modlar portrait, landscape lock zorunlu.
- **Manuel Çeviri** = mevcut `TranslationTestScreen`, 3 modun yanında bağımsız ana ekran erişimi olarak kalır
- **SessionMode (3) + SessionQuality (fast/full)** 2 boyutlu enum mimarisi — Mehmet "fast/full bu 3 modun her birinin içinde switch olarak" diye yönlendirdi
- **Language ID kararı: SAKLA, kullanma** — kod `lib/core/engines/language_id/` altında + paket + 8 testi olduğu gibi kalır. Step 9 polish'de **(1) yanlış dil uyarısı** + **(2) hibrit ders modu** için bekliyor. Roadmap Polish Notları'na 📌 dokümanlı.
- **iPhone Faz 1'de test edilmiyor** (Mac yok, Codemagic yavaş). Geliştirme Poco X3 Pro'da devam. Voice Translator iOS Faz 2.

**Dokümanlar:**
- `HERMES_KONUSMA_MODU_TASARIM.md` baştan yazıldı (~230 → ~400 satır) — 3 mod detay (her birinin akışı + UI + audio input + quality default + feedback loop çözümü), AudioInput strategy, DualMicAudioInput plan, schema v2 migration, 3 mod data flow diyagramları, riskler, test senaryoları, sub-step implementasyon sırası
- `HERMES_ROADMAP.md` Modlar bölümü + Aktif İş + Sıradaki tur + Polish Notları (4 cihaz testi entry'si: 6r-a, 6r-b, 6r-c, ve dual mic için bekliyor) + Risk tablosu güncellendi

**Kod (Step 6 refactor sub-step'leri):**
- **6r-a ✅** Manager'dan `LanguageDetector` koparıldı (import + field + constructor param + `_classifyParticipant` silindi, hardcode `sourceSpeaker`, Whisper'a explicit `language: sourceLanguage`). LangID dosyaları ve paket dokunulmadı. Test 58/58 ✅, cihaz smoke ✅
- **6r-b ✅** `SessionMode { lecture, voiceTranslator, pushToTalk }` + yeni `SessionQuality { fast, full }`. Drift schema v1→v2: `quality` (default 'fast') + `title` (nullable) column'ları, `MigrationStrategy.onUpgrade` ile eski `'fast'/'full'` değerleri yeni evrene remap (`'fast' → voiceTranslator+fast`, `'full' → lecture+full`). Manager `quality` parametresi alır, `_speakWithMode` mantığı mode'tan quality'ye taşındı. `build_runner` regen. 65/65 test ✅ (7 yeni: createSession quality, SessionQuality enum, migration SQL davranışı + sıralama regression koruması). Cihaz smoke ✅ — eski oturumlar yeni modlarla doğru göründü (Mehmet: "her şey testde istediği gibi çalışıyor")
- **6r-c ✅** `lib/core/audio/audio_input.dart` (AudioInput interface + AudioUtteranceEvent + AudioSource enum {primary, secondary}) + `single_mic_audio_input.dart` (VadController sarmalı; ara state'leri yutar, source etiketli utterance yayar). Manager constructor `vad: VadController` → `audioInput: AudioInput`, `_subscribeToVad` → `_subscribeToAudioInput`. Test'lerde `FakeVadController` → `FakeAudioInput`. 69/69 test ✅ (4 yeni: SingleMicAudioInput), cihaz smoke ✅

**Drift uyarısı (bilinmesi gereken):** Repository test'inin migration SQL grubunda setUp/tearDown DB'sinin yanında test içinde ikinci `AppDatabase.forTesting` açılması "multiple databases" warning'ini tetikliyor. Production build'lerde yok, test'leri etkilemiyor, ama temizlik isterse ya `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` ya da migration test'lerini ayrı grup + ayrı setUp ile izole et.

**Bıraktıklarım:** Üç sub-step kapalı, açık iş yok, test/analyze/cihaz tamam. Sıradaki **6r-d — DualMicAudioInput native Kotlin plugin — KRİTİK kontrol noktası**. Roadmap "Sıradaki tur açılışında ne yapılır" 7 adımlık plan içeriyor: plugin iskeleti (MethodChannel + 2 EventChannel), Kotlin dual `AudioRecord` + `setPreferredDevice`, Dart wrapper, AndroidManifest izin kontrolü, geçici test ekranı, Poco X3 Pro'da concurrent capture doğrulama smoke. Başarısızsa Mehmet pivot kararı verir (Voice Translator Faz 2'ye ertelenir veya Yöntem A'ya dönülür).

**Sıradaki modele not:** 6r-d'ye girmeden önce starter kit'i (`new_session_starter_kit/00_README.md` → 01 → 02 → 03 → bu punch_board) gözden geçir, sonra `HERMES_KONUSMA_MODU_TASARIM.md` §3.2.2 (DualMicAudioInput planı) + §5 (risk satırı) + §7 (sub-step tablosu) oku. Mehmet'in onayını alarak başla — plugin yazımı 3-5 saatlik bir iş, sonunda cihaz testi kritik. Eğer cihazda fail olursa Mehmet'e iki opsiyonu net sun (Voice Translator Faz 2'ye ertele veya Yöntem A'ya pivot), kendisi karar versin. Eğer pass ederse 6r-e (Manager 3-mod davranışları + AudioSource → sağ/sol routing), 6r-f (TitleGenerator), 6r-g (DB Test ekranı `title` field UI), 6r-h (entegrasyon cihaz testi) sırayla devam. **Hatırlatma:** Mehmet step-by-step çalışır, her sub-step için flutter analyze + flutter test + cihaz smoke + Polish Notları'na birebir feedback kaydı zorunlu (feedback memory kuralı).

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
