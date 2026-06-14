# Hermes — Yol Haritası

**Canlı statü dokümanı.** Her implementasyon adımı sonrası güncellenir. Tasarım kararları için: `HERMES_KONUSMA_MODU_TASARIM.md`. Teknoloji seçimleri için: `HERMES_TEKNIK_REFERANS.md`.

**Son güncelleme:** 2026-06-13 (#4) — **🩹 3. CİHAZ TESTİ DÜZELTMELERİ (analyze temiz, 196 test, APK build, Poco'ya kuruldu):** (A) Home header overflow → `FittedBox(scaleDown)` cihaz-agnostik ✅; (2) eyebrow → `connectivity_plus` (canlı, takılma yok) + 10 dil (ar/zh/ja/ru dahil) + belirgin fade+slide ✅; (5) Görsel Çeviri foto-üstü kontroller daha şeffaf (glass 42) + compact + kenarlara yakın ✅. **(1) AÇILIŞ SİYAH EKRANI HÂLÂ AÇIK** — 4 yöntem denendi (native launch_bg + Android12 windowSplashScreenBackground + FlutterGemma.initialize'ı arka plana alma + night launch_bg açık), cihazda hâlâ ~3sn siyah + 1sn logo; sıradaki tur: flutter_native_splash / release karşılaştırması / MainActivity setKeepOnScreenCondition (Polish'te detay). (3/4/6/7 önceki turda onaylandı.) ↓ ÖNCEKİ: 2026-06-13 (#3) — **🧠 BÜYÜK FEEDBACK PAKETİ (7 madde) KODLANDI (analyze temiz, 196/196 test, arm64 debug APK build; CİHAZ SMOKE BEKLİYOR).** Mehmet'in 2. cihaz testi feedback'i (Polish'te birebir) ele alındı: (1) **RAM disiplini + crash guard** — `RamManager` (NLLB daima resident; offline LLM özetinde `withLlmRam`=NLLB unload→LLM→LLM unload→NLLB reload; canlı oturum öncesi `freeForLiveSession`=LLM unload; `freeAll`); `runZonedGuarded` + `ErrorWidget.builder` dostça "cihaz tam kapasite" ekranı (kırmızı çökme yok); canlı hata görünümlerine "RAM'i boşalt ve tekrar dene"; crunch_runner özet adımı NLLB swap'li. (2) **Banner/overscroll** — `_NoGlowScrollBehavior` (mor glow/stretch yok), HgGlass açık-mod gölgesi nötr (mor-mavi→ink). (3) **Home eyebrow** — `_OnlineBadge`: çevrimdışı/çevrimiçi kelimesi 6 dilde fade ile döngü; offline=coral, online=yeşil. (4) **Manuel** — scroll yerine Expanded sonuç alanı (ekran dolu), input tek-çerçeve (TextField tema kutusu kapatıldı). (5) **Boş transkript** — kök neden: ekran `dispose()`'ta `_db.close()` senkron çalışıp `deleteSessionIfEmpty`'yi boşa düşürüyordu → DB kapatma artık session dispose SONRASINA alındı (conf/smalltalk/ptt). (6) **Görsel Çeviri tam overlay** — fotoğrafsızken boş preview yok (sade CTA); fotoğraf çekilince tüm ekran foto + üstte şeffaf cam kontroller (başlık/dil/motor/sonuç/çek-galeri); bloklar fotoğrafta. (7) **Splash** — animasyonlu açılış (`SplashScreen`) + NLLB arka planda preload (kullanıcı beklemez); tema toggle kalıcı (önceki turdan). APK: `build/app/outputs/flutter-apk/app-debug.apk`. ↓ ÖNCEKİ: 2026-06-13 — UI RESTYLE TUR 2 KALANI (a–f) + Görsel Çeviri Lens overhaul. PTT split / Manuel Çeviri / ModelTierSelector / low_ram dialog hepsi liquid-glass HG'ye geçti; tema toggle artık kalıcı (shared_preferences). **Yeni feature — Görsel Çeviri Lens:** `OcrResult`'a blok kutuları (`OcrBlock`=metin+`Rect`) + görüntü boyutu eklendi; foto cam viewport'ta gösterilir, her metin bloğu tıklanabilir kutu, dokunulan blok çevrilip kutunun üstüne bindirilir (Google Lens tarzı) + altta sonuç kartı; auto kaynakta dil blok bazında tespit. OCR testleri yeni akışa güncellendi (4/4). APK: `build/app/outputs/flutter-apk/app-debug.apk`. ↓ ÖNCEKİ: 2026-06-10 — **☁️ (B) DÜŞÜK-RAM CRUNCH FALLBACK: Gemini API key ile çevrimiçi crunch + transkript kopyala (analyze temiz, 188/188 test, CİHAZSIZ KOD İŞİ — Mehmet yemek molasında).** Roadmap'in "hâlâ açık" tek büyük cihazsız işi bitti. Zayıf/düşük-RAM cihazlar yerel Gemma3-1B'yi çalıştıramazsa (Phi OOM, gemma-4 SD860 native crash) artık kullanıcının **kendi Gemini API anahtarıyla internet üzerinden** crunch yapabilir. **Tasarım — global toggle YOK:** Ayarlar'da anahtar varsa detay ekranında çevrimiçi butonlar çıkar, yoksa çıkmaz. **`CrunchService` aynen yeniden kullanıldı** (`run`/`translate` enjekte edilebilir → Gemini backend olarak takıldı; chunk/reduce/başlık/özet promptları değişmedi, çevrimiçi yolda `maxCharsPerChunk`=4000/`reduceCharBudget`=8000 → daha az API çağrısı). **Yeni:** `lib/core/services/gemini_key_store.dart` (`HfTokenStore` aynası, prefs `gemini_api_key`), `lib/core/services/gemini_client.dart` (`GeminiClient.generate` → `gemini-2.0-flash` REST `generateContent`, `http.post`, `GeminiException` 400/403→geçersiz/429→kota/boş-candidates→engellendi; `http.Client` enjekte → test). `CrunchService.languageName` public (çeviri prompt'u dil adı için). **`crunch_runner.dart`** + iki runner: `runOnlineCrunch` (yerel model YOK — Gemini çeviri+özet+başlık → `setCrunchResult`) + `runOnlineSummarize` (hibrit: yerel NLLB çevirisini Gemini ile özetle → `setCrunchSummary`). **`conference_detail_screen.dart`:** anahtar varsa raw'da `[Gemini ile Çevir & Özetle]`, çevrildi'de `[Gemini ile Özetle]` (outline+bulut, "internet · veri Google'a gider" notu); anahtar yoksa Ayarlar'a yönlendiren ipucu; **transkript başlığına "Kopyala" butonu** (her zaman, `Clipboard.setData`+snackbar — manuel fallback). **`settings_screen.dart`:** "Çevrimiçi Özet (Gemini)" bölümü (maskeli anahtar durumu + ekle/düzenle + gizlilik notu) + `_GeminiKeyDialog` (`_HfTokenDialog` aynası). 10 yeni test (gemini_client 6 + gemini_key_store 4). **CİHAZ SMOKE BEKLİYOR (Mehmet dönünce):** Ayarlar→Gemini anahtarı yapıştır → bir konferans/oturum detayı → "Gemini ile Çevir & Özetle" çeviri+özet+başlık çıkıyor mu (internet); yerel çeviri varsa "Gemini ile Özetle" hibrit; "Transkripti Kopyala"; geçersiz anahtar→net hata. **NOT:** anahtar shared_preferences düz metin (HfTokenStore ile aynı; kullanıcının kendi anahtarı, APK'ya gömülmez). ↓ ÖNCEKİ: 2026-06-09 (8) — **🔧 3 İŞ: SpeechService re-entry çökme fix + Crunch 2-adım + Vosk EN de-risk (analyze temiz, crunch testleri 9/9, APK build).** Mehmet bildirdi: (1) Konferans ısınmadan **sistem geri tuşuyla** çıkıp tekrar girince `SpeechService instance already exist` çökmesi; (2) crunch ikiye bölünsün; (3) EN için daha iyi Vosk modeli (önce daanzu). **P1 FIX:** `vosk_streaming_controller.dart` statik tekil nöbet (`_active`) + idempotent/memoized `dispose` + `load()` önce önceki SpeechService'i tam dispose eder → ekran nasıl kapanırsa kapansın çökme biter. **P2:** crunch 2 adım — `CrunchService.translateTranscript`(NLLB) + `summarize`(Gemma, ana hikaye/önemli noktalar promptu); `repo.setCrunchTranslation`/`setCrunchSummary`; `crunch_runner` `runDeepTranslate`+`runSummarize`; **detayda merkezi** durum-tabanlı 2 buton; bitiş+arşiv inline crunch yapmaz → detaya yönlendirir ("Crunch now" kaldırıldı). **P3:** 🧪 `vosk_en_derisk_screen` (canlı mic, model seçici: small-0.15/daanzu/0.22) + `VoskStreamingController.load(modelPathOverride:)`; daanzu (~922MB) indirildi+açıldı (1.5GB). **MEHMET/CİHAZ BEKLİYOR (USB koptu):** daanzu push (1.5GB) + APK kur + 3 smoke (çökme/crunch-2adım/vosk-en daanzu vs small). ↓ ÖNCEKİ: 2026-06-09 (7) — **🧠 CRUNCH MODELİ DE-RISK + GEMMA3-1B BAĞLANDI (analyze temiz, 174/174 test, APK Poco'da).** Phi-4 in-app indirme %70-80'de sessiz çöküyor + yetim ~3GB bırakıyordu (Mehmet bildirdi). Kök: flutter_gemma native indirici büyük dosyada çöküyor + HF `.task` modelleri Xet CDN'de (dart:io TLS kırılır) + Phi-4 3.76GB Poco'da OOM. **Yeni crunch de-risk** (🧪 `crunch_derisk_screen.dart`, adb-push + `fromFile`, aynı TR örneği gerçek crunch promptlarıyla): **Gemma3-1B-IT q8 = KAZANAN** (Mehmet "yeterli"); Qwen2.5-1.5B elendi (bozuk karakter+soru sorma), Phi-4 OOM çöktü, gemma-4-E2B `.litertlm` native invoke hatası (SD860 uyumsuz). **Uygulama:** `LlmModelDef.crunch`=`gemma3` (yeni def, **selfHosted** GH Release); LLM indirme selfHosted→**streamed indirici + `fromFile`** (native çökme + Xet biter; kullanıcı token gerekmez, re-host), HF tier'ları fromNetwork'te kaldı. Ayarlar'da tek LLM "Özet Modeli (Crunch)"=Gemma3-1B (Qwen/Gemma/Phi listeden çıktı). **MEHMET'TE (engelleyici):** `Gemma3-1B-IT_multi-prefill-seq_q8_ekv1280.task` (1005MB, `_scratch/crunch_derisk/`) mevcut `nllb-600m-int8-v1` GH release'ine asset olarak eklenecek. **CİHAZ TEST:** yüklenince Ayarlar→Özet Modeli→Gemma3-1B in-app indir → bir oturum crunch → kalite. **AÇIK:** (B) düşük-RAM fallback = transkript kopyala + kendi Gemini API key arayüzü (online crunch) — YAPILMADI. ↓ ÖNCEKİ: 2026-06-09 (6) — **🌐 FAZ B — IN-APP İNDİRME HOST'U (NLLB, analyze temiz, APK Poco'da).** NLLB int8 (~1.3GB) artık **GitHub Release**'ten in-app inecek (eskiden yalnız adb-push). `nllb_model_manager.dart` `files` URL'leri girildi: `https://github.com/Runomm/MOBS-Hermes/releases/download/nllb-600m-int8-v1/<dosya>` (4 asset: encoder/decoder/decoder_with_past `_quantized.onnx` + `sentencepiece.bpe.model`). `download()` zaten streamed (`.part`→atomik rename); GitHub 302 redirect dart:io http'de otomatik izlenir (Xet sorunu yok). App kendi indirince dosyalar **app-owned** → Android 15 FUSE/run-as gereği yok. `_NllbManagedModel.download` bayt-ağırlıklı ilerlemeye çevrildi (419/470/445/5 MB farkı → çubuk+hız/ETA gerçekçi). **MEHMET'TE (engelleyici):** GitHub Release'i web'den oluştur (tag birebir `nllb-600m-int8-v1`) + 4 dosyayı `_scratch/nllb600_int8/` + `_scratch/sentencepiece.bpe.model`'den sürükle (tokenizer.json YOK). **CİHAZ TEST BEKLİYOR:** Release yüklenince Ayarlar→NMT→NLLB-600M indir → in-app iniyor + çalışıyor mu. ↓ ÖNCEKİ: 2026-06-09 (5) — **🎨 F3b (Whisper indirme ilerlemesi) + FAZ 4 (UI BEYAZLAŞTIRMA) (analyze temiz, 169/169 test, APK build).** **F3b:** Mehmet F3 smoke'unda "hız/%/ETA görünmüyor" dedi → `managed_model.dart` `_WhisperModel.download` artık `whisper_ggml`'in consolidate yolu yerine NLLB/Vosk kalıbıyla **streamed-http** indiriyor (`_model.modelUri`→`.part`→atomik rename, byte sayacı + onProgress) + `supportsProgress=true` → Ayarlar'da Whisper small için %/hız/ETA otomatik çıkar (UI değişmedi, `DownloadStats`+`sizeMb` zaten vardı). ML Kit imkânsız (GMS), boyut+"indiriliyor…" kalır. **Faz 4 (son büyük iş):** Konferans açık/beyaz tasarım dili app geneline. Yeni `lib/core/theme/app_theme.dart` (`HermesColors` kanonik palet + `hermesLightTheme` global ThemeData: appBar/card/input/divider/text temaları). `conference_theme.dart` `ConferenceColors`→`HermesColors` delege (geriye uyum), `ConferenceTheme`→`hermesLightTheme` sarmalı. `main.dart` `MaterialApp.theme=hermesLightTheme` (dark blok kalktı) + status bar ikonları koyu (açık zemin). Yeni paylaşılan `lib/features/shared/hermes_card.dart` (`HermesCard`); `home_screen` `_ModeCard`→`HermesCard`. Koyu hardcoded renkleri HermesColors'a çevrilen ekranlar: home, Manuel (`main.dart` TranslationTestScreen), language_select, model_tier_selector, settings, ocr_translate, push_to_talk (üst yarı 180° + şeffaf tap korundu; yeşil→success), models_required_gate (beyaza-yakın metin görünmez oluyordu → düzeltildi). SmallTalk (4 ekran) + Konferans ekranları **zaten** ConferenceColors ile açık tasarımdaydı → HermesColors delegesiyle otomatik. 🧪 dev/test ekranları dokunulmadı (koyu kalır). **CİHAZ SMOKE — F3b ✅ GEÇTİ (Mehmet 2026-06-09 birebir: "tamamdır gayet iyi görünüyo"):** %/MB iyi; ilk turda hız/ETA "kriz geçiriyor gibi yanıp sönüyor ve sallanıyor" + ETA sadece saniye → FIX: `DownloadStats` anlık delta yerine **kümülatif ortalama hız** (titremez, imza `from(fraction, elapsedMs, sizeMb)`) + `etaLabel` (`45sn`/`1dk 35sn`/`2dk`) + ilk 600ms hız/ETA gizli; APK yeniden kuruldu → Mehmet onayladı. 9/9 download_stats testi. **Faz 4 UI:** Mehmet tüm modları detaylı gezmedi ("sıradaki işe geç"), görsel sorun bildirmedi. **AÇIK:** kalan planlı büyük iş yok; sıradaki tur Mehmet'le belirlenecek (öneri: Faz B in-app indirme host'u) — bkz "Sıradaki tur". ↓ ÖNCEKİ: 2026-06-09 (4) — **📥 F3 — MERKEZİ İNDİRME (analyze temiz, 169/169 test).** Mehmet: tüm indirmeler yalnız Ayarlar'dan; mod girişinde model yoksa "Ayarları Aç" yönlendirmesi (inline indirme kaldırıldı). Yeni `lib/features/shared/models_required_gate.dart` (`ModelsRequiredGate`: eksik model adları + "Ayarları Aç" → SettingsScreen → dönünce otomatik yeniden kontrol). İndirme kapıları kaldırıldı: `model_tier_selector` (indir/ilerleme/token çıktı → "Ayarları Aç" CTA), `conference_screen` (`needsModels` gate), `smalltalk_screen` (`needsModels` gate), `main.dart` Manuel (inline MLKit dialog → snackbar yönlendirme). **Ayarlar indirme UI'si zenginleşti:** yeni saf `DownloadStats` (hız/boyut/%/ETA) + `ManagedModel.sizeMb` → kart altında "{inen}/{toplam} MB · {hız} MB/s · ~{eta}s". 4 yeni test (DownloadStats). Test/dev (🧪) ekranları dokunulmadı. **CİHAZ SMOKE BEKLİYOR:** inmemiş modelle mod aç → "Ayarları Aç" + eksik ad; Ayarlar'da indir → hız/boyut/%/ETA; dön → mod hazır. **AÇIK (sıradaki):** Faz 4 UI beyazlaştırma. ↓ ÖNCEKİ: 2026-06-09 (3) — **🎚️ F2 — HANDS-FREE 3-KATMAN (analyze temiz, 165/165 test).** SmallTalk hands-free 2→3 katman (Mehmet spec): **fast**=Vosk×2+MLKit / **full**=Whisper+MLKit (YENİ orta) / **full+**=Whisper+NLLB (eski full). `SessionQuality`'ye `fullPlus` eklendi (DB string, migration yok, `fromDbValue` case'i). `smalltalk_screen.dart` tier-tabanlı motor seçimi (top-level saf `handsFreeUsesWhisper`/`handsFreeUsesNllb` + `_checkModels`/`_download`/`_warmUp` güncel; full artık MLKit indirir, full+ NLLB pre-install ister). Setup'ta 3 kart. **F1 RAM uyarısı koşulu `full`→`fullPlus`** (NLLB yalnız full+'ta). `SmallTalkStreamingSession.quality` opsiyonel param → DB'ye gerçek katman. 6 yeni test (enum roundtrip + tier helper). **CİHAZ SMOKE BEKLİYOR:** 3 seçenek; full=Whisper+MLKit (NLLB uyarısı yok), full+=Whisper+NLLB (düşük-RAM uyarısı + NLLB pre-install). Hands-free full(+) testi R1 (Whisper ~466MB indirme, internet olunca). **AÇIK (sıradaki):** Faz 4 UI. ↓ ÖNCEKİ: 2026-06-09 (2) — **🧠 F1 — DÜŞÜK-RAM (OOM) UYARISI (analyze temiz, 159/159 test).** Poco 8GB'de Bas Konuş "Akıllı" (NLLB ~1.3GB + canlı ASR eşzamanlı) signal 9=OOM ile çöküyordu. FIX: `device_info_plus` (Mehmet kararı — iOS dahil, native kod yok) ile RAM tespiti; yeni `lib/core/services/device_memory.dart` (`DeviceMemory.totalRamMb` + saf `isLowRam` + `kLowRamThresholdMb`=11GB) + `lib/features/shared/low_ram_warning.dart` (`confirmHeavyTierOnLowRam` dialog: düşük-RAM'de "uyar + Yine de kullan/İptal", yüksek/bilinmeyen RAM'de sessiz devam). 3 canlı NLLB giriş noktasına bağlandı: Bas Konuş (`language_select` `_setQuality(full)`), Konferans (`_go(nllb)`), SmallTalk hands-free (`_go(full)`). 5 yeni `isLowRam` testi. **CİHAZ SMOKE ✅ GEÇTİ (Mehmet 2026-06-09: "her şey belirttiğin gibi çalışıyor").** **AÇIK (sıradaki):** F2 hands-free 3-katman, Faz 4 UI. ↓ ÖNCEKİ: 2026-06-09 — **⏱️ ML KIT İNDİRME TIMEOUT + NET HATA UX (analyze temiz, 154/154 test).** Mehmet'in Poco'sunda ML Kit dil paketi inmiyor: model **tamamen GMS** tarafından indirilir, MIUI arka plan kısıtı GMS'i tamamlatmıyor → `downloadModel` Future'ı asla çözülmüyor (sonsuz "indiriliyor"). FIX: `google_mlkit_engine.dart`'a `kMlKitDownloadTimeout` (90sn) + `MlKitDownloadException` + saf `runMlKitDownloadWithTimeout` helper; `ensureModelLoaded` (canlı çeviri) + `downloadLanguage` indirmeleri sarıldı. Timeout aşılınca net hata ("Google Play modeli indiremedi → 'Akıllı (NLLB)' seçin"). Tüm yüzeyler zaten `$e` gösterdiği için UI değişikliği gerekmedi (motor tek nokta). 4 yeni unit test (saf helper). **CİHAZ SMOKE BEKLİYOR (Mehmet, Poco):** ML Kit indir → ~90sn sonra sonsuz dönme yerine net hata; ayrıca paralel GMS testi (Google Çeviri'de TR offline indir + MIUI pil "kısıtlama yok"). **AÇIK (sıradaki):** F1 RAM/OOM uyarısı, F2 hands-free 3-katman, Faz 4 UI. ↓ ÖNCEKİ: 2026-06-07 (gece) — **🔌 NLLB ANA AKIŞA BAĞLANDI (Bas Konuş/Manuel/OCR/Ayarlar).** `NllbTranslationEngine` (TranslationEngine wrapper, paylaşılan singleton, BCP-47↔NLLB eşleme) + `TranslationTier.nllb` ("Akıllı"=NLLB; LLM çeviri bırakıldı, gemma/qwen crunch'ta kalır) + `ModelTierSelector` genelleştirildi (`showMlkit`→`tiers` listesi [mlkit,nllb], tier-tipine göre readiness/indirme) + Bas Konuş full→NLLB + Manuel'e selector + Ayarlar'a `_NllbManagedModel`. analyze temiz, 150/150 test, S25'e kuruldu (Mehmet: "her şey yerli yerinde görünüyor", **detaylı çeviri/crash testi BEKLİYOR**). **AÇIK:** (1) Mehmet detaylı test; (2) Konferans+SmallTalk canlı streaming hâlâ MLKit (öneri: canlı MLKit kalsın, NLLB'yi crunch'a koy); (3) Faz B in-app indirme host'u (model GitHub Release'e — Mehmet, `gh` yok). Detay: punch_board en üst. ↓ ÖNCEKİ: 2026-06-07 (akşam) — **✅ NLLB-600M CİHAZDA ÇÖZÜLDÜ — GERÇEK BUG = BOZUK TOKENIZER (S25 Ultra: Mehmet "kalite ve hız harika").** Mehmet: "NLLB mobilde PC kadar iyi değildi, implementasyon hatalıydı, düzgün yap + S25 Ultra'da test." **Kök neden bulundu:** int8 DEĞİL — `dart_sentencepiece_tokenizer`'ın **`tokenizer.json` loader'ı NLLB'yi yanlış parçalıyordu** (bol `<unk>`, çöp segmentasyon → model çöp girdi → "orta" kalite). PC parite testi kanıtladı: JSON loader ≠ HF; **ham `sentencepiece.bpe.model` + `SentencePieceTokenizer.fromModelFile` + (+1 fairseq offset) == HF birebir.** **FIX:** `NllbOnnxTranslator` artık ham SP model + offset + sabit dil-token haritası (tur/eng/spa/deu/fra/ita) kullanır; decode HF→SP (-1). **int8 seçildi (fp16 DEĞİL):** PC ölçümü int8≈fp16≈PC kalite; **fp16 cihazda OOM** (3.7GB, S25 12GB bile öldü, Poco 8GB imkânsız), int8 ~1.3GB hem S25 hem Poco'ya sığar. `NllbModelManager`→int8 quantized + sp model. **Android 15 FUSE tuzağı:** adb-push edilen dosyalar shell-sahipli → app göremez; **run-as ile app-sahipli kopyalama** şart (klasör+dosyalar u0_a146 olmalı). Cihaz testi GEÇTİ (S25 Ultra, app-owned int8+sp): "kalite ve hız harika". analyze temiz. **AÇIK:** NLLB henüz ana akışa BAĞLANMADI (yalnız 🧪 de-risk ekranı çalışıyor) — sıradaki: TranslationEngine'e wrap + fast/full + son-kullanıcı model dağıtımı (app-owned indirme). Detay: punch_board en üst entry. ↓ ÖNCEKİ: 2026-06-07 — **📷 GÖRSEL ÇEVİRİ (OCR) MODU Faz 1 + NLLB PC KALİTE TESTİ (analyze temiz, 147/147 test; cihazsız oturum — Poco yanında değildi).** **OCR modu Faz 1 KOD TAMAM:** yeni "Görsel Çeviri" modu — foto çek/galeriden seç → ML Kit Text Recognition (cihaz-içi/offline/Latin) → mevcut `createTranslationEngine` ile çevir → orijinal+çeviri kart. Strategy Pattern: `TextRecognizerEngine`+`MlKitTextRecognizer` (`lib/core/engines/ocr/`). Ekran `lib/features/ocr_translate/ocr_translate_screen.dart` (kaynak "Otomatik algıla"=MLKit LangID + `ModelTierSelector`, tüm bağımlılıklar enjekte edilebilir). Paketler: `google_mlkit_text_recognition: ^0.15.0` (commons ^0.11.0 uyumu için 0.15.x) + `image_picker: ^1.1.2`; AndroidManifest CAMERA izni. 4 Fake test + home kartı. **Faz 2 = canlı kamera overlay** (`camera` paketi, aynı arayüz; sonraki oturum, cihazla). **CİHAZ SMOKE Poco gelince.** **NLLB PC kalite testi (cihazsız, "hangi NMT" kararını besler):** `_scratch/nllb_quality_test.py` (transformers fp32/CPU) → `_scratch/nllb_quality_results.md`. BULGU: **NLLB-1.3B daha sadık** (cümle düşürmüyor); **NLLB-600M bazen tüm cümleyi atlıyor** ("keep the change"/"check in" düştü); ikisi de deyimde kusurlu. 1.3B OOM gerçeği değişmedi → karar hâlâ Mehmet'te (Opus-MT de-risk ile birlikte). ↓ ÖNCEKİ: 2026-06-06 (2. blok) — **🔀 ÇEVİRİ KALİTESİ: ONNX PİVOT.** LLM çeviri (Gemma/Qwen) Türkçede yetersiz + Gemma cevap veriyor/saçmalıyor → **Mehmet: LLM çeviriyi bırak, ONNX NMT'ye geç** (fast=SMaLL-100, full=NLLB). **NMT model arayışı (de-risk turu):** **SMaLL-100 ELENDİ** (düzgün KV-cache export'la bile gerçek cümlede saçmalıyor; 330M zayıf). **NLLB-600M** belirgin iyi ama "yeterli değil". **NLLB-1.3B ELENDİ — OOM** (2.75GB int8, 8GB cihaz çöküyor). **→ Opus-MT (Helsinki/Marian, çift-özel ~156MB, OOM yok) kuruldu, TEST BEKLİYOR** (🧪 "Opus-MT de-risk", tr-en). Translator'lar (`NllbOnnxTranslator`/`Small100OnnxTranslator`) cihazda kanıtlandı (KV-cache, hızlı). **Altyapı:** ONNX modelleri Xet CDN'de → PC `adb push` ile harici app dizinine; manager'lar `getExternalStorageDirectory`; PC export toolchain (optimum+torch). **ONNX henüz ana akışa BAĞLANMADI** (yalnız de-risk test ekranları). Ayrıca bu blokta: çeviri context'i (TranslationTurn) + sade few-shot prompt + Bas Konuş fast/full + hata UX (OK'li dialog, motor adı sızdırmaz) + DEV overlay. Detay: punch_board en üst entry. ↓ ÖNCEKİ: 2026-06-06 — **🔧 LLM MODEL YÖNETİMİ NS-1/2/3/5 KOD TAMAM (analyze temiz, 143/143 test, arm64 debug APK Poco'da kuruluyor).** **NS-2 (yanlış-indirili fix):** `LlmTranslationEngine._installedId` artık `listInstalledModels` metadata'sını **diskteki gerçek dosyayla** doğruluyor (`getApplicationDocumentsDirectory`/{filename} var + ≥1MB); dosya yoksa stale metadata `uninstallModel` ile temizlenir → "Model hazır" yanlış pozitifi bitti. **NS-1 (Ayarlar'a LLM):** `managed_model.dart`'a `_LlmManagedModel` (Qwen + Gemma, kategori "Çeviri Modelleri (LLM)") + `ManagedModel.requiresToken` getter (alt sınıflar `implements`→`extends` ile default'u miras alır); Ayarlar dişlisi (`SettingsScreen`) artık LLM'leri gör/indir/sil gösterir, Gemma indirmede HF token dialog'u. **NS-3 (token persistence):** yeni `HfTokenStore` (shared_preferences eklendi; düz metin, RELEASE_CHECKLIST'e madde); `ModelTierSelector` token kutusunu kayıtlıdan otomatik doldurur + indirmede kaydeder; Ayarlar dialog'u da kaydeder. **NS-5:** Bas Konuş zaten `ModelTierSelector` ile MLKit+Gemma+Qwen üçünü gösteriyor — NS-2 fix'iyle birlikte canlı kısa-cümle çevirisi çalışmalı. **SIRADAKİ (cihaz, Mehmet):** NS-4 Qwen+Gemma yeniden indir (Ayarlar'dan, yer var) → crunch + Bas Konuş LLM geri çalışır; NS-6 fast/full hands-free smoke; sonra Bas Konuş Gemma/Qwen kök fix doğrula (artık görünür hata + gerçek model). Detay: Polish "🗣️ SMALLTALK". ↓ ÖNCEKİ: 2026-06-05 (3. oturum sonu) — **🗣️ SMALLTALK S1+S2+S3 + fast/full KOD TAMAM (analyze temiz, 140/140 test, APK Poco'da kurulu).** Voice Translator→SmallTalk (Konferans mimarisi, çift yönlü); Bas Konuş artık SmallTalk alt-modu. **S1:** menü SmallTalk kartı+folder, alt-mod picker, arşiv. **S2:** Bas Konuş eski split UI + warmup + Bitir→crunch. **S3 Hands-free fast/full:** **fast=Vosk×2 + güven skoru + histerezis**, **full=Whisper `auto` + MLKit Language ID** (Whisper çok dilli → gerçek dilde yazar → MLKit ayırır; Vosk tek-dilli olduğu için ayıramıyordu). Setup'ta fast/full seçimi. Her ikisi `DualTranscriber` → tek orkestratör. **CİHAZ KÖK NEDEN (Mehmet):** Qwen modeli SİLİNMİŞ → crunch + Bas Konuş LLM çevirisi çalışmıyor; "Çeviri motoru" seçicisi silinen modeli **'indirili' gösteriyor (yanlış pozitif bug)**. **SIRADAKİ:** NS-1 Ayarlar'a LLM yöneticisi (gör/indir/sil + Gemma token; `ModelRegistry`'de LLM YOK), NS-2 yanlış-indirili tespiti fix (dosya doğrula), NS-3 HF token persistence, NS-4 modelleri yeniden indir, NS-5 Bas Konuş MLKit+Gemma+Qwen seçimi, NS-6 fast/full cihaz smoke. **Kararlar:** ses kanal yönlendirme (kulaklık↔hoparlör) DEFERRED; full+ (diarizasyon+Vosk) + Konferans büyük-Vosk + gürültü NS/AEC = ileri keşif. Detay: Polish "🗣️ SMALLTALK". ↓ ÖNCEKİ: 2026-06-05 (2. oturum) ↓ ÖNCEKİ: 2026-06-05 (2. oturum) — **✅ KONFERANS POLISH BİTTİ — #1 VOSK NATIVE STREAMING + #2 BOZUK KARAKTER CİHAZDA GEÇTİ (Mehmet: "aynı çeviri artık tekrar etmiyor, bozuk karakterler artık ortadan kalktı").** Streaming hız "harika", canlı partial satırı kalıcı (Mehmet beğendi), EN Vosk şimdilik yeterli. Tekrar bug'ı (Vosk EventChannel aynı finali art arda yayıyordu) `_lastFinal` dedupe ile çözüldü. **SIRADAKİ:** önceki turun kalanı = 3-katman çeviri (Manuel Çeviri selector + tier seçim kalıcılığı). ↓ ÖNCEKİ (kod aşaması): **⚡ KONFERANS POLISH: #2 BOZUK KARAKTER + #1 VOSK NATIVE STREAMING — KOD TAMAM, cihaz testi bekliyor (Mehmet AFK).** Mehmet kararları (AskUserQuestion): hız çözümü = **direkt Vosk native streaming**, önce #2. **#2 ✅ KOD:** `lib/core/utils/llm_text.dart` `sanitizeLlmOutput` (byte-fallback `<0xNN>`→UTF-8 / özel token `<|im_end|>` vb. / metaspace ▁→boşluk / kontrol karakteri temizliği) → `LlmHost.generate`'e tek choke-point bağlandı (canlı çeviri + crunch özeti birlikte). 13/13 yeni test. **#1 ✅ KOD:** Manager'ı bypass eden streaming pipeline — `VoskStreamingController` (native `SpeechService` sarmalı, `onPartial`/`onResult`, VoskTestScreen kalıbından ayrıştırıldı) + `ConferenceStreamingSession` (final→filler→MLKit→DB→çeviri akışı; partial yalnız canlı gösterim, çeviri tetiklemez; crunch DB `sourceText`'ten okuduğu için **uyumlu**) + `ConferenceScreen` streaming'e geçti (model indirme kapısı + ısınma + running'de soluk **canlı partial** satırı). Dosya turu/backpressure yok → "Gemini hızı" hedefi. 8/8 orkestratör testi. **analyze temiz, 121/121 test.** **CİHAZ SMOKE BEKLİYOR:** (a) #2 crunch'ta bozuk karakter gitti mi; (b) #1 TR/EN canlı hız + cümle atlanmıyor + model indirme kapısı + bitir→crunch. Detay: Polish "🎤 KONFERANS MODU". ↓ ÖNCEKİ: 2026-06-05 — **🎤 KONFERANS MODU (eski Ders Modu) BAŞTAN TASARLANDI — K1–K4 KOD TAMAM, cihazda çalışıyor.** Mehmet Ders Modu'nu **Konferans Modu** olarak yeniden tasarlattı: açık/beyaz tema, sade giriş (yalnız 2 dil + seslendirme sorusu + ısınma ekranı/gri yuvarlak buton + arka planda model yükleme), canlı çeviri=MLKit (destek amaçlı, transkript gizli ama kayıtlı), oturum sonu **Qwen "crunch"** = tam çeviri + yapılandırılmış özet + başlık, "Crunch later" → ana menüde **klasör/arşiv** (crunch'lı=yeşil✓ "already crunched"+başlık-tarih, crunch'sız=tarih+"Crunch now"), her crunch'ta **ilerleme**. 4 sub-step hepsi cihaz testi geçti: **K1** rename+setup akışı+`Manager.prepare/start` ayrımı; **K2** çalışan ekran (yalnız çeviri, chunk'lı); **K3** DB v3 crunch sütunları+arşiv+detay; **K4** `CrunchService` (Qwen map-reduce)+ilerleme. **2 cihaz BUG'ı düzeltildi:** (a) uzun konuşmada "Bitir" takılması → `_stopping` bayrağı + backpressure; (b) crunch native çökme (MediaPipe JNI abort, bağlam taşması) → bağlam-güvenli map-reduce. **100/100 test, analyze temiz.** **KALAN = Konferans polish (2 iş):** #1 ⚡ TRANSKRİPT HIZI (en kritik — Gemini gibi hızlı değil; on-device cevap = Vosk native streaming), #2 🔣 Qwen çıktı bozuk karakter. Detay: Polish "🎤 KONFERANS MODU". ↓ ÖNCEKİ: 2026-06-04 (akşam) — **🌐 3-KATMAN ÇEVİRİ: NLLB elendi → MLKit/Gemma/Qwen + mod-başı model seçimi.** NLLB de-risk cihazda: KV-cache'e rağmen ~12sn (>20sn bile), kalite Qwen<, hatta MLKit< → **Mehmet NLLB'yi eledi.** <5sn gerçekçi değil (native generation-loop ister). **Son karar: Tier1 MLKit / Tier2 Gemma / Tier3 Qwen + Ders/Bas Konuş/Manuel'e model seçimi** (varsayılan Ders=Qwen, diğerleri MLKit). ✅ Yazıldı: `LlmHost` (tek-LLM-RAM) + `LlmTranslationEngine` (flutter_gemma sarmalı, TranslationEngine impl) + `TranslationTier` factory + `ModelTierSelector` widget; **Ders+Bas Konuş bağlandı** (LanguageSelectScreen). analyze temiz, 89/89 test, cihaza kuruluyor. KALAN: Manuel selector + seçim kalıcılığı + cihaz testi. NLLB kodu/paketleri (flutter_onnxruntime, dart_sentencepiece_tokenizer) deney olarak duruyor. Detay: Polish "🌐 3-KATMAN" + "🔬 TIER2". ↓ ÖNCEKİ: **🔬 TIER2 ARAŞTIRMASI BİTTİ → NLLB de-risk kararı.** Mehmet "önce Tier2 motoru araştır" dedi. Adaylar elendi: opus-mt ≈ MLKit (sıçrama yok, elendi), Bergamot devasa native emek (elendi), **NLLB-200-distilled-600M = MLKit'ten +44% FLORES + Qwen'den ~yarı hafif (~865MB ONNX vs 1.57GB)**. KRİTİK: NLLB saf çevirmen (mantık yürütmez) → Qwen'in reasoning'inin yerini TUTMAZ → NLLB = gerçek Tier2, Qwen Tier3 kalır. Hedef: **Tier1 MLKit / Tier2 NLLB / Tier3 Qwen**. **✅ MEHMET KARARI: NLLB de-risk ekranı kur** (MLKit vs NLLB vs Qwen, 3 kart). Fizibilite doğrulandı: `dart_sentencepiece_tokenizer` (HF tokenizer.json yükler) + flutter_onnxruntime + Xenova NLLB ONNX quantized + niedev/RTranslator referans. ⚠️ En ağır de-risk (hazır paket yok, Dart'ta tokenizer+seq2seq decode); önce dar spike sonra 3-kart. Detay: Polish "🔬 TIER2 ARAŞTIRMASI". ↓ ÖNCEKİ (2026-06-03): **✅ LLM ÇEVİRİ KIYAS BİTTİ: TIER-3 = QWEN2.5-1.5B (cihaz testi, Mehmet "qwen kesinlikle daha iyi, 3.2sn yavaş ama kabul edilebilir").** LLM test ekranı Qwen↔Gemma yan yana kıyasa dönüştürüldü (her model kendi "Çevir" butonu, sırayla/OOM-yok, üretim+yükleme süresi ölçer, HF token kutusu). Gemma'ya geçiş **iptal** (kalite Qwen'de + Apache-2.0 lisans avantajı). Gemma-4-E2B denendi → SD860'a fazla ağır → vazgeçildi. Detay: Polish "🤖 LLM ÇEVİRİ KIYAS". ⚠️ **AÇIK İŞ:** HF token (`hf_...`, memory `ref_hf_token`'da) ileride Gemma/gated model gerekirse hazır — Mehmet hatırlatılmasını istedi. **SIRADAKİ:** 3-katman çeviri entegrasyonu (Tier3=Qwen'i gerçek pipeline'a bağla + Tier2 orta-NMT araştır + `TranslationEngine` selector). ↓ ÖNCEKİ (2026-06-01): STT KATMANI TAMAM (Vosk ana + Whisper fallback) + Ders Modu chunk/ilk-kelime + LLM Qwen spike. Detay: Polish "🌐 ÇEVİRİ MOTORU ZAYIF". ↓ ÖNCEKİ: **VOSK TÜRKÇE ASR de-risk KODU HAZIR + MODEL YÖNETİMİ UX.** `vosk_flutter_2` (fork; orijinal permission_handler çakışması) eklendi, Android build fix'leri (minSdk 30 + namespace enjeksiyonu + alphacephei maven). `VoskTestScreen` (sadece TR, Whisper'a kıyas) + indirme onay/ilerleme UX'i + **Ayarlar ekranı** (tüm modeller gör/indir/sil, `ManagedModel`+`ModelRegistry`). Hibrit KESİNLEŞTİ (Mehmet birebir: "sadece türkçeye özel ayrı motor"): EN=Whisper, TR=Vosk. 89/89 test, analyze temiz, cihaza kuruldu. **SIRADAKİ: cihaz testi** — (1) Ayarlar'dan Vosk indir (ilerleme), (2) Vosk Test'te TR doğruluğunu Whisper'a kıyasla (de-risk asıl kararı), (3) sil/indir akışı. Detay: Polish "🔤 Vosk Türkçe ASR de-risk". ↓ ÖNCEKİ: **Transkript çözüldü (small+hız tuning), STREAMING çalışıyor, ama TÜRKÇE TANIMA → ASR PİVOTU (Vosk).** Bu oturum çok uzun, Step 7'nin büyük kısmı + kalite pivotu yapıldı. **Sıradaki oturum ilk işi: Vosk Türkçe ASR de-risk** (vosk_flutter eklenemedi — pub.dev ağ hatası; internet düzelince ekle → TR model → VoskTestScreen). Whisper EN için kalıyor. Detay: Polish "⚠️ Step 7 burst-3 KALİTE" madde 4. (Step 7 UI tarafı Mehmet'çe ertelendi, kaliteye odak.) ↓ ÖNCEKİ: **STEP 7 navigasyon + Bas Konuş + Ders Modu ekranları ✅.** burst-1 ✅ Navigasyon (HomeScreen mod kartları → LanguageSelectScreen → mod ekranı; Manuel→TranslationTestScreen). burst-2 ✅ **Bas Konuş gerçek ekranı** (`lib/features/push_to_talk/`): iki yarı + üst 180° + şeffaf/sadece-basılınca butonlar + DM-box chat (çeviri karşı tarafa) + gerçek Manager + immersive tam ekran + ortada minimal pill (geri+dil). 2. tur düzeltme: bottom overflow (chat klip) + üst boşluk (`primary:false`) — deploy edildi, Mehmet teyit edecek. **Step 9 notu: tasarım baştan yenilenecek (liquid glass tema).** Detay: Polish "Step 7 burst-1/2" + "🎨 Step 9 tasarım". Sıradaki burst: **Ders Modu ekranı** (placeholder duruyor). — ÖNCEKİ: **STEP 6 REFACTOR TAMAMEN BİTTİ (6r-e+f+g+h, hepsi cihaz smoke geçti).** 6r-e: PushToTalkAudioInput + Manager çift yönlü + portre kilidi. 6r-f: TitleGenerator (timestamp + hybrid seam). 6r-g: DB Test başlık. 6r-h: Manager tam pipeline entegrasyon (`SessionTestScreen`) — Mehmet "her şey harika". **88/88 test, analyze temiz.** Açık konular (Step 7/9): canlı transkript, TR Whisper doğruluğu; **karar: fast mod MLKit kalır, AI translate ileride full mod için (Faz 2).** **Sıradaki: Step 7 — gerçek mod UI'ları** (Ders Modu live subtitle + Bas Konuş şeffaf butonlar/DM-box chat). Gereksinimler Polish "6r-e" + "6r-h"de. Kod: `PushToTalkAudioInput` (`record` ham PCM16/16kHz/mono, VAD yok, ek `pressTalk(source)`/`releaseTalk()`, `PttRecorder` abstraction) + **Manager çift yönlü** (`event.source` → primary=source→target, secondary=target→source). **79/79 test ✅**, analyze clean. Detay ↓ Aktif İş. Önceki entry (6r-d pivot) ↓ Polish Notları + punch_board'da.

---

## Mevcut Durum (Checkpoint)

**Cihaz:** Poco X3 Pro (Android 13, ID: cd61ba57)
**Son cihaz testi:** ✅ Drift + SQLite — oturum/mesaj yazma + sıralama + cold-start kalıcılık doğrulandı (6/6 senaryo)
**Build ortamı:** NDK 29.0.13113456 pinli (`android/app/build.gradle.kts`), `record: ^6.0.0`, `whisper_ggml`, `google_mlkit_translation`, `flutter_lints`, `drift: ^2.21.0` + `sqlite3_flutter_libs: ^0.5.24` + `drift_dev` & `build_runner` (dev)
**`flutter analyze`:** clean (28/28 unit test geçiyor)

---

## Modlar (Faz 1 hedef özellikler)

**Faz 1'de 3 mod: Ders Modu, Bas Konuş, Manuel Çeviri.** Voice Translator (Yöntem B çift mic) **Faz 2'ye ertelendi** (2026-05-31 — bkz. aşağıdaki §2 başlığı + Risk tablosu). İsimler subject-to-change ama development boyunca aşağıdaki adlandırma korunur.

### 1. Ders Modu

**Senaryo:** Telefonu açıp ders modunu başlatır, kenara koyar, dersi dinler.

- **Live subtitles** — anlamadığın/bilmediğin kelimede veya hiç bilmediğin bir dilde ekrana bakarsın
- **Transkript kaydedilir** (ses kaydı DEĞİL, yalnızca metin)
- **Sonradan Gemini özeti** — internet varsa içerikten önemli noktalar çıkarılır
- **Opsiyonel kulaklık sesli çeviri** — izlenmesi gereken derslerde kulaklık takılır, çeviri sesli olarak kulaklığa verilir
- Tek yönlü, sürekli dinleme
- STT: Whisper small (doğruluk öncelik)

### 2. Voice Translator (kulaklık zorunlu) — ⏸️ FAZ 2'YE ERTELENDİ (2026-05-31)

> **Neden ertelendi:** Temel donanım varsayımı (kulaklık mic + telefon mic eş zamanlı bağımsız capture = Yöntem B) Poco X3 Pro'da cihaz testinde **kesin başarısız** oldu (5 AudioSource × 2 kulaklık tipi denendi, hiçbiri çift canlı route vermedi — Android/MIUI tek giriş route'u servis ediyor). Faz 2'de farklı yaklaşımla (turn-based + çıkış routing, ya da farklı cihaz/donanım, ya da SeamlessM4T) yeniden ele alınacak. Aşağıdaki tasarım orijinal niyeti belgeler, Faz 2 referansı olarak korunuyor.

**Senaryo:** Karşı kişiyle yüz yüze konuşma. Sadece app'i kullanan kişi kulaklık takar, karşı taraf kulaklıksız.

- **Çift mikrofon dinleme — Yöntem B** (Mehmet 2026-05-30'da seçti)
  - Mic A = kulaklık mikrofonu → mesaj **sağ** tarafa (kullanıcı)
  - Mic B = telefon mikrofonu → mesaj **sol** tarafa (karşı taraf)
  - Her iki mic de eş zamanlı dinlemede
  - **Risk:** Android'de concurrent audio capture cihaza/MIUI'ye bağımlı. Geliştirme Poco X3 Pro'da devam; sorun çıkarsa o zaman düşünülür (POC öncesi yapılmayacak)
- **Karşı tarafın mesajı otomatik kulaklıktan seslendirilir** (TR çevirisi)
- **Sağdaki play butonu** → telefon hoparlöründen karşı dile (ES) seslendirir → karşı taraf duyar
- **Transkript kaydedilir** (ses kaydı DEĞİL); "konuşmalarım"a düşer
- **Başlık otomasyonu:**
  - Internet varsa: Gemini'den içerik özetli başlık (ör. "yol tarifi")
  - Internet yoksa: `YYYY-MM-DD-HH-MM-SS tarihli voice translator konuşması`

**UI (kararlaştırıldı):**
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

### 3. Bas Konuş Modu

**Senaryo:** Kulaklığı olmayan kullanıcılar veya çift mic capture desteklemeyen cihazlar için Voice Translator'ın alternatifi.

- **Portrait** (tüm modlar gibi — landscape lock aktif). Ekran ortadan yatay bir çizgi ile ikiye bölünür, ortada ince ayraç çizgisi
- **Yukarı yarı** = karşı tarafın bölgesi, **içerik 180° döndürülmüş** (`RotatedBox(quarterTurns: 2)` — karşıdaki kişi telefonu kendine doğru tutarken normal okur). **Tüm yarı = karşının görünmez bas-konuş alanı.**
- **Aşağı yarı** = senin bölgen, normal yön. **Tüm yarı = senin görünmez bas-konuş alanın.**
- **Ortada görünür buton YOK** — hangi yarıya parmak değdiyse o taraf konuşur (doğal "kim konuşuyor" çözümü)
- **Transkript kaydedilir** (ses kaydı DEĞİL)
- UI olarak Voice Translator ile aynı (küçük gri transkript + büyük beyaz çeviri), sadece sol/sağ yerine aşağı/yukarı ayrımı + üst yarı 180° dönmüş + görünür buton yok

**Voice Translator ile farkı:** Tek mic yeterli, turn-based, kulaklık gerek yok. "Karşı taraf bizi türkçe konuşmamızın ispanyolca çevirisini görmeye ihtiyaç duymaz" — yukarı yarıda kendi diline çevrilmiş hâli görünür, alt yarıda kendi konuşman + onun diline çevirisi görünür.

---

## Faz 1 — Çekirdek Çeviri & Konuşma Asistanı

### Tamamlanan

- [x] **Proje iskeleti** — Flutter app, Material 3 dark tema, Hermes brand renkleri
- [x] **TranslationEngine interface** — Strategy Pattern abstract sınıf
- [x] **GoogleMLKitEngine** — `google_mlkit_translation` ile offline çeviri, model indirme yönetimi
- [x] **Test ekranı (Translation)** — Dil dropdown'ları, manuel metin girişi, çevir butonu (USB cihaz testi geçti)
- [x] **SttEngine interface** — Strategy Pattern abstract sınıf
- [x] **WhisperCppEngine** — `whisper_ggml`, tiny modeli APK asset, small Hugging Face indirme
- [x] **Mikrofon kayıt + Whisper transkript akışı** — `record` paketi, otomatik transkripsiyon sonrası ML Kit çevirisi (USB cihaz testi geçti)
- [x] **NDK 29 pin + record 6.x upgrade** — `whisper_ggml` NDK 29 gereksinimi karşılandı, record_linux 0.7→1.3 uyumsuzluğu çözüldü
- [x] **Konuşma Modu tasarımı** — VAD + auto-dil + chat akışı + filler temizleme, 6 açık soru kararlaştırıldı
- [x] **Step 1 — TtsEngine + Native flutter_tts** — `flutter_tts: ^4.2.5`, BCP-47 locale eşlemesi, auto-speak toggle, manuel Seslendir/Stop butonu (cihaz testi geçti; 6 senaryo ✅, robotic ses sistem TTS engine'iyle ilgili — Coqui Faz 2'ye işaretli)
- [x] **Step 2 — Dil paketi indirme UI** — TranslationEngine interface'e `isLanguageReady`/`downloadLanguage`/`deleteLanguage`/`estimatedDownloadSizeMb` eklendi, GoogleMLKitEngine bunları implement etti, dropdown indirilmiş (✓ beyaz) / indirilmemiş (⬇ gri + ~30MB) ayrımı, confirm dialog + indirme akışı, bottom overflow (Switch tap target) düzeltildi (cihaz testi geçti)
- [x] **Step 2 fix — Dropdown baseline assertion** — `selectedItemBuilder` ile inline seçili görüntü düz `Text`'e indirgendi; `_LanguageRow` açık menüde kaldı. InputDecorator+RenderIndexedStack baseline döngüsü kırıldı (log'da `ASSERTION_COUNT=0`)
- [x] **Step 3 — VadController (Silero v4)** — `vad: ^0.0.7+1`, `silero_vad_legacy.onnx` (1.8MB) APK asset, MODIFY_AUDIO_SETTINGS izni, VadController interface + sealed VadUtteranceEvent, SileroVadController, standalone VadTestScreen + AppBar entry. Cihaz testi: 5 cümleden 4'ü tespit (kısa/hızlı "iki kahve lütfen" kaçırıldı — bilinen min frame trade-off, Step 9 polish'inde tunable), uzaktaki gerçek konuşma misfire olarak doğru sınıflandı, sessizlikte sayaç artmadı, gürültü filtresi başarılı
- [x] **Step 4 — FillerCleaner (saf Dart)** — `FillerLevel.off/conservative/aggressive`, jenerik dolgu sesleri (mmm, aaa), TR conservative (ee, uhh), TR aggressive (yani, işte, hani, falan, şey), EN conservative (um, uh), EN aggressive (you know, i mean, kinda, sorta, sentence-initial like). 16/16 unit test geçti. Bilgi notu: Dart `caseSensitive: false` Türkçe `İ` ↔ `i` eşlemiyor; TR pattern'lerde açık character class `[İi]şte`. `\b` Unicode-aware olmadığı için `(?<![\p{L}])...(?![\p{L}])` kullanıldı.
- [x] **Step 5 — Drift schema + ConversationRepository** — `lib/core/database/app_database.dart` (sessions + messages tabloları, cascade delete, `PRAGMA foreign_keys=ON` `beforeOpen` migration), `lib/core/repositories/conversation_repository.dart` (`SessionMode.fast/full` enum + 7 metot: create/end Session, appendMessage, getSession, listMessages, listAllSessions (`startedAt` desc + id desc tiebreak), countMessages). 11 unit test (in-memory `NativeDatabase.memory()`). Cihaz doğrulaması için `lib/features/db_test/db_test_screen.dart` eklendi (AppBar `Icons.storage` butonundan). Bağımlılıklar: `drift: ^2.21.0`, `sqlite3_flutter_libs: ^0.5.24`, `path: ^1.9.0` + dev: `drift_dev`, `build_runner`. Cihaz testi 6/6 ✅ — kalıcılık dahil.

### Aktif İş

**Step 6 refactor — 6r-a + 6r-b + 6r-c TAMAMLANDI (2026-05-30):**

- **6r-a** ✅: Manager'dan `LanguageDetector` koparıldı, hardcode `sourceSpeaker`, `Whisper.language` explicit `sourceLanguage`. 58/58 test ✅, cihaz smoke ✅.
- **6r-b** ✅: `SessionMode` 3-değerli (`lecture/voiceTranslator/pushToTalk`), yeni `SessionQuality` enum (`fast/full`), Drift schema v1→v2 migration (`quality` + `title` column eklendi, eski `'fast'/'full'` değerleri yeni evrene remap edildi). Manager `quality` parametresi alır, `_speakWithMode` davranışı mode'tan quality'ye taşındı. DB Test ekranı yeni enumlara hizalandı. 65/65 test ✅, migration cihazda doğrulandı.
- **6r-c** ✅: `AudioInput` interface (`lib/core/audio/audio_input.dart`) + `AudioUtteranceEvent` + `AudioSource enum {primary, secondary}`. `SingleMicAudioInput` mevcut `VadController` sarmalı (ara state'leri yutar, bitmiş utterance'ları source etiketiyle yayar). Manager constructor `vad: VadController` → `audioInput: AudioInput` (test'lerde `FakeAudioInput`). 69/69 test ✅ (4 yeni: SingleMicAudioInput unit testleri), cihaz smoke ✅ (Mehmet: "her şey çalışıyor").

**6r-d — DualMicAudioInput native Kotlin plugin — ❌ CİHAZDA BAŞARISIZ (2026-05-31 akşam).** Plugin yazıldı (HermesDualMicPlugin.kt + dual_mic_channel.dart + dual_mic_test_screen.dart), analyze clean, 69/69 test ✅, cihaza kuruldu. Smoke testi 5 AudioSource kombinasyonu × kablolu + BT kulaklık denendi: **hiçbir konfigürasyonda kulaklık mic'i + dahili mic eş zamanlı bağımsız canlı değil** (cihaz tek giriş route'u servis ediyor). → **Mehmet pivot: Voice Translator Faz 2'ye ertelendi, Faz 1 = Ders Modu + Bas Konuş + Manuel.** Kod silinmedi (negatif bulgu kanıtı). Tam analiz: Polish Notları "6r-d-faz1".

**6r-e — Bas Konuş audio input + Manager çift yönlü — ✅ CİHAZ SMOKE GEÇTİ (2026-05-31 akşam, 2. oturum).** Mehmet: "2 test de başarılı" (iki yarı da yakalıyor, çift yönlü routing + record.startStream PCM çalışıyor). Portre kilidi eksikti → `main.dart`'a portraitUp eklendi. Türkçe Whisper doğruluğu zayıf (açık STT kalite sorunu, Step 9). Step 7 gerçek UI gereksinimleri (şeffaf butonlar, çeviri karşı tarafa, DM-box chat, mod→dil→ekran akışı) Polish Notları "6r-e"de birebir. Mehmet onayı Seçenek A×2:
- **`PushToTalkAudioInput`** (`lib/core/audio/push_to_talk_audio_input.dart`): `record` paketiyle ham PCM16/16kHz/mono stream (VAD yok, buton=utterance sınırı). Base `AudioInput`'a ek 2 metot: `pressTalk(AudioSource)` (buton bas → yakala) + `releaseTalk()` (bırak → PCM16→Float32, tek `AudioUtteranceEvent` yay, source=basılan yarı). `start/pause/stop` = arm/disarm. UI bu metotları doğrudan concrete tipte çağırır; Manager habersiz. Test için `PttRecorder` abstraction + `RecordPttRecorder` default impl.
- **Manager çift yönlü**: `_processUtterance(samples, source)` — `primary`=source→target/sourceSpeaker, `secondary`=target→source/targetSpeaker. Whisper lang + filler lang + translate yönü + participant yöne bağlı. Ders Modu/`SingleMicAudioInput` hep `primary` → davranış birebir korunur.
- **79/79 test ✅** (9 PushToTalk unit + 1 Manager secondary-routing), analyze clean.
- ✅ **Cihaz smoke GEÇTİ**: minimal iki-yarı PTT test ekranı (`lib/features/push_to_talk_test/`, üst yarı 180°) ile `record.startStream` PCM + press/release + iki source routing + Whisper transkript doğrulandı (Mehmet "2 test de başarılı"). Portre kilidi de cihazda teyit edildi.

**6r-f — TitleGenerator — ✅ TAMAM (2026-05-31 akşam, 2. oturum).** `lib/core/services/title_generator.dart`: `TitleGenerator` interface + `TimestampFallbackGenerator` (`titleFor`/`modeName` saf metotlar, format "YYYY-MM-DD-HH-MM-SS tarihli {ders|voice translator|bas konuş} konuşması") + `HybridTitleGenerator` (online seam: null→fallback, online geçerli→trim'li kullan, boş/throw→fallback). Repository `setTitle(sessionId, title)`. Manager: `TitleGenerator` enjekte (default `TimestampFallbackGenerator`), `end()`'de `_writeTitle` → mesaj+session çek → üret → `setTitle` (hata end() akışını bozmaz). **Gemini gerçek HTTP Step 9'a ertelendi** (offline-first Faz 1, roadmap Step 9 "başlık Gemini"). Test: 7 title_generator unit + 1 Manager end→title + 1 repository setTitle.

**6r-g — DB Test ekranı title — ✅ TAMAM + CİHAZ SMOKE GEÇTİ (2026-05-31 akşam, 2. oturum).** `db_test_screen.dart`: "Oturumu Kapat" Manager ile aynı akışı yapar (başlık üret + setTitle + endSession), kart başlığı gösterir (null→"(başlık yok)" italic, dolu→sarımsı). Cihaz smoke ✅ — Mehmet "test başarılı": oturum aç → mesaj → kapat → timestamp başlık üretilip listede göründü. **88/88 test toplam**, analyze clean.

Karar özetleri:

- **Yöntem B seçildi** (kulaklık + telefon mic, iki mic eş zamanlı dinleme). MIUI/Poco X3 Pro'da sorun çıkarsa o zaman düşünülür — POC öncesi yapılmayacak.
- **Geliştirme Poco X3 Pro'da devam.** iPhone 17 Pro Max Faz 1 demo cihazı, Faz 1 boyunca iOS testine girilmez (Mac yok, Codemagic iterasyonu yavaş).
- `SessionMode` revize edilecek: `fast/full` yerine 3 mod (örn `lecture/voiceTranslator/pushToTalk`).
- **ML Kit Language ID silinecek** — kim konuşuyor donanımdan belli, dil tespitine ihtiyaç yok.
- Mevcut `TranslationTestScreen` korunur — modlardan bağımsız "manuel çeviri" olarak ana ekranda yer alır.

### Sıradaki tur açılışında ne yapılır

**⭐ EN GÜNCEL (2026-06-13) — UI RESTYLE TUR 2 KALANI BİTTİ (a–f) + Görsel Çeviri Lens overhaul (analyze temiz, 196/196 test, arm64 debug APK build; CİHAZ SMOKE BEKLİYOR):**

Tur 2'nin yarım kalan kalemleri (a–f) bu turda tamamlandı, hepsi liquid-glass HG:
- **(a) PTT split** (`push_to_talk_screen.dart`) — HgScreen + warmup/running/ended/error fazları; split koruundu (üst yarı `RotatedBox(2)`, her yarı görünmez bas-konuş), cam balonlar (smalltalk tint), orta cam pill "SmallTalk · TR ⇄ EN" + hairline ayraç + Bitir; mic ipucu altta; tüm session/manager mantığı AYNEN.
- **(b) Manuel Çeviri** (`main.dart`) — HgScreen + NavHeader (dev menü cam ikonda) + LangBar (pill'e dokun → cam bottom-sheet dil picker, 6 dil + ready/indir dot) + ModelTierSelector + cam input kartı + Çevir gradient + mic cam butonu + sonuç cam kartı (Dinle) + autoSpeak toggle. Eski dropdown'lar + `_LanguageRow` SİLİNDİ.
- **(c) GÖRSEL ÇEVİRİ LENS OVERHAUL (feature)** — `OcrResult`'a `blocks` (her `OcrBlock`=metin+`Rect boundingBox`) + `imageSize` eklendi; `MlKitTextRecognizer` blok kutularını + `instantiateImageCodec` ile görüntü pikselini döner. Ekran: foto cam viewport'ta (boşken tarama deseni + köşe ayraçları), her blok **tıklanabilir kutu** (scale = viewportW/imageW), dokunulan blok çevrilir → çeviri kutunun üstüne bindirilir (Lens) + altta sonuç kartı (orijinal+çeviri+kopyala); auto kaynakta dil blok bazında tespit. `HgScreen(scroll:false)`+kendi `SingleChildScrollView`'i (LayoutBuilder IntrinsicHeight'la çakışmasın). OCR testleri yeni akışa güncellendi (4/4; MLKit kanal mock + büyük test penceresi + reduce-motion).
- **(d) ModelTierSelector** HG (cam segment + WarnGlass "Ayarları Aç"); opsiyonel `accent` (Manuel=manual, OCR=visual).
- **(e) low_ram_warning** → cam dialog (uyarı ikonu + İptal/Yine de kullan).
- **(f) Tema toggle KALICI** — `setHgThemeMode`/`loadHgThemeMode` (shared_preferences `hg_theme_mode`), main()'de açılışta yükleniyor, Home toggle setter'ı çağırıyor. (Ayarlar'a taşıma hâlâ yapılmadı — toggle Home'da.)

**CİHAZ SMOKE BEKLİYOR (Mehmet, Poco bağlanınca):** `adb -s cd61ba57 install -r -d build/app/outputs/flutter-apk/app-debug.apk` → (1) PTT split iki yarı + 180° + balonlar + Bitir; (2) Manuel: dil picker, çevir, dinle, tier "Ayarları Aç"; (3) **Görsel Çeviri Lens: foto çek → bloklar kutu olarak görünüyor mu → bloğa dokun → o blok çevrilip üstüne biniyor + sonuç kartı** (asıl yeni feature); (4) low_ram cam dialog; (5) tema toggle kapat-aç sonrası kalıcı mı (uygulamayı yeniden başlat). ⚠️ Dosya düzenlemede yalnız Edit/Write (PowerShell `-replace` Türkçe UTF-8 bozuyor). ⚠️ HgGlass gerçek BackdropFilter — OCR viewport + çok bloklu fotoda jank olursa `blur:false`.

**SONRAKİ (cihaz smoke sonrası):** tema toggle'ı Ayarlar'a taşı (şu an Home); kalan dev/test 🧪 ekranları hâlâ HermesColors/Material (kullanıcıya görünmez, düşük öncelik); `hermes_card.dart` artık ölü kod (silinebilir). Önceki turların bekleyen cihaz smoke'ları aşağıda.

**ÖNCEKİ (2026-06-12, 2. iş) — UI RESTYLE TUR 1: liquid-glass tasarım sistemi + Mercury Home (cihaz smoke YAPILDI, feedback Polish'te):**

Claude Design hand-off'u geldi (`MOBS-Hermes/Hermes-UI-claudeDesign-Hand-off.zip`, açılmış kopya `MOBS-Hermes/_handoff_ui/design_handoff_hermes_translator/` — README + prototype jsx + 17 ekran görüntüsü). **Mehmet kararları:** Home=Mercury (serif/editoryal), palet=Coral, dark=Hermes Noir ŞİMDİ (altyapı kuruldu), ilerleme=aşamalı (tur tur + cihaz testi). **Tur 1 yapıldı:** `hg_tokens.dart` (Coral+Noir paletleri, mod aksanları, geometri token'ları, `hgThemeMode` notifier) + `hg_typography.dart` (Manrope+Cormorant Garamond variable font, `assets/fonts/`, FontVariation ile ağırlık) + `hg_background.dart` (radyal mesh painter) + `hg_glass.dart` (HgGlass: BackdropFilter blur+saturate(190%), tint bloom, glare, hairline; HgPressable) + `hg_icons.dart` (hand-off stroke SVG path'leri, path_drawing ile; 10 ikon portlandı) + **home_screen.dart Mercury'ye yeniden yazıldı** (navigasyon birebir korundu) + `hermesNoirTheme` + main.dart themeMode (Home'da geçici güneş/ay toggle, varsayılan açık). analyze temiz, 196/196 test. **CİHAZ SMOKE (Mehmet):** Home görünüm (mesh + glass panel + serif), 4 mod + 2 klasör + Ayarlar navigasyonu, Noir toggle (eski ekranlar Noir'da kusurlu görünebilir — bilinen geçiş durumu), font Türkçe karakterler (İ/ğ/ş serif'te). **SONRAKI TURLAR:** Tur 2 = SmallTalk wizard + ConversationLive 5-faz restyle; Tur 3 = Konferans 5-faz; Tur 4 = Manuel/OCR/Ayarlar/Arşiv; sonra eski `HermesColors` ekranları tamamen göçünce themeMode kalıcılaştır + Ayarlar'a taşı. Hand-off README "Screens/Views" bölümü ekran ekran spec veriyor — kod yazarken oradan oku.

**ÖNCEKİ (2026-06-12, 1. iş) — Tüm-kod bug taraması + 11 Haziran artıkları kapatıldı (analyze temiz, 196/196 test):**

2026-06-11 oturumu punch board'a yazılmadan kesilmişti; artıkları bulunup kapatıldı: **(B) Gemini anahtar doğrulama** Ayarlar'a bağlandı (`validateKey`, yalnız 200'de kaydet); **(C) boş-oturum-silme** davranışının kırdığı 4 test güncellendi + 3 boş-oturum testi eklendi. Ek bug fix'ler: indirme hata yolunda açık `IOSink` (5 dosya — Whisper/NLLB/LLM/small100/opus_mt); crunch ilerleme dialogu geri tuşuyla düşünce sonraki `pop()`'un ekranı kapatması (`PopScope`); Conference/SmallTalk session `start()` çift-çağrı yarışı (`_starting` guard); Dual-Vosk + StreamingMic stop→start döngüsünde duplicate VAD aboneliği; `_vad.dispose()` await'leri; FillerCleaner TR cümle başı `i→İ/ı→I` (locale fix, +2 test); Ayarlar `_delete` mounted guard; validateKey'e 3 test. **AÇIK KALAN: (D) crunch etiketleri** — "Derinlemesine Çevir" → "Daha İyi Çevir" gibi spesifik etiket (Mehmet 2026-06-11 feedback, henüz yapılmadı). **Cihaz işleri hâlâ bekliyor (aşağıdaki 06-10 entry'si):** yeni APK build + Gemini smoke + entry-8 kalanları.

**ÖNCEKİ (2026-06-10) — (B) Gemini çevrimiçi crunch fallback KOD TAMAM; cihaz smoke + entry-8 bekleyenler:**

(B) düşük-RAM fallback artık YAPILDI (analyze temiz, 188/188 test, cihazsız). Kullanıcı Ayarlar'a kendi Gemini anahtarını girer → konferans/oturum detayında "Gemini ile Çevir & Özetle" (yerel model gerektirmez) + "Gemini ile Özetle" (yerel NLLB çevirisini Gemini özetle, hibrit) + her zaman "Transkripti Kopyala". **CİHAZ SMOKE BEKLİYOR (Mehmet):** Ayarlar→Gemini anahtarı → detay→çevrimiçi crunch → çeviri+özet+başlık (internet); geçersiz anahtar→net hata; kopyala. **HÂLÂ AÇIK CİHAZ İŞLERİ (entry 8'den, USB koptuğu için yapılamadı):** (1) daanzu (1.5GB) push `<ext>/vosk_en_derisk/` + APK kur + 3 smoke (SpeechService çökme fix / crunch 2-adım / Vosk EN daanzu-vs-small doğruluk); (2) NLLB + Gemma3 in-app indirme (GH Release'e yüklü; Gemma3 indirme test edildi ✅, NLLB in-app test bekliyor). **Sonra:** de-risk artıkları temizle (🧪 crunch_derisk + vosk_en_derisk ekranları + scratch/cihaz klasörleri). APK Poco'da kurulu (entry 8 build'i; Gemini değişikliğini içermez → yeni APK gerekir).

**ÖNCEKİ (2026-06-09-7) — Crunch=Gemma3-1B bağlandı; GH yükleme + cihaz test + (B) Gemini fallback bekliyor:**

Crunch de-risk bitti → **Gemma3-1B-IT q8** kazandı (Phi-4 OOM, Qwen bozuk/soru-soruyor, gemma-4 native hata). `LlmModelDef.crunch`=gemma3 (selfHosted GH), LLM indirme selfHosted→streamed+`fromFile`. **MEHMET'TE:** `Gemma3-1B-IT_multi-prefill-seq_q8_ekv1280.task` (1005MB, `_scratch/crunch_derisk/`) → mevcut `nllb-600m-int8-v1` release'ine ekle. Sonra cihazda: Ayarlar→Özet Modeli (Crunch)→Gemma3-1B indir → oturum crunch. **SONRA (B, YAPILMADI):** düşük-RAM cihaz fallback = transkripti **kopyala** + kullanıcının **kendi Gemini API key**'iyle online crunch arayüzü (Ayarlar). 🧪 crunch_derisk ekranı + `_scratch/crunch_derisk/` (4 model + gemma-4) de-risk sonrası temizlenebilir. APK Poco'da kurulu.

**ÖNCEKİ (2026-06-09-6) — FAZ B (in-app NLLB indirme) KOD TAMAM:**

`nllb_model_manager.dart` URL'leri GitHub Release'e (`Runomm/MOBS-Hermes`, tag `nllb-600m-int8-v1`) bağlandı; `download()` aktif (app-owned, FUSE sorunu yok). **MEHMET'TE (engelleyici):** Release oluştur + 4 dosya yükle (`_scratch/nllb600_int8/encoder|decoder|decoder_with_past _quantized.onnx` + `_scratch/sentencepiece.bpe.model`; tokenizer.json YOK; toplam ~1.34GB). Yüklenince: Ayarlar→Çeviri Modelleri (NMT)→NLLB-600M indir → in-app iniyor + çeviri çalışıyor mu. APK Poco'da kurulu. **Sonrası:** bekleyen cihaz testleri (crunch/Phi, hands-free full(+) R1, OCR detaylı) + Faz 4 UI detaylı gezme. Planlı yeni büyük iş yok.

**ÖNCEKİ (2026-06-09-5) — F3b + Faz 4 KOD TAMAM; F3b cihaz smoke ✅:**

F3b (Whisper streamed indirme → %/hız/ETA) + Faz 4 (UI beyazlaştırma — Konferans tasarım dili app geneline, `app_theme.dart` `HermesColors`/`hermesLightTheme` + `HermesCard`) yapıldı (analyze temiz, 169/169 test, APK build). **CİHAZ SMOKE BEKLİYOR (Mehmet, Poco USB bağlanınca):** (1) Ayarlar→Whisper small indir → %/hız/ETA görünüyor mu (ML Kit'te boyut+"indiriliyor…" beklenir); (2) tüm kullanıcı modları açık/temiz tasarımda mı + kontrast + Bas Konuş 180° + status bar ikon kontrastı. **APK kurulumu yapılamadı** (cihaz USB'de değildi) — bağlanınca `adb -s cd61ba57 install -r -d build/app/outputs/flutter-apk/app-debug.apk`. Bekleyen diğer cihaz testleri: F3 merkezi indirme smoke, hands-free full(+) (R1 — Whisper indirme), crunch (Phi), OCR detaylı. **Roadmap'in planlı büyük işleri bitti** — sonrası cihaz smoke + polish + (açık) Faz B in-app indirme host'u (GitHub Release).

**ÖNCEKİ liste (referans):**

NLLB her yüzeyde (fast=MLKit/full=NLLB; crunch NLLB→Phi). ML Kit readiness audit + WiFi fix yapıldı (analyze temiz, 150/150 test, APK Poco'da). Poco cihaz testi geri bildirimi Polish'te birebir. **YARIN İLK İŞLER (sırayla):**

1. **ML Kit/GMS (✅ TAMAM):** Timeout + net hata UX kodu yapıldı (`google_mlkit_engine.dart`, 90sn + `MlKitDownloadException`). **Cihazda ML Kit ARTIK ÇALIŞIYOR** (Mehmet 2026-06-09: "ML kit artık çalışıyor" — muhtemelen paralel GMS testi düzeltti). PARK değil. Timeout kodu yine de güvenlik ağı olarak duruyor.
2. **F1 — Cihaz RAM uyarısı (OOM) (✅ TAMAM — kod + cihaz, 2026-06-09):** Bas Konuş Akıllı Poco'da OOM çöktü (signal 9). **✅ YAPILDI:** `device_info_plus` RAM tespiti (`device_memory.dart` `DeviceMemory.totalRamMb`+`isLowRam`, eşik 11GB) + `low_ram_warning.dart` `confirmHeavyTierOnLowRam` dialogu → düşük-RAM'de NLLB seçilince "uyar+Yine de kullan/İptal"; 3 canlı modda (Bas Konuş/Konferans/SmallTalk full). 159/159 test. **CİHAZ SMOKE ✅ GEÇTİ** (Mehmet: "her şey belirttiğin gibi çalışıyor" — 3 modda uyarı + fast'te uyarı yok).
3. **F2 — Hands-free 3-katman (✅ KOD 2026-06-09, cihaz smoke bekliyor):** fast=Vosk+MLKit / full=Whisper+MLKit / full+=Whisper+NLLB. **✅ YAPILDI:** `SessionQuality.fullPlus` (DB string, migration yok); `smalltalk_screen` top-level `handsFreeUsesWhisper`/`handsFreeUsesNllb` + tier-tabanlı `_checkModels`/`_download`/`_warmUp` (full MLKit indirir, full+ NLLB pre-install); setup 3 kart; F1 RAM uyarısı `full`→`fullPlus`; `SmallTalkStreamingSession.quality` opsiyonel. 165/165 test. **CİHAZ SMOKE bekliyor:** 3 seçenek + full/full+ davranışı (full+ Whisper ~466MB → R1).
4. **F3 — Merkezi indirme (✅ KOD 2026-06-09, cihaz smoke bekliyor):** Tüm indirmeler yalnız Ayarlar'dan; mod girişinde model yoksa `ModelsRequiredGate` ("Ayarları Aç" + eksik adlar → dönünce yeniden kontrol). İndirme kapıları kaldırıldı (`model_tier_selector`/`conference_screen`/`smalltalk_screen`/`main.dart` Manuel). Ayarlar'da hız/boyut/%/ETA (`DownloadStats`+`ManagedModel.sizeMb`). 169/169 test. 🧪 ekranları hariç.
5. **F3b — Whisper indirme ilerlemesi (cihaz testinden çıktı, küçük):** Mehmet "hız/%/ETA görünmüyor" dedi → ML Kit (GMS) + Whisper (`whisper_ggml` consolidate) progress vermiyor. Whisper'ı kendi streamed `http` indirmemizle (`_WhisperModel.download` → byte sayacı + onProgress, `model.modelUri`→`getPath`) indir → stat çıksın. ML Kit imkânsız (boyut kalır). Vosk/NLLB/LLM zaten çalışıyor. **YAPILMADI.**
6. **Faz 4 — UI:** Konferans tasarım dilini app geneline (salt renk değil, genel dizayn). `ConferenceColors/Theme`→`lib/core/theme/app_theme.dart` global + paylaşılan widget'lar + kullanıcı ekranları (dev/test hariç). **YAPILMADI — son büyük iş.**
- **Bekleyen cihaz testleri:** crunch (Phi kurulu olmalı), Hands-free full (R1 — internet olunca), OCR detaylı.
- **Faz B (açık):** int8 (`Hermes/_scratch/nllb600_int8/*` + `_scratch/sentencepiece.bpe.model`) GitHub Release'e → `nllb_model_manager.dart` URL'leri → `download()` aktif (şu an adb-push).
- Plan: `~/.claude/plans/indexed-zooming-wilkinson.md`.

**ÖNCEKİ (2026-06-07) — cihazsız iş bitti, CİHAZ TESTLERİ Poco gelince:**
- **Görsel Çeviri (OCR) Faz 1 — CİHAZ SMOKE (Mehmet, Poco gelince):** Ana menü → "Görsel Çeviri" → kaynak/hedef dil (veya "Otomatik algıla") → "Fotoğraf çek" veya "Galeri" → metin tanınıp çevrildi mi (orijinal+çeviri kart). Latin alfabesi (tr/en/es/de/fr). İlk kamera/galeri kullanımında izin dialogu.
- **Görsel Çeviri Faz 2 (kod, cihazla):** canlı kamera overlay (`camera` paketi + periyodik frame → `TextRecognizerEngine.recognize` → çeviri overlay). Arayüz değişmez.
- **NLLB kalite kararı:** `_scratch/nllb_quality_results.md` Mehmet'le gözden geçir → Opus-MT de-risk (cihaz, hâlâ bekliyor) ile birlikte "hangi NMT" kararı. NLLB-600M seçilirse cümle-düşürme riski not edildi.
- **Opus-MT tr→en de-risk (CİHAZ, hâlâ bekliyor):** 🧪 "Opus-MT de-risk" → kalite gör → iyiyse en-tr export → çift yönlü → ana akışa wrap.

**ÖNCEKİ (2026-06-06) — SmallTalk NS iş listesi:**
- **NS-1:** ✅ KOD TAMAM — Ayarlar'a `_LlmManagedModel` (Qwen+Gemma gör/indir/sil + Gemma HF token dialog'u).
- **NS-2:** ✅ KOD TAMAM — `LlmTranslationEngine._installedId` diskteki dosyayı doğrular (≥1MB) + stale metadata temizler → yanlış-indirili bitti.
- **NS-3:** ✅ KOD TAMAM — `HfTokenStore` (shared_preferences); seçici + Ayarlar token'ı otomatik doldurur/kaydeder.
- **NS-4:** ⏳ CİHAZ (Mehmet) — Qwen + Gemma'yı yeniden indir (Ayarlar'dan, yer var) → crunch + Bas Konuş geri çalışır.
- **NS-5:** ✅ Zaten karşılanıyor — Bas Konuş `ModelTierSelector` ile MLKit+Gemma+Qwen üçünü gösteriyor (canlı kısa-cümle çevirisi).
- **NS-6:** ⏳ CİHAZ (Mehmet) — fast/full hands-free smoke + Bas Konuş Gemma/Qwen kök fix doğrula.
- **İleri keşif:** Konferans büyük-Vosk, full+ diarizasyon, gürültü için Android NoiseSuppressor/AEC.

Detay: punch_board en üst entry + Polish "🗣️ SMALLTALK". (Aşağısı eski 6r-d planı — ARŞİV.)

---

**6r-d-faz1 cihazda KESİN BAŞARISIZ (2026-05-31 akşam) → Voice Translator Faz 2'ye ertelendi.** Faz 1 artık üç modla bitecek: **Ders Modu + Bas Konuş + Manuel.**

**Bir sonraki tur (dual-mic'siz, yeniden tanımlı sub-step'ler):**
- 6r-d (DualMicAudioInput) **ATLANDI** — kod deney/negatif-bulgu olarak duruyor, ana akışa bağlanmadı.
- **6r-e:** ✅ TAMAM (`PushToTalkAudioInput` + Manager çift yönlü, 79/79 test, cihaz smoke "2 test de başarılı"). Portre kilidi eklendi. Açık: TR Whisper doğruluğu (Step 9) + Step 7 gerçek UI (Polish "6r-e").
- **6r-f:** ✅ TAMAM — `TitleGenerator` interface + `TimestampFallbackGenerator` ("YYYY-MM-DD-HH-MM-SS tarihli {mod} konuşması") + `HybridTitleGenerator` (online seam null→fallback; Gemini Step 9'da plug). Manager `end()`'de başlık üretip `sessions.title`'a yazar. Repository `setTitle`. 88/88 test.
- **6r-g:** ✅ TAMAM — DB Test ekranı: "Oturumu Kapat" başlık üretip yazar, kart başlığı gösterir. Cihaz smoke ✅ (Mehmet: "test başarılı") — oturum aç/mesaj/kapat → timestamp başlık üretilip listede göründü.
- **6r-h:** ✅ TAMAM — `SessionTestScreen` (`lib/features/session_test/`) ile Manager tam pipeline gerçek motorlarla cihazda doğrulandı (Mehmet "her şey harika"). **→ Step 6 refactor TAMAMEN BİTTİ.** Geri bildirim: (1) canlı transkript istenir (Step 7/9), (2) fast mod MLKit kalır, AI translate ileride full mod için (Faz 2). Polish "6r-h".
- **Sıradaki: Step 7 — gerçek mod UI'ları** (Ders Modu live subtitle + Bas Konuş şeffaf butonlar/DM-box 180° chat; Voice Translator hariç). Polish "6r-e" + "6r-h" gereksinimleri Step 7'ye girdi.

---

**⬇️ ARŞİV — aşağısı 6r-d için yazılmış orijinal plan. Cihaz testi başarısız oldu, plan UYGULANMAYACAK; teknik detaylar (özellikle vad `audioStream` keşfi) Faz 2 referansı için duruyor.**

> **⚠️ 2026-05-31 keşif turu netleştirmeleri (kod YAZILMADI, bir sonraki tur sıfırdan yazar):**
>
> **(A) Uygulama 2 faza bölündü [Mehmet kararı]** — varsayım üstüne VAD kodu yığmamak için:
> - **6r-d-faz1 (transport + RMS):** Kotlin plugin (iki `AudioRecord` → 2 EventChannel ham PCM) + test ekranı (iki RMS bar, VAD YOK, ham PCM'den RMS hesapla). **Cihazda concurrent capture'ı bu fazda doğrula.** Geçerse faz2'ye geç, geçmezse pivot — VAD kodu boşa gitmez.
> - **6r-d-faz2 (VAD'li tam `DualMicAudioInput`):** faz1 ✅ sonrası. Aşağıdaki keşif (B) sayesinde her stream'e ayrı VAD bağlanır.
>
> **(B) KRİTİK teknik keşif — `vad: ^0.0.7+1` ham PCM stream kabul ediyor:** `VadHandler.startListening(...)` artık `audioStream: Stream<Uint8List>?` parametresi alıyor (paket kaynağı: `vad_handler.dart:147,163,270-283`). Stream verilince dahili `AudioRecorder` BYPASS edilir; beklenen format **PCM16 / 16kHz / mono** — bizim native plugin'in tam çıktısı. Yani DualMicAudioInput'ta primary+secondary için **iki ayrı `VadHandler`**, her birine kendi EventChannel stream'i `audioStream` olarak verilir. `onSpeechEnd` → `List<double>` Float32 samples → `AudioUtteranceEvent`. **NOT:** mevcut `SileroVadController` bu `audioStream` parametresini KULLANMIYOR (kendi mic'ini açıyor); 6r-d-faz2'de ya `SileroVadController`'a opsiyonel `audioStream` ekle ya da `DualMicAudioInput` doğrudan `VadHandler` kullansın (tasarım kararı faz2'de).
>
> **(C) Kulaklık tercih sırası [Mehmet kararı]:** USB/kablolu öncelik, Bluetooth SCO fallback. Kotlin tarafı `AudioDeviceInfo` enumeration ile USB_HEADSET → WIRED_HEADSET → BLUETOOTH_SCO sırası dener. SCO seçilirse `startBluetoothSco()` gerekir (async, MIUI'de riskli — kablolu ana smoke yolu).
>
> **(D) Bağlama noktaları (referans):** test ekranı AppBar `actions`'a `main.dart:267` civarına `Icons.headphones` IconButton (mevcut VAD/DB pattern'i aynen). `MainActivity.kt` şu an boş gövde (`class MainActivity : FlutterActivity()`), `configureFlutterEngine` override edilip plugin register edilecek. AndroidManifest'te `RECORD_AUDIO` + `MODIFY_AUDIO_SETTINGS` var, Bluetooth için `BLUETOOTH_CONNECT` eklenebilir.

**Adımlar (faz1 → faz2 sırasıyla; aşağıdaki orijinal 7-adım hâlâ geçerli, 3. adım=faz2):**

1. **Android plugin iskeleti** — `hermes/android/app/src/main/kotlin/com/mobstudios/hermes/HermesDualMicPlugin.kt`:
   - `MethodChannel("hermes/dual_mic")` — control (`start`/`stop`/`isDualCaptureSupported`)
   - İki `EventChannel`: `hermes/dual_mic/primary` ve `hermes/dual_mic/secondary` — PCM stream'ler
   - `MainActivity` (veya `HermesApplication`) içinde plugin register

2. **Dual mic capture mantığı (Kotlin):**
   - Cihaz kontrol: `AudioManager.isHeadsetOn()` veya `AudioDeviceInfo` enumeration ile kulaklık var mı doğrula
   - İki `AudioRecord` instance, ikisi de `MediaRecorder.AudioSource.MIC`, sample rate 16000, mono, 16-bit PCM:
     - Mic A: `setPreferredDevice(headsetDevice)` (Bluetooth veya kablolu kulaklık mic)
     - Mic B: `setPreferredDevice(builtinDevice)` (telefon dahili mic)
   - İki ayrı thread'de okuma, PCM samples'ı `EventChannel.EventSink`'e ilet
   - Hata yakalama: `AudioRecord.STATE_UNINITIALIZED` veya `read()` < 0 → error event

3. **Dart tarafı** — `lib/core/audio/dual_mic_audio_input.dart`:
   - `DualMicAudioInput implements AudioInput`
   - İki `EventChannel` stream'ini dinler
   - Her PCM chunk'a kendi VAD instance'ı uygula (Silero, primary için biri, secondary için biri)
   - VAD utterance'larını `AudioUtteranceEvent(source: primary | secondary)` olarak yayınla
   - `start`: MethodChannel'a `start` mesajı + iki VAD'i başlat
   - `stop`/`dispose`: simetrik

4. **AndroidManifest izinleri** — `RECORD_AUDIO` zaten var. Bluetooth kulaklık için `BLUETOOTH_CONNECT` (Android 12+) eklenmesi gerekebilir; dual capture izninin OS varsayılanı yeterli mi cihazda test edilir.

5. **Permissions UX (opsiyonel basit)** — start çağrıldığında izin verilmediyse exception → Dart tarafında yakala, kullanıcıya "RECORD_AUDIO izni gerekli" uyarısı

6. **Cihaz testi smoke senaryosu (KRİTİK):**
   - Geçici test ekranı (`lib/features/dual_mic_test/dual_mic_test_screen.dart`) ekle — AppBar'a `Icons.headphones` ile bağla
   - Kulaklık tak (Bluetooth veya kablolu)
   - Test ekranı: "Başlat" butonu → iki ayrı RMS bar (Mic A / Mic B) görünür
   - Kulaklığa "test 1" söyle → sadece Mic A bar'ı yükselmeli
   - Telefon mic'ine "test 2" söyle → sadece Mic B bar'ı yükselmeli
   - Aynı anda kulaklığa + telefon mic'ine konuş → ikisi de yükselmeli (concurrent capture testi)
   - Cihazda 30 sn dinle, hata logu yok ise ✅; aksi halde Mehmet pivot kararı verir

7. `flutter analyze` + `flutter test` + cihaz testi → Polish Notları'na geri bildirim

**Eğer 6r-d ✅ geçerse:** 6r-e Manager 3-mod davranışı (Voice Translator: AudioUtteranceEvent.source ile sağ/sol routing, Bas Konuş: PushToTalkAudioInput entegrasyonu, Ders Modu mevcut), 6r-f TitleGenerator (Gemini + timestamp), 6r-g DB Test ekranını `title` field için uyarla, 6r-h entegrasyon cihaz testi.

**Eğer 6r-d ❌ başarısız (concurrent capture cihazda çalışmıyorsa):** Mehmet pivot kararı verir. Olası yollar: (a) Voice Translator Faz 2'ye ertelenir, Faz 1 Ders Modu + Bas Konuş yeterli; (b) Voice Translator Yöntem A'ya (tek mic + dil tabanlı kimlik) dönülür — kararı Mehmet verir.

### Sıradaki Adımlar (Faz 1 kalan)

- [x] **Step 6 — ConversationSessionManager + 3 mod altyapısı** — ✅ TAMAM (6r-a…6r-h). AudioInput strategy (SingleMic + PushToTalk; DualMic deney/Faz 2) + Manager çift yönlü 3-mod + TitleGenerator. DualMicAudioInput cihazda başarısız → Voice Translator Faz 2. 88/88 test, tüm sub-step'ler cihazda doğrulandı.
- [ ] **Step 7 — Mod UI'ları** — Voice Translator (sol/sağ chat + play butonu) + Bas Konuş (üst/alt ahize + tam orta bas-konuş butonu, üst yazılar ters) + Ders Modu (live subtitle)
- [ ] **Step 8 — Ana ekran navigation + mod seçimi** — 3 mod kart + Manuel Çeviri (mevcut TranslationTestScreen) erişimi
- [ ] **Step 9 — Polish** (TTS-mikrofon feedback guard, wakelock_plus, kalibrasyon, başlık otomasyonu Gemini entegrasyonu)
- [ ] **Release öncesi — `Hermes/RELEASE_CHECKLIST.md`** (zorunlu): 🔒 HF token app içinde KALMASIN (dev/test ekranları + token alanı production'dan çıkarılır; `git grep hf_` boş), gated model gerekirse self-host, build boyutu, son smoke. Guardrail aktif: root `.gitignore` sır kalıpları + `.githooks/pre-commit` token kalıbını commit'te engeller (`git config core.hooksPath .githooks`).

---

## Faz 2 — Genişletmeler

- [ ] **Voice Translator (Yöntem B ertelendi)** — Faz 1 cihaz testinde simültane çift-mic uygulanamadı (bkz. Risk tablosu + Polish "6r-d-faz1"). Faz 2'de turn-based capture + çıkış routing, farklı donanım, veya SeamlessM4T ile yeniden ele alınır. Mevcut `HermesDualMicPlugin.kt` + `DualMicChannel` deney harness'ı başlangıç noktası.
- [ ] Android **foreground service** (cebe atıp konuşmaya devam)
- [ ] iOS **background audio mode** (App Store risk değerlendirmesi sonrası)
- [ ] **Gemini Flash online cleanup** (opsiyonel "Online dil cilalama" toggle'ı)
- [ ] **Belge Modu** (kamera OCR + görüntüden çeviri)
- [ ] **Coqui TTS** (Native OS yerine, daha doğal ses)
- [ ] **Offline harita tile cache**
- [ ] **Anki / PDF export** (oturum geçmişi)

## Faz 3 — Gelişmiş

- [ ] **SeamlessM4T** (ses→ses direkt, STT+Translate+TTS tek model)
- [ ] **GeoEngine entegrasyonu** (Belge Modu üzerinden)
- [ ] **Konuşmacı diarization** (3+ kişi)
- [ ] **Real-time partial transcript** (canlı altyazı)

---

## Risk & Borç Takibi

| Konu | Durum | Not |
|---|---|---|
| **Dual mic concurrent capture (Voice Translator)** | ❌ **KAPANDI — cihazda uygulanamaz** | 2026-05-31 cihaz testi: native plugin + 5 AudioSource × 2 kulaklık tipi → kulaklık mic'i + dahili mic eş zamanlı bağımsız capture **hiçbir konfigürasyonda çalışmadı**. Poco X3 Pro (MIUI/Android 13) tek giriş route'u servis ediyor. **Sonuç: Voice Translator (Yöntem B) Faz 2'ye ertelendi**, Faz 1 dual-mic'siz 3 modla bitiyor. Faz 2'de turn-based + çıkış routing ya da farklı yaklaşım. |
| NDK r29-beta1 | Aktif risk | `whisper_ggml` strict istemiş; production release öncesi stable r29 çıkarsa upgrade |
| `flutter_lints: ^6.0.0` modern olmasına rağmen 13 paket outdated | İzlemde | `permission_handler`, `record`, `google_fonts` major bump'lar var; Faz 2'de toplu upgrade |
| TTS feedback loop (mikrofon kendi sesini duyar) | **Yöntem B çözer** (Voice Translator için) | TTS kulaklığa, karşı tarafın sesi telefon mic'ine — donanım izolasyonu. Bas Konuş Modu'nda buton state'i guard'lar. Ders Modu'nda kulaklık opsiyonel = kulaklık varsa benzer izolasyon. |
| Whisper small modeli (Faz 1'de seçilemiyor) | Beklemede | Cihazda küçük model varsayılan; Settings'te toggle Step 7+ |
| iOS Faz 1'de test edilmiyor | Bilinen | Mac yok, Codemagic iterasyonu yavaş. iPhone 17 Pro Max Faz 1 sonu/demo. Voice Translator'ın iOS dual mic davranışı Faz 2'de doğrulanır. |

---

## Polish Notları (Step 9 için biriken cihaz testi gözlemleri)

> Bu bölüm her cihaz testinin AYNEN raw geri bildirimini + analizini saklar.
> Step 9'a gelindiğinde tek tek elden geçirilir ve fix/feature olarak ele alınır.
> **İLKE: Kullanıcı testte ne söylediyse buraya birebir yazılır, parafraze edilmez.**

### 🆕 UI TUR 2 — 3. cihaz testi (2026-06-13 #3, Mehmet birebir)

> "ana menüdeki hermes yazsınının sağı ve logo'nun solundaki alanda right overflowed by 25 pixels hatası veriyor. bu overflow hatalarından kurtulmak için ne yapılması gerekiyorsa yap her şeyi sadece poco'ya özgü tutma başka cihazların en boy gövde oranlarına göre otomatik fit gerçekleştiren bir sistem üret
>
> 1.Splash: uygulama açılırken hala uzun bir siyah ekran var.
> 2.Eyebrow: animasyon yok ve online'da sadece 3 dil var, offline'da daha fazla dil var ve uygulama açıkken int kapanırsa hala online ya da ofline takılı kalıyor. dillere arapça, çince, japonca, rusça da ekle her iki durum içinde
> 3. Overscroll: mor yanıp sönme gitti. [✅ çözüldü]
> 4.Manuel çeviri: sorun yok gayet iyi. [✅]
> 5.görsel çeviri: butonları ve göstergeleri daha da şeffaf yap daha kenaralara ve aşağı/yukarı kaydır ve küçült.
> 6.boş transkript: evet doğru çalışıyor. [✅]
> 7.çökme: şuan bir sorun yok olursa haber veririm. [✅ şimdilik]"

**Analiz / yapılacaklar — ✅ TÜMÜ 2026-06-13 #4'te kodlandı (analyze temiz, 196 test, APK build):**
- **(A) Overflow ✅:** Home header eyebrow + marka satırı `FittedBox(scaleDown, centerLeft)` ile sarıldı → dar cihazlarda otomatik küçülür (cihaz-agnostik, overflow yok).
- **(1) Splash siyah — ⚠️ HÂLÂ ÇÖZÜLMEDİ (cihazda devam ediyor, AÇIK İŞ):** Denenenler: (i) `drawable-v21` + NormalTheme `?android:colorBackground` (karanlıkta siyah) → `colors.xml`(+night) `launch_bg`. (ii) Android 12+ SplashScreen API → `values-v31`+`values-night-v31` `windowSplashScreenBackground`. (iii) `main()`'deki `await FlutterGemma.initialize()` runApp'ten önceydi → `SplashScreen._initEngines`'e arka plana alındı; runApp neredeyse anında. (iv) night `launch_bg` #100E14→#FCFBFF (karanlık modda siyah algısı için). **SONUÇ (Mehmet son test):** hâlâ "başlangıçta ~3sn siyah ekran + 1sn logolu ekran". 1s logo = sistem splash çalışıyor; ~3s siyah DEVAM. Hipotez: debug motor cold-start (release'de düzelebilir) VEYA hâlâ bir native pencere boşluğu. **SIRADAKİ TUR DENE:** (a) `flutter_native_splash` paketi (Android 12 keep-on-screen dahil battle-tested) — manuel stiller yerine; (b) release/profile APK ile gerçek süreyi ölç (debug mı suçlu doğrula); (c) MainActivity'de `installSplashScreen().setKeepOnScreenCondition` ile sistem splash'i ilk Flutter frame'e kadar tut.
- **(2) Eyebrow ✅:** `connectivity_plus` eklendi (event-driven → internet kopunca ANINDA güncellenir, takılma yok); 10 dil (tr/en/es/fr/de/it/ar/zh/ja/ru) online+offline eşit; fade+slide animasyon belirginleştirildi (650ms), döngü 2.2s.
- **(5) Görsel Çeviri overlay ✅:** foto üstü kontroller `glass: 42` (çok daha şeffaf), `compact` (küçük), kenar padding 12 + üst 6/alt 8 (kenarlara/uçlara yakın).

### 🆕 UI TUR 2 — 2. cihaz testi + büyük feedback paketi (2026-06-13 #2, Mehmet birebir)

> "her AI işlevinde veya her ağır işin başında ram boşaltılmalı her bir ağır işin altına girmeden önce temiz bir başlangıç yapılmalı yoksa app çöküyor ayrıca bir hata oluşsa bile app crash olmamalı hata mesajı verilmeli "cihazınız şuanda tam kapasite çalışıyor lütfen daha sonra deneyiniz veya arka planda çalışan diğer işlemleri durdurunuz(ram'i boşaltmak için kullanıcıya bir buton sunabiliriz)gibi?
>
> ör: ayarlar ekranında en tepede "ayarlar" yazan banner scroll gerçekleştiğinde çok çirkin bir şekilde ekranın üst kısmını tamamen kapladığı çok göze çarpıyor. genel olarak herhangi bir ekranda banner'ın çerçevesi şeffaf olmalı. ayrıca yine ayarlarda en scrollda en alta veya en üste çarpınca mor şekilde ekran yanıp sönüyor bu çok çirkin bunu kaldır. ve mor olarak parlayan kısım pasif moddayken bile göze çarpıyor arka plandan ayrışıyor.
>
> sol üst köşede yazan ÇEVİRİMDIŞI yazısı desteklenen dillerde sürekli olarak fade out and fade in animasyonu ile yer değiştirsin her dilde yazsın yani, ayrıca çevirim içi olduğunda değişebilsin ve yine aynı şekilde diğer dillerle birlikte animasyonlu olarak yazsın. çevirimiçi olduğunda yeşil, çevirimdışı olduğunda coral renginde şık şekilde yansın yani çevirimdığı olmanın kötü bir şey olmadığı hatta iyi bir şey olduğu hissiyatı verilsin.
>
> manuel çeviri ekranında alt kısım kullanılmıyor bütün ekran yukarı kaymış.ayrıca çevirinin yazıldığı alanda 2 kutucuk iç içe geçmiş gibi görünüyor.
>
> konferasn ve smalltak modlarında içi boş olan transkriptler tutulmaya devam ediyor. boş transkriptler silinsin.
>
> görsel çeviri ekranında görüntü ekranda olabildiğince yer kaplasın derken zaten hali hazırda küçük olan preview ekranının içinde büyüt demedim. bütün görsel çeviri ekranını kaplasın ve çeviri motoru seçimi, kaynak ve heder seçimi, çeviri sonucu göserilen ekran, galeri, fotoğraf çek butonlarının hepsi şefaf olsun ve fotoğrafın üzerinde yer alsınlar. fotoğraf çekimi yapılmadan önceki durumda ise preview ekranının gereksiz yere çirkin bir şekilde yer kaplamasına gerek yok, fotoğraf çekilene kadar veya galeriden fotoğraf seçilene kadar boş bir preview'in ekranda gereksiz yer kaplamasına ihtiyaç yok.
>
> uygulama açılırken düz siyah ekran yerine yükleniyor gibi şık animasyonlu bir ekran açılsın ve her açılmada nllb ram'e yüklensin çünkü en çok kullanılan ürün o olacak ve her seferinde kullanıcının nllb'nin yüklenmesini beklemsini istemiyorum nllb arka planda daima çalışacak. taaa ki local ai ile özet oluşturulmaya çalışana kadar, local'de(offline) özet çıkarmak istendiğinde nllb ramden boşalıtılıp özet, llm'i ram'e yüklenecek ardından işini yaptıktan sonra ram'den boşaltılıp tekrar nllb i ram'e yüklenecek ve bu işlev kullanıcının ekranında özet olarak görünecek arka planda o sırada ihtiyaç duyulmayacak olan ama genel olarak ihtiyaç duyulan nllb'nin yüklendiğini bilmesine gerek yok."

**Analiz / yapılacaklar (öncelik sırası) — ✅ 7 maddenin TAMAMI 2026-06-13 #3'te kodlandı, analyze temiz/196 test/APK build, CİHAZ SMOKE BEKLİYOR:**
- **(1) RAM yönetimi + crash önleme (KRİTİK):** Her ağır iş (STT/NMT/LLM/OCR warmup) ÖNCESİ RAM temizliği (önceki motoru dispose/unload). Hata olsa bile app CRASH OLMAMALI → yakalanıp dostça mesaj: "Cihazınız şu anda tam kapasite çalışıyor, lütfen daha sonra deneyin veya arka plandaki işlemleri durdurun" + opsiyonel "RAM'i boşalt" butonu. → global crash guard + her warmup'ta pre-clean.
- **(2) Banner + overscroll (global):** Üst banner çerçevesi/zemini ŞEFFAF olsun (scroll'da üstü kapatmasın); overscroll mor glow KALDIRILSIN (Material stretch/glow → `ScrollBehavior` ile kapat); HgGlass'taki "mor parlama" pasifken arka plandan ayrışıyor → glow/tint yumuşatılacak.
- **(3) Home eyebrow "ÇEVRİMDIŞI":** desteklenen dillerde sürekli fade-out/in ile döngü (her dilde "çevrimdışı"); online→yeşil + "çevrimiçi" dillerde döngü, offline→coral. Offline kötü değil iyi hissi.
- **(4) Manuel çeviri:** alt kısım boş/ekran yukarı kaymış (scroll:false yaptım → Column yukarı toplandı; düzelt — alanı doldur/ortala); input alanı "2 iç içe kutu" görünüyor (HgGlass içinde TextField'in kendi dekorasyonu → fazlalık çerçeveyi kaldır).
- **(5) Boş transkript silme:** Konferans + SmallTalk'ta boş transkriptler hâlâ kayıtlı kalıyor (oysa empty-session-delete eklenmişti — neden tetiklenmiyor araştır, fix).
- **(6) Görsel Çeviri TAM overlay:** tüm ekran fotoğraf olsun; tier/kaynak-hedef/sonuç/galeri/fotoğraf çek hepsi ŞEFFAF + fotoğrafın ÜSTÜNDE. Fotoğraf çekilmeden önce boş preview yer kaplamasın (sadece çek/galeri CTA).
- **(7) Açılış + NLLB daima-RAM:** düz siyah yerine şık animasyonlu splash; açılışta NLLB RAM'e (en çok kullanılan, kullanıcı beklemesin, arka planda daima). Offline LLM özet istendiğinde: NLLB unload → özet LLM load → özet → LLM unload → NLLB reload (sessiz, kullanıcı bilmez).

### 🆕 UI TUR 2 KALANI — Poco cihaz testi (2026-06-13, Mehmet birebir)

> "manuel çeviri ekranı çalışmıyor de-risk menüsünü ana ekranı taşi şimdilik özenli bir tasarıma gerek yok final versionda de-risk oradan kaldırılacak zaten. manuel çeviriyi düzelt deney menüsünü içerde tutmana gerek yok. görsel çeviride her şey harika sadece ön izleme ekranı çok küçük kalıyor onu mümknü olduğunca büyüt."

**Analiz / yapılanlar (2026-06-13, aynı oturum — kod düzeltildi, yeni APK build):**
- **Manuel çeviri çalışmıyordu — KÖK NEDEN bulundu + FIX:** `HgScreen(scroll:true)` `IntrinsicHeight` kullanıyor; `TextField`'in içindeki `LayoutBuilder` intrinsic dimension desteklemiyor → "LayoutBuilder does not support returning intrinsic dimensions" runtime exception → ekran patlıyordu (probe testiyle birebir doğrulandı). FIX: Manuel `HgScreen(scroll:false, padded:false)` + kendi `SingleChildScrollView`'i (OCR'deki çözümün aynısı). **Aynı tuzak: HgScreen scroll:true içine TextField veya LayoutBuilder KOYMA.**
- **De-risk/deney menüsü → Home'a taşındı:** `main.dart` Manuel'den `_devMenu`/`_devItem` + 13 dev-ekran importu kaldırıldı; `home_screen.dart` header'ına basit cam science ikonu + aynı popup menü eklendi (özenli tasarım yok — final'de tümüyle kaldırılacak).
- **Görsel Çeviri önizleme büyütüldü:** viewport artık `Expanded` (kalan tüm dikey alanı doldurur) + `BoxFit.contain` eşlemesi (kutular letterbox offset'iyle `dx`/`dy`). Scroll kaldırıldı (viewport maksimum). "her şey harika" — Lens akışı onaylandı.
- **Henüz cihazda DOĞRULANMADI** (yeni APK build edilip kuruldu, Mehmet tekrar bakacak): Manuel artık açılıyor + çalışıyor mu; dev menü Home'da; OCR önizleme yeterince büyük mü.

### 🆕 UI TUR 1 (Mercury Home) — Poco cihaz testi (2026-06-12, Mehmet birebir)

> "arka planın gündüz modunda hareket etmesi gerekiyordu ama etmiyor ayrıca ayarlar logosu yamulmuş gibi duruyor(butonda sorun yok logo.jpg de sorun var gibi). 4 mod satırı vs. hepsi doğru satıra gidiyor. ay/güneş toggle gayet iyi ve güzel çalışıyor. henüz kaydırma işlevini gerçekleştirebileceğim bir ekranım olmadığı için test edemiyorum uygulamanın her aşamasına UI'ı implemente et. görsel çeviriy google lens gibi yap baştan sona bir overhaul getir mesela çekilen fotoğrafta belirli bir alanı seçip oranın çevirisini isteyebilelim"

**Analiz / yapılacaklar:**
- **A) Mesh hareketi yok:** Tur 1 statik mesh'ti (bilinçli). Fix: `MeshOverlay` drift blobları (hg-drift-0..3 keyframe'leri, 17-23s ease-in-out alternate) + reduce-motion saygısı.
- **B) Ayarlar dişlisi yamuk:** ekran görüntüsüyle doğrulandı (merkez kaymış, dişler bozuk) — prototipin sıkıştırılmış arc-flag'li gear path'i `path_drawing`'de yanlış parse oluyor. Fix: dişliyi açık-parametreli temiz path ile değiştir; diğer ikonlardaki sıkıştırılmış flag'leri de aç.
- **C) Navigasyon ✅, ay/güneş toggle ✅** (Mehmet: "gayet iyi ve güzel çalışıyor").
- **D) TÜM EKRANLARA UI (Mehmet talimatı):** aşamalı plan iptal — wizard, SmallTalk canlı (5 faz), PTT split, Konferans (setup+canlı+detay+arşiv), Manuel, Ayarlar, arşivler, gate'ler hepsi liquid-glass'a tek seferde geçirilecek; sonra tek cihaz testi.
- **E) Görsel Çeviri = Google Lens tarzı overhaul (feature):** çekilen/seçilen fotoğraf ekranda; kullanıcı **belirli bir alanı seçip** o alanın çevirisini isteyebilmeli (ML Kit blok bounding box'ları + bölge seçimi → seçilen metni çevir).

### 🆕 (B) GEMİNI + SpeechService + Crunch 2-adım — Poco cihaz testi (2026-06-11, Mehmet birebir)

**Mehmet (birebir):**
> "6. Geçersiz anahtar testi: bilerek yanlış bir anahtar gir → net hata mesajı çıkıyor mu (sonsuz dönme değil)? **kabul etti, etmemeliydi.**"
>
> "Gemini çevrimiçi crunch (yukarıdaki 6 adım — internet gerekli): **doğru keyi girdikten sonra yine başarısız: http401, expected OAuth 2 acces token**"
>
> "SpeechService çökme fix (ısınma → sistem geri → tekrar gir → "already exist" çıkmamalı): **sorun yok hata çıkmıyor. ancak yinede boş transkript olarak dosyalara kayıt gerçekleşiyor boş olanları kayıt etme otomatik sil.**"
>
> "Crunch 2-adım (bitiş → detay → Derinlemesine Çevir → Özetle): **başarılı özet ve transkript ayrı ayrı adımlar ancak sorun ikiside sanki aynı adımmış gibi görünüyor "daha iyi çevir" gibi spesifik bir indicator olmalı hala çevir ve özetle yazmamalı**"
>
> "Vosk EN doğruluk (🧪 vosk_en_derisk → daanzu vs small-0.15): **bir sonraki adımda da onu test edeceğim henüz test etmedim**"

**Analiz / yapılacaklar:**
- ✅ **SpeechService çökme fix DOĞRULANDI** ("already exist" hatası çıkmıyor).
- ⏳ **Vosk EN doğruluk** testi bekliyor (daanzu cihaza push edildi 2026-06-11, 1.4GB, `.../files/vosk_en_derisk/vosk-model-en-us-daanzu-20200905`).
- **A) Gemini 401 "expected OAuth 2 access token":** Kod DOĞRU — anahtarsızlık testi (`curl` sahte key, `?key=` + `x-goog-api-key` her iki yöntem) **400 "API key not valid"** döndürüyor, 401 değil. 401 "expected OAuth2", sunucunun isteği **hiç anahtar yokmuş gibi** görmesi = anahtar AI Studio (Gemini API, `AIza…`) anahtarı değil VEYA projede Generative Language API OAuth gerektiriyor. **Kod fix'i çözmez → anahtar/proje kaynaklı.** Mehmet'in anahtar kaynağı doğrulanacak.
- ✅ **B) Geçersiz anahtar kabul ediliyor — FIX EDİLDİ (2026-06-12):** `GeminiClient.validateKey()` (`GET /v1beta/models?key=`) Ayarlar `_editGeminiKey`'e bağlandı — yalnız 200'de kaydedilir, hata (400/401/403) kaydetme anında snackbar'da görünür. Cihaz smoke bekliyor.
- ✅ **C) Boş transkript oturumları kaydediliyor — FIX EDİLDİ:** `end()` mesajsız oturumu otomatik siler, `null` döner (`deleteSessionIfEmpty`, 3 session sınıfı, 2026-06-11). 2026-06-12: kırık kalan 4 test yeni davranışa güncellendi + 3 yeni boş-oturum testi eklendi.
- **D) Crunch giriş etiketi kafa karıştırıcı:** Bitiş ekranı butonu hâlâ **"Çevir & Özetle"** diyor (push_to_talk + smalltalk ended view) ama detayda 2 ayrı adım var. Fix: bitiş butonu "çevir ve özetle" dememeli + ilk adım "Derinlemesine Çevir" → **"Daha İyi Çevir"** gibi spesifik etiket (canlı çeviriden ayrışsın).

### 🧪 CRUNCH MODELİ DE-RISK — Poco cihaz testi (2026-06-09, Mehmet birebir)

> "gemma yeteli seviyede, qwen bozuk karakterler kullanıyor ve soru sormaya çalışıyor, phi çöktü, gemma'yı kullanırız ama yeterli ram'i olmayan sistemler için gemma çalıştırılmayacak ve kendilerine transkripti kopyalyabilme imkanı tanınacak veya kendi api keylerini girebilecekleri arayüz sağlanacak. gemma 4'ü de test etmek istiyorum"

**Sonuç/karar:**
- **Crunch modeli = Gemma3-1B-IT q8** (yeterli). Qwen2.5-1.5B elendi (bozuk karakter + özet yerine soru soruyor/cevaplıyor). Phi-4-mini çöktü (Poco 8GB'de OOM doğrulandı → üst tier flagship'e ait).
- **Düşük-RAM cihaz fallback (YAPILACAK):** Gemma3 bile çalışmayan cihazlarda crunch on-device YAPILMAZ → (a) transkripti **kopyalama** imkânı + (b) kullanıcının **kendi API anahtarını** girebileceği arayüz (online crunch). 
- **gemma-4-E2B (2.47GB, .litertlm) DE-RISK SONUCU: ELENDİ (native invoke hatası).** Mehmet "gemma 4'ü test etmek istiyorum" → eklendi, cihazda denendi. Model yüklendi ama ÜRETİMDE çöktü (Mehmet birebir): `PlatformException (LiteRtLmJniException ... Failed to call nativeSendMessage: INTERNAL: ERROR ... lm_litert_compiled_model_executor.cc:786 Failed to invoke the compiled model)`. → generic `gemma-4-E2B-it.litertlm` SD860 + flutter_gemma 0.13.6 LiteRT-LM runtime ile **çalışmıyor** (backend/derlenmiş-model uyumsuzluğu; CPU backend zorlanmıştı). Cihaz-özel varyantlar (qualcomm_sm8750=SD8Elite, Tensor_G5…) Poco'ya ait değil. **Sonuç: gemma-4 bu stack'te kullanılamaz → Gemma3-1B kararında kalındı.**
- **De-risk altyapısı:** 🧪 "Crunch Modeli De-risk" ekranı (`crunch_derisk_screen.dart`) — sabit TR örnek konuşmayı gerçek crunch promptlarıyla (translate=kimlik) modelle özetler; `fromFile` ile adb-push'lu `crunch_derisk/` dosyalarından yükler.

### 🟢 NLLB TÜM YÜZEYLER — Poco cihaz testi (2026-06-08, Mehmet birebir)

> "her şey yerli yerinde nllb de-risk ekranında çalışıyor ama manuel çeviri de ml kit çalışmıyor, bas-konuş akıllı mod olarak çalıştırıldığında app çöküyor. konferans modu akıllı mod çalışıyor ancak aşırı yavaş kullanıcı'ya sisteminin kapasitesine göre tavsiyede bulunmamız gerek telefonları üst düzey ise full modu kullanabileceklerini veya kullanmamaları gerektiğini tavsiye etmeliyiz. konferans modunda da aynı şekilde ml kit çalışmıyor ama iyi haber en azından çökmek yerine "no existing model file" hatası fırlatıyor. hands-free modda full modu test edemiyorum çünkü 400mb indirme var ve yeterli internetim yok daha sonra test etmemi hatırlat. ayrıca hands-free için 3. bir mod ekleyeceğiz: fast: ml kit + vosk, full whisper + ml kit, full+: whisper + nllb şeklinde olacak."

**Analiz (sıradaki tur işleri):**
- **Bas Konuş Akıllı çökme = OOM** (logcat `signal 9 (Killed)` = lowmemorykiller). Vosk + NLLB 1.3GB Poco 8GB'de zirvede aşıyor. Konferans (Vosk streaming + NLLB) ucu ucuna sığıyor (yavaş). → **F1 (cihaz kapasitesi tavsiyesi)** zorunlu; ayrıca Bas Konuş full'de NLLB OOM'a karşı önlem (warn/blok düşük-RAM'de).
- **ML Kit "no existing model file" (Manuel + Konferans fast) — KÖK NEDEN ÜÇ KATMAN:**
  - (1) **Readiness yalanı** (MLKit "hep hazır" varsayılıyordu) → **DÜZELTİLDİ** (`isTierReady` + indirme kapısı her yerde: ModelTierSelector+langs, language_select fast/full, conference/smalltalk MLKit gate, 2026-06-08).
  - (2) `downloadModel` varsayılan `isWifiRequired:true` → **DÜZELTİLDİ: `isWifiRequired:false`** (GoogleMLKitEngine). Ama asıl sorun bu değilmiş.
  - (3) **GERÇEK ENGEL (KOD DEĞİL — CİHAZ/GMS):** ML Kit çeviri modelini telefonun **GMS (Google Play Services)** indirir; biz sadece tetikleriz. Mehmet'in Poco/MIUI'sinde GMS indirmeyi **tamamlamıyor**. Kanıt: cihazda `no_backup/com.google.mlkit.translate.models` **boş** (sadece `temp/`); `download_manager.xml` 3 dili denemiş (en_es/en_fr=gvt1.com, en_tr=dl.google.com); PC'den CDN **erişilebilir** (200/302) → ağ engeli YOK; 40+ dk WiFi açık önde → dizin boş. Muhtemel: MIUI agresif arka plan/pil kısıtı GMS indirmesini öldürüyor. **ML Kit paketlenemez/elle atılamaz** → her cihazın GMS sağlığına bağımlı. **NLLB GMS'siz offline çalışıyor → güvenilir yol.** **PARK** (Mehmet). Yarın: GMS testi (Google Çeviri offline TR + MIUI pil whitelist) + kodda timeout/hata UX.
- **Konferans full aşırı yavaş** (S860). Kasıtlı (NLLB CPU). → F1 ile yüksek-uç cihazlara öner, ortada/düşükte fast öner.
- **F2 — Hands-free 3 katman:** fast = ML Kit + Vosk; **full = Whisper + ML Kit** (yeni orta katman); full+ = Whisper + NLLB. (Önceki full=Whisper+NLLB → artık full+.) Setup'taki 2-seçenek → 3-seçenek.
- **R1 — HATIRLAT:** Hands-free full(+) cihaz testi BEKLİYOR — Whisper small ~400MB indirme + Mehmet'in interneti yetersizdi; internet olunca test edilecek.

### 📥 İNDİRMELER → MERKEZİ AYARLAR (2026-06-09, Mehmet birebir — F2 smoke sonrası yeni yön)

> "her şey yerli yerinde ama artık gözümüzün gördüğü her yere indirme ekranı koymayacağız. artık bütün indirmeler ana menüdeki ayarlar menüsünden gerçekleşecek eğer bir model yüklü değilse örn: tam/tam+'da olduğu gibi ayarlardan indirmesi istenecek ve ayarlarda detaylı bir şekilde indirme bilgisi verilerek indirme gerçekleştirilecek(hız, boyut, % vb.)"

**✅ KOD YAPILDI (2026-06-09): F3 tamam** — `ModelsRequiredGate` + inline kapılar kaldırıldı + Ayarlar hız/boyut/%/ETA; analyze temiz, 169/169 test, APK Poco'da.

**🟡 CİHAZ SMOKE (2026-06-09, Mehmet birebir):** "hız, % ve ETA görünmüyor" (boyut görünüyor). **TEŞHİS:** İndirdiği model **ilerleme bildirmeyen** tipte (ML Kit veya Whisper). hız/%/ETA yalnız **progress-veren** modellerde çalışır: **Vosk / NLLB / LLM (Gemma/Qwen/Phi)** ✅ (http streamed, `onProgress` 0–1). **ML Kit** = GMS indirir, progress callback YOK → imkânsız. **Whisper small** = `whisper_ggml.downloadModel` `consolidateHttpClientResponseBytes` ile tek seferde indiriyor, progress YOK → yalnız boyut. **SIRADAKİ TUR FIX (F3b):** Whisper'ı paket yerine kendi streamed http indirmemizle (Vosk/NLLB gibi `http` + byte sayacı → onProgress) indir → %/hız/ETA çıksın. ML Kit için imkânsız (boyut + "indiriliyor…" kalır). Mehmet'in büyük indirmeleri (NLLB 1.3GB) zaten tam stat gösteriyor.

**Analiz (yeni iş — "F3: Merkezi İndirme"):** F2 cihaz smoke GEÇTİ (3 katman yerli yerinde). Yeni mimari kararı: **tüm model indirmeleri yalnız Ayarlar'dan.** Mod giriş ekranlarındaki inline indirme kapıları kaldırılacak; model yüklü değilse "Ayarlar'dan indir" yönlendirmesi (indirme YapMA, sadece bilgilendir + Ayarlar'a yönlendir). Ayarlar indirme UI'si zenginleştirilecek: **hız + boyut + % + (ETA?)**. Etkilenen inline indirme noktaları: `ModelTierSelector._download` (language_select/manuel/ocr), `conference_screen._prepareModels`, `smalltalk_screen._download/_downloadGate`, `main.dart._handleLanguageChange` (MLKit dialog). Ayarlar = `settings_screen.dart` + `managed_model.dart` (zaten merkezi yönetici). Bu, Faz 4 UI'den ÖNCE veya sonra olabilir — Mehmet'e sırayı sor.

### 🧠 F1 DÜŞÜK-RAM/OOM UYARISI — Poco cihaz testi ✅ GEÇTİ (2026-06-09, Mehmet birebir)

> "her şey belirttiğin gibi çalışıyor."

**Bağlam:** Bas Konuş "Akıllı" + Konferans "Akıllı (NLLB)" + SmallTalk hands-free "Full" seçilince ~7.4GB düşük-RAM uyarı dialogu çıkıyor (İptal→fast'te kalır / Yine de kullan→devam); "Hızlı/fast"ta uyarı çıkmıyor. Üç modda da doğrulandı. **F1 TAMAMEN BİTTİ (kod + cihaz).**

### ⏱️ ML KIT TIMEOUT + GMS — Poco cihaz testi (2026-06-09, Mehmet birebir)

> "ML kit artık çalışıyor. hata mesajının çıkıp çıkmadığını test edemedim ancak gerek yok önemsiz sıradaki işten devam et"

**Analiz:** ML Kit indirme/çeviri Poco'da artık çalışıyor (muhtemelen Mehmet'in paralel GMS testi — Google Çeviri offline TR + MIUI pil whitelist — GMS'i sağlığa kavuşturdu). Timeout + `MlKitDownloadException` net-hata UX kodu yine de yerinde (cihazda GMS bozulursa sonsuz "indiriliyor" yerine NLLB'ye yönlendirir); hata mesajı cihazda gözlemlenmedi ama Mehmet önemsiz dedi → F1'e geçtik. ML Kit/GMS artık PARK değil, çalışır durumda.

### 🎤 KONFERANS MODU (eski Ders Modu) yeniden tasarım — K1 cihaz testi (2026-06-04)

Mehmet "Ders Modu"nu **Konferans Modu** olarak baştan tasarlattı (açık/beyaz tema, sade giriş = sadece 2 dil + seslendirme sorusu + ısınma ekranı/gri yuvarlak buton, canlı çeviri=MLKit destek amaçlı, transkript arka planda gizli/kayıtlı, oturum sonu Qwen "crunch" = tam çeviri+özet+başlık, "crunch later" → ana menüde klasör/arşiv). 4 sub-step: K1 (rename + setup akışı + Manager.prepare/start ayrımı + çalışan ekran translation-only), K2 (running polish — K1'e foldlandı), K3 (DB v3 crunch sütunları + arşiv klasörü + detay), K4 (Qwen crunch servisi + ilerleme).

**K1 CİHAZ TESTİ — ✅ GEÇTİ (Mehmet, birebir):**
> "her şey çalışıyor ama transkript biraz daha hızlı çalışması lazım nüyük ihtimalle speech to text ile alakalı ya da chunk boyutu biraz küçültülebilir. bunu konferans modunun sonundaki polish için not düş ve devam et"

**Konferans Modu polish notu (sonunda ele alınacak):** Transkript biraz daha hızlı olmalı. Aday kökenler: (a) STT motoru (Vosk/Whisper) hızı; (b) `StreamingAudioInput` chunk boyutu (~5sn `maxSegmentDuration`) biraz küçültülebilir → daha sık/daha hızlı commit. Trade-off: çok küçük chunk → daha fazla STT çağrısı + parça-ortası kelime bölünmesi. K4 sonrası konferans modu polish'inde dene (chunk ~3-4sn? + STT hız ölç).

**K3 sonrası BUG (2026-06-05, Mehmet birebir) → ✅ DÜZELTİLDİ:**
> "uzun konuşmadan dolayı diye tahmin ediyorum ki çeviri takılı kaldı konferansı bitir butonu çalışmıyor. büyük ihtimalle hala queue daki işleri bitirmeye çalışıyor ve en son çöktü." + düzeltme: "pardon çökmedi büyük ihtimalle senin app i güncellediğin an program kapandı bende çökütü sandım. tamam sorun hala var ama çökmüyor en azından"
>
> **Kök neden (doğrulandı):** Uzun/sürekli konuşmada STT ~5sn chunk'lara yetişemeyince Manager `_pipelineQueue` sınırsız büyüyor. `end()` `await _pipelineQueue` ile TÜM backlog'u bekliyordu → "Bitir" yanıt vermiyor. Ayrıca in-flight `_processUtterance` bitince `_setState(listening)` ile `end()`'in koyduğu `ending` state'ini eziyor → sıradaki kuyruk öğeleri erken çıkamıyor → backlog tamamen işleniyor.
> **Fix:** (1) ezilmeyen `_stopping` bayrağı — `end()` set eder, `_processUtterance` her ağır await (transcribe/translate) sonrası kontrol edip erken çıkar; `end()` artık yalnız o an çalışan TEK transcribe'ı bekler (iptal edilemez native çağrı). (2) Backpressure: `_maxPendingUtterances=3` — STT canlı hızdan yavaş kalırsa fazla chunk düşürülür (`ConversationDropped` "backpressure"), OOM/sınırsız birikme yerine "geride kalındı". Transkript kaybı kabul; asıl çözüm STT hız polish'i (yukarıda). 95/95 test (2 yeni regresyon testi: end()-takılma + backpressure).

**K4 CRASH (2026-06-05, Mehmet birebir) → ✅ DÜZELTİLDİ:**
> "klasörden crunch işlemi sırasında app crash verdi ve kapandı"
>
> **Kök neden (logcat crash buffer ile DOĞRULANDI):** Native flutter_gemma/MediaPipe `nativePredictSync` → `CheckJNI NewPrimitiveArray` JNI **abort** (debug CheckJNI hard-abort). Sebep: ilk crunch servisim "rolling summary" kullanıyordu — büyüyen özeti her chunk'ta prompt'a geri besliyordu. Uzun konferansta prompt token sayısı Qwen'in bağlam penceresini (ekv1280, session maxTokens 1024) aşıyor → üretim budget'ı negatif → MediaPipe negatif boyutlu array alloc → abort.
> **Fix:** CrunchService **bağlam-güvenli map-reduce**'a çevrildi (`crunch_service.dart`): her LLM çağrısının GİRDİSİ sıkı sınırlı — (a) çeviri parça başına ≤350 char; (b) her parça BAĞIMSIZ kısa nota indirgenir (büyüyen özet beslenmez); (c) notlar kademeli/hierarchical reduce ile birleştirilir (her reduce penceresi ≤1200 char). Hiçbir prompt bağlamı zorlamaz. `_chunk` kelime-bazlı paketleme (uzun tek satırı da böler). 100/100 test (CrunchService chunk/not/reduce/başlık + ilerleme + başlık-temizleme). **NOT:** debug CheckJNI bunu hard-abort'a çeviriyor; release'de farklı olabilirdi ama bağlam taşması her hâlde yanlış → fix doğru. **Açık risk:** çok uzun konferansta map-reduce çok Qwen çağrısı = uzun sürer (ilerleme çubuğu var); kalite/süre cihazda görülecek.

**K4 CİHAZ TESTİ — ✅ GEÇTİ (crunch çalışıyor, çökme yok) + 2 YENİ SORUN (2026-06-05, Mehmet birebir):**
> "her şey doğru çalışıyor ancak en önemli sorunumuz tanskript oluşturma hızı. konuşma devam ederken çeviri çok geride kalıyor aynısını gemini vs ile yaptığımda çok daha hızlı kelimeleri yazıya dökebiliyorlar. sistemi nasıl onların hızına çıkarabiliriz. bug: qwen özetinde ve çevirisinde değişik karakterler beliriyor. hız sorunundan dolayı bazı cümleler ve kelimeler atlanıyor ve context kaybı yaşanıyor."

**Ayrıştırma — Konferans Modu'nun KALAN 2 polish işi (en kritik #1):**
1. **⚡ TRANSKRİPT HIZI (EN ÖNEMLİ).** Konuşma sürerken transkript/çeviri çok geride kalıyor; Gemini vb. çok daha hızlı canlı yazıya döküyor. Hız yetmediği için backpressure chunk düşürüyor → **cümle/kelime atlanıyor + context kaybı**. **Kök fark:** bizimki dosya-bazlı, chunk-chunk STT (~5sn segment → WAV → Vosk/Whisper `transcribeFile`); Gemini = bulut **streaming ASR** (GPU, gerçek-zamanlı, kelime kelime). On-device "onların hızı" için yol:
   - **Vosk native streaming** (`SpeechService.onPartial/onResult`) — kelime kelime canlı, dosya turu yok. VoskTestScreen'de çalışmıştı; ayrı/büyük iş: Manager pipeline'ını bypass eder + Whisper fallback'i yok + çeviriyi partial mı final mi tetikleyeceğiz tasarlanmalı. **Bu, "Gemini hızı" hissinin asıl cevabı.**
   - Ara çözümler: chunk boyutunu küçült (`StreamingAudioInput` ~5sn → 2-3sn), Whisper `quality` full→ daha hafif model (base/tiny) konferans için, STT thread/ayar tuning. Bunlar yardımcı ama streaming kadar değil.
   - **Karar Mehmet'e:** Vosk native streaming'e geçiş büyük iş — Konferans polish'inde öncelik. (Backpressure cap'i de bu çözülünce gevşetilebilir.)
2. **🔣 QWEN ÇIKTI BOZUK KARAKTER (crunch).** Qwen özet + çevirisinde "değişik karakterler" beliriyor. Aday: özel/kontrol token sızması (`<|im_end|>`, `<0x0A>` vb.), eksik UTF-8, ya da map-reduce birleştirme artefaktları. **Fix adayı:** CrunchService/LlmTranslationEngine çıktısını sanitize et (özel token + non-printable temizle), gerekirse prompt'a "plain text only" vurgusu. Konferans polish'inde ele alınacak.

**→ Konferans Modu K1–K4 KOD TAMAM (rename + setup + çalışan + crunch + arşiv), cihazda çalışıyor. KALAN = yukarıdaki 2 polish (hız #1 kritik + bozuk karakter). Bunlar "Konferans Modu sonu polish" turunda.**

### 🗣️ SMALLTALK (eski Voice Translator) — S1+S2+S3 KOD TAMAM, cihaz testi (2026-06-05, 3. oturum, Mehmet birebir)
> "bas konuşta gemma ve qwen çalışmıyor, hands-free'de kim konuştu kararını verme konusunda iyi ama istediğimiz düzeyde bir başarı sunamıyor buna alternatif olarak ne yapabiliriz? çok istemesemde whisper'a dönüş mü yapsak?"

**✅ KARAR (Mehmet 2026-06-05, birebir) — HANDS-FREE = FAST/FULL:**
> "fast/full moduna geçişi yapacağız: hands-free'de kullandığımız **vosk motorunu tutmaya devam (fast mod)** ve iyileştir. **full modda whisper.** her şeye rağmen 2sinden de iyi alternatif aramaya devam (daha büyük vosk / kotlin 2 mic / başka yol)."
- **Fast = Vosk** çift-recognizer + güven skoru (mevcut S3, histerezis+eşikle iyileştir). Hızlı + canlı partial.
- **Full = Whisper** `language:auto` (gerçek dilde yazar) + **MLKit Language ID** ile master/local yönlendirme (Vosk'ta imkansızdı, Whisper çok dilli olduğu için çalışır). Daha doğru, daha yavaş, partial yok.
- Setup'ta fast/full seçimi (mevcut `SessionQuality.fast/full` enum'u tam bunun için). İki motor da `DualTranscriber` arayüzünü uygular → `SmallTalkStreamingSession` + ekran ikisini de kullanır (Whisper transcriber tek transkripti dil tespitine göre master/local slot'una koyar).
- **full+ (Mehmet fikri, ileride):** konuşmacı **diarizasyonu (voiceprint) + Vosk** — diarizasyon "kim" (master/local sesi) der, her kişinin dili bilindiği için o dilin Vosk'u kullanılır → en güvenilir + Vosk hızı. Ekstra on-device diarizasyon modeli (ECAPA/x-vector ONNX) + tuning gerektirir → keşif turu. (SessionQuality enum şimdilik fast/full; full+ eklenince 3. değer + DB migration.)
- **Dual-mic Poco'da kapalı** (6r-d, 5 kombinasyon başarısız — donanım sınırı); farklı cihaz/iPhone'da Faz 2. **Açık keşif (ileride):** daha büyük Vosk modeli, dual-mic farklı cihaz, full+ diarizasyon.

**Ayrıştırma + çözüm yönü:**
- **(1) Bas Konuş'ta Gemma/Qwen canlı çeviri çalışmıyor.** ("başlıyor ama konuşunca çeviri hiç gelmiyor.") → Bas Konuş çeviri hatalarını YUTUYORDU (`_onEvent` yalnız mesajı işliyordu); **hata görünür yapıldı** (kırmızı banner). Mehmet: Gemma/Qwen canlı kısa-cümle çevirisi için DÜZELT (özet beklentisi yok). Sonraki cihaz testinde çıkan hata metnine göre kök fix. APK hazır, cihaz bağlı değildi → kurulum bekliyor. SmallTalk/Konferans tasarımı = **canlı çeviri MLKit, kalite Qwen CRUNCH'ta**. Bas Konuş'taki 3-katman tier seçici eski tasarımdan kalma. Çözüm: Bas Konuş'u da Konferans gibi **MLKit canlı**'ya çevir (tier seçici kaldır) → bug gider + tutarlılık. (3-katman Manuel'de durmaya devam.)
- **(2) Hands-free konuşmacı tespiti güven-skoruyla "iyi ama yeterli değil".** **Kök sınır:** Vosk tek-dilli → her tanıyıcı sesi ne olursa olsun KENDİ dilinde yazar → MLKit ayırt edemez, sadece akustik conf kıyası kaldı (zayıf sinyal). **Whisper farkı:** Whisper **çok dilli**, `language:auto` ile konuşulanı GERÇEK dilde yazar → çıktıya MLKit Language ID = güvenilir master/local ayrımı. Bedeli: segment başına Whisper (Vosk'tan yavaş) + canlı kelime-kelime partial kaybı.

**✅ ÇÖZÜM (Mehmet kararı) — HANDS-FREE = FAST/FULL (kod tamam, 140/140 test):**
- **fast = Vosk** çift-recognizer + akustik güven skoru + **histerezis** (yakın güvende son konuşanda kal — `_routeWithHysteresis`, margin 0.15). Hızlı + canlı partial.
- **full = Whisper** `language:auto` + **MLKit Language ID** → `WhisperLangIdTranscriber` (DualTranscriber; tek transkripti algılanan dile göre master/local slot'una koyar → orkestratör değişmez; `slotFor` saf+test). Partial yok ("dinleniyor").
- Setup'a fast/full adımı; her moda göre indirme kapısı (fast=2 Vosk, full=Whisper small ~466MB).
- **full+ (ileride):** diarizasyon (voiceprint ONNX) + Vosk = kişi-bazlı, en güvenilir; ekstra model → keşif. SessionQuality şimdilik fast/full.

**🔑 CİHAZ KÖK NEDEN + YENİ İŞLER (Mehmet birebir):**
- "bas konuşta gemma/qwen çalışmıyor (başlıyor ama çeviri gelmiyor)" + "model silinmiş crunch da çalışmıyor" → **Qwen modeli cihazdan SİLİNMİŞ** (yer içindi). Bu yüzden hem Bas Konuş LLM hem crunch çalışmıyor (eskiden Qwen vardı → çalışıyordu). Yer artık var.
- **BUG: "Çeviri motoru" (`ModelTierSelector`) silinen modeli 'indirili/Model hazır' gösteriyor (yanlış pozitif)** → warmup geçer, çeviri/crunch sessizce patlar. `LlmTranslationEngine.isLanguageReady`/`_installedId` dosya varlığını doğrulamıyor (`flutter_gemma listInstalledModels` stale).
- **SIRADAKİ (NS):** **NS-1** Ana menü Ayarlar'a (sağ üst dişli; `SettingsScreen`/`ModelRegistry` var ama LLM YOK) **Gemma+Qwen ekle** (gör/indir/sil + Gemma HF token). **NS-2** yanlış-indirili tespiti fix (gerçek dosya doğrula). **NS-3** HF token persistence (dart-define/secure storage; [[ref-hf-token]], repo'ya gömme). **NS-4** modelleri yeniden indir. **NS-5** Bas Konuş'ta MLKit+Gemma+Qwen üçü seçilebilir kalsın (canlı kısa-cümle çevirisi, özet değil). **NS-6** fast/full cihaz smoke.

**✅ POLISH KOD TAMAM (2026-06-05, 2. oturum — cihaz testi bekliyor, Mehmet AFK):**
- **#2 🔣 BOZUK KARAKTER — KOD ✅:** `lib/core/utils/llm_text.dart` `sanitizeLlmOutput`: SentencePiece byte-fallback token'ları (`<0xC3><0xA7>`→`ç`, ardışık toplanıp `utf8.decode`; geçersiz dizi atılır), özel/şablon token'ları (`<|im_end|>`, `<end_of_turn>`, `<eos>` vb.), metaspace `▁`→boşluk, replacement char + non-printable kontrol karakteri temizliği. `LlmHost.generate` çıktısına tek choke-point bağlandı → canlı çeviri **ve** crunch özeti birlikte temizlenir. 13/13 unit test. **Cihaz smoke bekliyor:** bir konferansı crunch et → özet/çeviride bozuk karakter kalmadı mı.
- **#1 ⚡ TRANSKRİPT HIZI = VOSK NATIVE STREAMING — KOD ✅ (Mehmet kararı: direkt streaming):** Manager'ı bypass eden ayrı pipeline.
  - `lib/core/engines/stt/vosk_streaming_controller.dart` — `StreamingTranscriber` soyutlaması + `VoskStreamingController` (native `SpeechService`: `createModel→createRecognizer→initSpeechService→onPartial/onResult`, mic izni; VoskTestScreen kalıbından ayrıştırıldı). Native → unit test edilmez, cihaz smoke ile doğrulanır.
  - `lib/core/session/conference_streaming_session.dart` — orkestratör (Manager muadili): final→`FillerCleaner`→MLKit çevir→`repository.appendMessage` (sourceText=transkript → **crunch uyumlu**)→`translations` yay→ttsEnabled ise seslendir. Partial yalnız `livePartial` (çeviri tetiklemez). `end()` başlık üretir+session kapatır+id döner. 8/8 orkestratör testi (sahte transcriber).
  - `lib/features/conference/conference_screen.dart` — streaming session'a geçti: model **indirme kapısı** (`VoskModelManager` + ilerleme, source dilinin modeli yoksa) → ısınma → running'de çeviriler + en altta soluk **canlı partial transkript** satırı (hız hissi). Crunch akışı aynen (`runConferenceCrunch` DB `sourceText`'ten).
  - Dosya turu (~5sn WAV→`transcribeFile`) + backpressure düşürme **kalktı** → konuşma geride kalmaz. **Cihaz smoke bekliyor:** TR/EN canlı kelime kelime partial + çeviri gecikmiyor + cümle atlanmıyor; model inmemiş dilde indirme kapısı; bitir→crunch çalışıyor.
  - **analyze temiz, 121/121 test** (önceki 100 + 13 sanitize + 8 streaming).
  - **CİHAZ TESTİ ✅ GEÇTİ — KONFERANS POLISH KAPANDI (2026-06-05, 2. oturum, Mehmet birebir):**
    - İlk tur: "harika çalışıyor ancak aynı çeviriyi 4 kere tekrarlıyor." → Streaming hız ✅; BUG: Vosk `SpeechService` EventChannel aynı finalize segmenti art arda yayıyor. **Fix:** `ConferenceStreamingSession._onFinal` ardışık aynı finali atlar (`_lastFinal`; 2 yeni test). APK yeniden kuruldu.
    - İkinci tur (fix sonrası): **"aynı çeviri artık tekrar etmiyor, bozuk karakterler artık ortadan kalktı."** → **#1 ⚡ hız+tekrar ✅ + #2 🔣 bozuk karakter ✅ İKİSİ DE CİHAZDA GEÇTİ. KONFERANS MODU POLISH TAMAMEN BİTTİ.**
  - **Açık seçenekler ÇÖZÜLDÜ (2026-06-05, Mehmet cihaz, birebir):** (i) **"canlı partial satırı çok güzel bir dokunuş olmuş kalsın"** → `_partialLine()` KALICI. (ii) **"ingilizcede vosk doğruluğunu daha sonra değerlendiririz şuan için yeterli"** → EN Vosk şimdilik yeterli, doğruluk değerlendirmesi sonraya (Whisper EN'e dönme opsiyonu açık).

### 🔬 TIER2 ARAŞTIRMASI → NLLB de-risk kararı (2026-06-04)

Mehmet 3-katman entegrasyonunda **önce Tier2 motorunu araştır** dedi (AskUserQuestion). Web araştırması + cihaz gerçekliğiyle adaylar elendi:

**Aday tablosu (on-device Flutter, SD860):**
- **opus-mt (ONNX):** Flutter paketi var (`onnx_translation` ham v0.1.2 / `flutter_onnxruntime`), tam offline, MIT. AMA kalite ≈ **MLKit ile aynı sınıf** (ikisi de küçük per-pair NMT) → güvenilir sıçrama yok. Her dil çifti ayrı model + ONNX dönüşüm kalite bug'ları. **Elendi** (MLKit'i net geçmez).
- **NLLB-200-distilled-600M:** **MLKit'ten +44% FLORES** (gerçek kalite sıçraması), tek çok-dilli model (200 dil). Boyut: CT2 int8 `model.bin` **623MB**; ONNX quantized encoder 419MB + decoder_with_past 445MB ≈ **~865MB**. Qwen q8 (1.57GB)'den **~yarı hafif**.
- **Bergamot (Firefox modelleri):** En iyi hız/boyut (~40MB/çift, 5-80ms) ama Flutter paketi yok, C++/JNI native (firefox-translator yazarı aylarca uğraşmış). **Elendi** (emek devasa).

**Mehmet'in iki sorusu + cevabım:**
1. *"opus-mt ile ML Kit'i kıyaslayalım"* → opus-mt ≈ MLKit, kıyas değeri düşük (yukarı).
2. *"NLLB Qwen'den hafif, Qwen yerine onu alsak?"* → **KRİTİK MİMARİ FARK:** NLLB = **saf çevirmen** (seq2seq, mantık yürütmez), Qwen = **LLM** (Vosk'un "minik pürüzlerini" toparlar — Mehmet'in LLM seçme gerekçesi tam buydu). NLLB Vosk garbled çıktısını **düzeltmez, sadık çevirir**. → NLLB Qwen'in **yerine değil**, gerçek bir **Tier2** (MLKit'ten iyi, Qwen'den hafif). Hedef mimari: **Tier1 MLKit (fast) / Tier2 NLLB (~865MB) / Tier3 Qwen (reasoning, Ders post-process)**.

**✅ MEHMET KARARI (AskUserQuestion):** **NLLB de-risk ekranı kur** — flutter_onnxruntime + NLLB ONNX ile **MLKit vs NLLB vs Qwen** cihaz kıyas ekranı (Qwen↔Gemma ekranı gibi, 3 kart). Tek entegrasyon iki soruyu yanıtlar: NLLB MLKit'i geçiyor mu + Qwen yerine/yanına yetiyor mu (reasoning farkı cihazda görünür).

**FİZİBİLİTE DOĞRULANDI (kod yazmadan önce):**
- **Tokenizer:** `dart_sentencepiece_tokenizer` (saf Dart, sıfır bağımlılık, HF `tokenizer.json` yükler, BPE+Unigram). NLLB tokenizer.json ~17MB. → tokenizer engeli aşıldı.
- **ONNX runtime:** `flutter_onnxruntime` veya `onnxruntime_flutter` (gtbluesky, ffi, olgun). Seq2seq KV-cache passthrough gerek.
- **Modeller:** Xenova/nllb-200-distilled-600M ONNX (encoder_model_quantized 419MB + decoder_with_past_model_quantized 445MB hazır). HF Optimum standart export → decode: encoder 1×, sonra decoder_with_past autoregressive, forced BOS = hedef dil token'ı (NLLB: decoder_start=eos(2), forced_bos=tgt_lang_id), greedy argmax → EOS.
- **Referans:** niedev/RTranslator (NLLB ONNX Android offline; 4-model'e bölmüş = ileri RAM optimizasyonu, biz standart 2-model export'la başlıyoruz).

**⚠️ RİSK (Mehmet'e iletildi):** Hazır Flutter NLLB paketi yok → Dart'ta tokenizer + seq2seq decode loop + ~865MB model indirme. Bu projedeki en ağır de-risk; tek burst değil. **Yaklaşım: önce dar fizibilite spike** (tokenizer yükle + encoder tek forward pass + SD860'ta yükleniyor mu), geçerse 3-kart ekrana genişlet.

**✅ SPIKE KODU YAZILDI (2026-06-04, cihaz testi bekliyor):**
- Paketler: `flutter_onnxruntime: ^1.7.1` (ORT 1.22, Android ✓, int64 ✓) + `dart_sentencepiece_tokenizer: ^1.3.2` (HF tokenizer.json yükler).
- `lib/core/engines/translation/nllb_onnx_translator.dart` — `NllbOnnxTranslator`. Tokenizer `tokenizer.json`'dan (`HuggingFaceTokenizerLoader.fromJsonString`); dil id'leri `convertTokensToIds(['tur_Latn'])` ile (fairseq offset YOK). **Decoder past'sız** (`decoder_model`, KV-cache YOK) → kalite birebir, hız yavaş (etiketli; her adım tüm sekansı + büyüyen logits transfer eder). NLLB format: kaynak `[src_lang]+subwords+[eos]`, decoder `start=eos(2)` + `forced_bos=tgt_lang`, greedy→eos. Debug getter'lar gerçek tensor adlarını gösterir (varsayım `input_ids`/`attention_mask`/`last_hidden_state`/`encoder_attention_mask`/`encoder_hidden_states`/`logits` yanlışsa ekranda görünür).
- `lib/core/models/nllb_model_manager.dart` — Xenova/nllb-200-distilled-600M ONNX: encoder_quantized 419MB + decoder_quantized 471MB + tokenizer.json 17MB (~890MB), streamed indirme (`.part`→rename) + ilerleme + sil. Non-gated.
- `lib/features/nllb_test/nllb_test_screen.dart` — **tek motor NLLB spike** (dev menü 🧪 → "NLLB Tier2 de-risk"): dosya indirme kartı + kaynak/hedef dil + metin + Çevir + çıktı + süre + debug. analyze temiz.
- **CİHAZ DE-RISK ADIMI:** APK kur (adb -r -d) → menüden NLLB ekranı → ~890MB indir → TR→EN birkaç cümle çevir → (1) yükleniyor mu, (2) kalite MLKit'i geçiyor mu, (3) hız/RAM. Geçerse 3-kart MLKit/NLLB/Qwen kıyasa + with-past optimizasyonu. **Açık riskler:** tokenizer normalization NLLB'ye birebir uymayabilir (Metaspace/precompiled_charsmap) → kalite düşebilir; past'sız decode SD860'ta çok yavaş olabilir; ONNX tensor adları farklıysa debug'dan düzelt.

**✅ CİHAZ DE-RISK SONUCU (2026-06-04, Mehmet birebir):**
> "yükleniyor, çıktı anlamlı ama kesinlikle qwen daha iyi sadece anlam kayması var onun dışında çeviri düzgün ve boşluk yerine "_" kullanıyor, bu spesifik örnek için mlkit çok daha doğru çeviri yapıyor. üretim çok yavaş qwen bile (yüklendikten sonra )5sn civarı sürerken nllb 12 sn civarı sürüyor. ayrıca kıyası denerken bir süre sonra app çöktü tahminimce qweni veya nllb yüklendikten sonra tekrar hafızadan silinmiyor her modelin yanında durdur butonu bulunsun."

**Ayrıştırma:**
1. **NLLB çalışıyor, çıktı anlamlı** ama **Qwen net daha iyi** (NLLB'de anlam kayması). **Bu örnekte MLKit bile NLLB'den daha doğru.** → Tier2 hipotezi ("MLKit'ten iyi") bu TR→EN örneğinde **DOĞRULANMADI**.
2. **"_" bug:** çıktıda boşluk yerine `▁` (SentencePiece metaspace U+2581) görünüyor → detokenize denormalize etmiyor. **FIX: çıktıda `▁`→boşluk.**
3. **Hız:** NLLB ~12sn vs Qwen ~5sn (yüklü). NLLB past'sız decode yavaş; KV-cache ile düşer ama Qwen'den iyi olması zor + kalite zaten düşük.
4. **Çökme:** modeller yüklendikten sonra RAM'den silinmiyor (NLLB ~900MB + Qwen ~1.5GB üst üste → OOM). **Mehmet isteği: her modelin yanında "Durdur/RAM boşalt" butonu.** → NLLB ekranına dispose butonu; 3-kart kıyas ekranında her modele ayrı dispose.

**ÖN DEĞERLENDİRME:** NLLB Tier2 olarak zayıf görünüyor (bu örnekte MLKit'ten kötü + Qwen'den yavaş). "_" fix + dispose sonrası Mehmet temiz bir kez daha bakacak; kalite hâlâ MLKit'in altındaysa **NLLB elenir → 2-katman (MLKit fast + Qwen quality)**. Karar Mehmet'in.

**✅ "_" FIX + DISPOSE + KV-CACHE (2026-06-04, cihaz testi bekliyor):**
- **"_" fix:** çıktıda `▁`(U+2581)→boşluk (`replaceAll`). **Dispose butonu:** NLLB ekranına "Durdur — RAM'den boşalt" (translator.dispose → ONNX session'ları kapatır; OOM çökme fix, Mehmet isteği).
- **Mehmet KV-cache hız opt. istedi → uygulandı** (`nllb_onnx_translator.dart` yeniden yazıldı): **3 oturum** — encoder + `decoder_model` (step0: cross-attn KV'yi encoder'dan üretip cache seed + forced tgt_lang) + `decoder_with_past` (step1+: tek token + KV). Tensor adları cihaz-dışı ASCII-grep ile DOĞRULANDI: decoder 12 katman; `decoder_with_past` encoder present'i re-emit ETMEZ (sabit cross-attn KV adımlar arası taşınır). **Verimlilik:** KV `OrtValue`'ları Dart'a çekilmeden (native id) doğrudan sonraki input'a geçer → round-trip yok + logits sabit `[1,1,vocab]` (büyüyen-logits transferi bitti). 4. model dosyası (`decoder_with_past_model_quantized.onnx` 445MB) eklendi → toplam ~1.3GB. analyze temiz.
- **CİHAZ DURUMU:** Telefon doluydu (226G'nin ~221G'si) → yer açmak için Qwen xnnpack_cache (1.55GB, yeniden üretilir) + reddedilen Gemma .task (555MB) silindi; **Qwen modeli sağlam** (ilk yükleme yavaş, cache yeniden oluşur). 4 NLLB dosyası adb push + run-as cp ile yerinde. APK arm64-only debug (~626MB; full-ABI 646MB sığmıyordu). **In-app indirici hâlâ Xet'te patlar — prod fix bekliyor.**
- **CİHAZ DE-RISK ADIMI (tekrar):** NLLB ekranı → TR→EN → (1) "_" gitti mi, (2) KV-cache ile hız ne (Qwen ~5sn'e yaklaştı mı), (3) kalite hâlâ MLKit/Qwen altında mı, (4) dispose butonu çökmeyi önlüyor mu. Sonuca göre: NLLB elenir → 2-katman, ya da kalite yeterse Tier2 entegrasyonu.

**✅ KV-CACHE CİHAZ SONUCU → NLLB ELENDİ (2026-06-04, Mehmet birebir):**
> "nllb 12sn sürüyor ortalama ara sıra 20sn nin üstüne bile çıkıyor bu kabul edilemez eğer 5 saniyenin altına düşüremezsen nllb'den kurtul yerine şimdilik gemma'yı koyalım hemen hemen aynı kalitedeyken daha kısa süreüyordu gemma. eğer nllb yi dahada hızlandırmanın bir yolu yoksa son karar: tier 1: mlkit, tier2:gemm(subject to change maybe a smaller model in the future), tier3: qwen. ders modu, bas konuş ve manuel çevirinin her birine model seçim imkanı sun"

**HIZ DEĞERLENDİRMESİ (Claude, dürüst):** KV-cache'e rağmen ~12sn (bazen 20+). **<5sn gerçekçi DEĞİL.** Kök neden: NLLB-600M encoder-decoder, token-token, 256k vocab lm_head/token, SD860 CPU + **Dart-orkestralı decode loop (flutter_onnxruntime method-channel/token)**. Gemma daha çok parametreli ama hızlı çünkü flutter_gemma=**MediaPipe native pipeline** (XNNPACK+native KV+GPU opsiyonu, tüm generation loop native). NLLB'yi eşitlemek native generation-loop (onnxruntime-genai/RTranslator tarzı, Android native kod + vocab shortlist + model surgery) ister = günler, belirsiz, SD860 garanti yok. Quantized ONNX ARM'da bazen fp'den de yavaş. → **NLLB <5sn için makul yol yok.**

**✅ SON KARAR (Mehmet): NLLB ELENDİ. 3-KATMAN = Tier1 MLKit / Tier2 Gemma (subject-to-change, ileride daha küçük model) / Tier3 Qwen.** + **Ders Modu, Bas Konuş, Manuel Çeviri'nin her birine model seçim imkanı.** NLLB kodu (nllb_onnx_translator, nllb_model_manager, nllb_test) deney/negatif-bulgu olarak kalır; cihazdaki 1.3GB ONNX modeli + ekran menüden kaldırılabilir (yer). flutter_onnxruntime + dart_sentencepiece_tokenizer paketleri NLLB'ye özel — başka kullanım yoksa sonra pubspec'ten çıkarılabilir.

### 🌐 3-KATMAN ÇEVİRİ ENTEGRASYONU (2026-06-04 başladı) — SIRADAKİ ANA İŞ

**Karar:** Tier1 MLKit / Tier2 Gemma / Tier3 Qwen + her modda (Ders/Bas Konuş/Manuel) model seçimi. Varsayılanlar (Mehmet): **Ders=Qwen, Bas Konuş=MLKit, Manuel=MLKit** (hepsi değiştirilebilir).

**✅ YAPILDI (2026-06-04, cihaz testi bekliyor) — ÇEKİRDEK + 2 MOD:**
- `lib/core/engines/translation/llm_translation_engine.dart`: **`LlmHost`** (singleton, tek-LLM-RAM koordinatörü — model değişiminde önceki handle kapatılır, OOM yok; taze session/çeviri) + **`LlmTranslationEngine implements TranslationEngine`** (flutter_gemma sarmalı, `LlmModelDef` Gemma/Qwen, prompt'la çevir, LLM=çok dilli → "dil hazır"=model indirilmiş; `downloadModel(onProgress)` arayüz-dışı UI için, `uninstallModel` ile sil).
- `lib/core/engines/translation/translation_tier.dart`: `TranslationTier {mlkit,gemma,qwen}` (label/hint/size) + `defaultTierFor(mode)` (Ders=Qwen/Bas Konuş=MLKit) + `createTranslationEngine(tier, hfToken)` factory.
- `lib/features/mode_entry/model_tier_selector.dart`: **yeniden kullanılabilir `ModelTierSelector`** — 3 segment + LLM indirme durumu/ilerleme + Gemma HF token; "hazır mı" callback ile parent'ı gate'ler.
- **Ders Modu + Bas Konuş bağlandı:** `LanguageSelectScreen`'e selector eklendi (mod varsayılanıyla), Devam model hazır olunca aktif; tier+token `LectureScreen`/`PushToTalkScreen`'e geçer → Manager `createTranslationEngine(tier)` ile kurulur. analyze temiz, 89/89 test.
- **KALAN (sonraki burst):** (1) **Manuel Çeviri** (main.dart) selector — ayrı yapı, henüz bağlanmadı. (2) Seçim **kalıcılığı** (prefs/Drift — şimdilik her mod açılışında varsayılana döner). (3) Cihaz testi: Ders=Qwen default (cihazda var ama xnnpack_cache silindi→ilk yükleme yavaş), Bas Konuş=MLKit, tier değiştir + Gemma indir (HF token [[ref-hf-token]]).
- **Engeller:** Gemma cihazdan silinmişti (yer) → selector'dan token'la re-download. Qwen cihazda. flutter_onnxruntime/dart_sentencepiece_tokenizer paketleri yalnız NLLB içindi — NLLB elendiğine göre ileride pubspec'ten çıkarılabilir (şimdilik duruyor, NLLB kodu deney).

**⚠️ İNDİRME ENGELİ — HF Xet CDN (2026-06-04, cihaz):** In-app indirme cihazda **`HandshakeException: Connection terminated during handshake`** verdi. Kök neden: Xenova repo'su `huggingface.co/resolve` → **302 `cas-bridge.xethub.hf.co`** (HF'in yeni **Xet** CDN'i); dart:io HttpClient bu host'la TLS handshake yapamıyor (curl PC'de sorunsuz; Vosk eski **klasik LFS CDN** `cdn-lfs` olduğu için dart:io'yla inmişti). **De-risk geçici çözümü:** modeller PC'de curl ile indirilip `adb push /data/local/tmp` → `run-as com.mobstudios.hermes cp files/nllb/` ile kopyalandı (in-app indirme bypass; hedef `/data/user/0/com.mobstudios.hermes/files/nllb`). **PRODÜKSİYON FIX'İ (NLLB de-risk geçerse):** in-app indiriciyi Xet-uyumlu yap — `cronet_http` (Android native stack, flutter_gemma'nın Qwen'i bu yüzden indirebiliyor) veya Xet olmayan ONNX mirror bul. Şu an `NllbModelManager` dart:io http (Xet'te patlar).

### 🤖 LLM ÇEVİRİ KIYAS: Qwen vs Gemma (2026-06-03) — ✅ KARAR: TIER-3 = QWEN

LLM test ekranı **Qwen ↔ Gemma yan yana kıyas**a dönüştürüldü (`llm_translate_test_screen.dart`): tek girdi, her model kendi "Çevir" butonuyla **sırayla** (asla ikisi aynı anda RAM'de değil → OOM yok, model translate sonrası `close()`), kart altında **⚡ üretim (prompt→sonuç) + yükleme süreleri** ayrı ölçülür, hatalar kırmızı görünür. Model seçici + HF token kutusu (yalnız gated model indirmesi için). Modeller: **Qwen2.5-1.5B q8** (1.57GB, `.task`, Apache-2.0, non-gated) ve **Gemma3-1B-IT q4** (555MB, `.task`, gated → HF token).

**Cihaz testi sonucu — ✅ KARAR (Mehmet, birebir):**
> "qwen kesinlikle daha iyi ve sadece 3.2sn daha yavaş ki bu şimdilik kabul edilebilir bence neyse bugünlük bu kadar yeterli."

**Sonuç:** **Tier-3 LLM = Qwen2.5-1.5B.** Kalitede net üstün, Gemma3-1B'den ~3.2sn yavaş ama kabul edilebilir. **Gemma'ya geçiş iptal** (önceki oturum planı). Bonus: Qwen Apache-2.0 = sıfır lisans/dağıtım sürtünmesi; Gemma "Gemma Terms of Use" (gated + dağıtımda ToU/Prohibited-Use bildirim yükümlülüğü + kişisel token app'e gömülemez → production'da self-host şart). Qwen bu yükten de muaf.

**Denenmiş ama elenen:** Gemma-4-E2B (`.litertlm`, 2.59GB) Mehmet istedi → SD860'a fazla ağır (E2B ~3-4GB RAM, OOM riski, SD860 NPU build'i yok, CPU yavaş) uyarısı verildi → Mehmet "vazgeçtim kendi bildiğin sistemi kullan" → Gemma3-1B'ye dönüldü. (Yanlış guess'lenen Gemma3-1B URL'i `q4_ekv1280` repoda yoktu = "model not found" 404; doğrusu `multi-prefill-seq_q4_ekv2048.task`, WebFetch ile doğrulandı.)

**Açık (sonraki):** 3-katman mimari hâlâ geçerli (Tier1 MLKit / Tier2 orta-NMT araştır / Tier3 = Qwen). `TranslationEngine` swappable selector + Qwen'i gerçek pipeline'a bağlama. Anlık çeviride hız (Qwen ~Xsn) yeterli mi yoksa sadece ders post-process mi — entegrasyonda netleşir.

### 🌐 ÇEVİRİ MOTORU ZAYIF + DERS MODU streaming/ilk-kelime (2026-06-01) — SIRADAKİ BÜYÜK İŞLER

Vosk STT cihazda geçti ("transkript gayet yeterli") → STT tamam. Mehmet 3 yeni iş bildirdi.

**Kullanıcı geri bildirimi (birebir):**
> "çeviri motorlarına el atmanın zamanı geldi. transkript gayet yeterli şekilde çıkarılıyor ama çeviri motoru çok zayıf kalıyor hatta transkript %100 doğrulukta oluşturulsa bile çeviri istenen doğrulukta çeviri gerçekleştiremiyor. ayrıca ders modunda da yine chunk mantığı ile canlı şekilde transkript oluştrulmalı konuşmacının susmasını beklememeli yine ayrıca ders modu konuşmacı konuşmasına başladıkltan sonraki ilk kelimesinin ilk yarısına yetişemiyor ve bu yüzden kelimenin tamamını yanlış anlıyor ama konuşmanın devamında genel olarak sorun oluşmuyor."

**Ayrıştırma — 3 iş:**
1. **ÇEVİRİ ZAYIF (öncelik). → 3 KATMAN kararı + LLM spike KODU HAZIR (2026-06-01).** MLKit yetersiz; mantık yürüten LLM kelime kaymalarını toparlar.
   - **`flutter_gemma: ^0.13.6` eklendi, BUILD ✅** (Android config sorunsuz). **APK 656MB'a çıktı** (MediaPipe native lib'leri — debug için kabul; prod'da app bundle + ayrı model indirme).
   - **MODEL GATING bulgusu:** litert-community Gemma3-1B **gated** (anon HTTP 401, HF token gerek). **Qwen2.5-1.5B-Instruct non-gated** (HTTP 200, token'sız iner, çok dilli instruct). → Spike Qwen ile (token derdi yok). Gemma istenirse ücretsiz HF token + lisans onayıyla sonra.
   - **`LlmTranslateTestScreen`** (`lib/features/llm_translate_test/`, AppBar `Icons.psychology`): Qwen2.5-1.5B q8 (~1.57GB) indir (ilerleme) → TR metin gir → `ModelType.qwen` + `getActiveModel(maxTokens:512, CPU)` + `createSession`+`Message.text(prompt)`+`getResponse` → çeviri + **SÜRE (sn)** göster. De-risk: SD860'te kalite+hız ölç. analyze temiz, build+install ✅ (cihaz testi bekliyor).
   - **CİHAZ TESTİ BEKLİYOR:** Qwen indir → birkaç TR→EN çeviri → kalite MLKit'ten iyi mi + hız (sn) kabul edilebilir mi (anlık için mi sadece ders post-process için mi). Sonuca göre 3-katman entegrasyonu.
   - **3-KATMAN mimarisi (Mehmet kararı):** Tier1 MLKit (var) / Tier2 orta NMT (aday: argos_translator_offline=NLLB/Argos, opus-mt — sonra) / Tier3 LLM (Qwen/flutter_gemma). Üçü app'te, test sonrası ele. `TranslationEngine` swappable. **SIRADAKİ (LLM spike sonrası):** orta NMT motoru + 3 motoru seçtiren bir `TranslationEngine` selector/UI + SessionQuality bağlama.
2. **DERS MODU CHUNK'LI CANLI TRANSKRİPT.** "Konuşmacının susmasını beklememeli, chunk mantığıyla canlı." **✅ YAPILDI (2026-06-01, cihaz testi bekliyor):** `StreamingAudioInput implements AudioInput` (`lib/core/audio/streaming_audio_input.dart`) — `StreamingMicAudioInput`'u sarar, `finals`'ı (~5sn segment commit, susmayı beklemez) `AudioUtteranceEvent` olarak Manager'a yayar. Ders Modu `SingleMicAudioInput` → `StreamingAudioInput`. **NOT:** kelime-kelime partial gösterimi YOK (Manager interface bitmiş utterance taşır); ~5sn chunk = "susmayı bekleme" karşılandı. Gerçek word-by-word canlı için ileride Vosk native `SpeechService` yolu (VoskTestScreen'de çalıştı; ayrı/büyük iş, Manager pipeline'ı bypass eder + Whisper fallback'i yok).
3. **DERS MODU İLK KELİME KIRPILMASI.** Konuşmacı başlayınca ilk kelimenin ilk yarısı kaçıyor → o kelime yanlış, gerisi sorunsuz. KÖK NEDEN: VAD pre-speech padding yetersiz (vad paketi `preSpeechPadFrames` varsayılan 1 = ~96ms). **✅ FIX (2026-06-01, cihaz testi bekliyor):** `SileroVadController`'a `preSpeechPadFrames` param (varsayılan **3** ≈ ~288ms pre-roll) + `startListening`'e iletildi. Yetmezse 4-5'e çıkar.

**MEHMET KARARLARI (2026-06-01, AskUserQuestion + mesaj):**
- **Öncelik = ilk-kelime kırpılması** (en hızlı) → ✅ yapıldı (preSpeechPadFrames=3).
- **Çeviri = 3 KATMAN** (birebir): "ml kit en düşük seviye ise ve llm en yüksek seviye ise arada kalan bir çeviri motoru olmalı mesela ml kit'den daha gelişmiş motoru ama llm olmayan bir çevirmen. bu 3 tip çeviriciyide app'de bulunduralım ileride hangisini atıp hangisini tutacağımıza test sonuçlarına göre karar veririz." → 3 `TranslationEngine` impl: (1) MLKit (mevcut, en düşük), (2) **ORTA SEVİYE** (MLKit'ten iyi, LLM değil — aday araştır: opus-mt/Argos/NLLB-distilled on-device? veya online hafif API?), (3) LLM (flutter_gemma, en yüksek). Üçü de app'te dursun, test sonrası ele. SessionQuality/seçim ile bağla.
- **STT görünürlüğü (Mehmet mesajı, birebir):** "fallback testini gerçekleştirmem mümkün değil çünkü çaışan modeli hiç bir mod göstermiyor." → **✅ FIX:** `HybridSttEngine.activeBackend` (`ValueNotifier<String>`, her transcribeFile sonrası "Vosk · tr" / "Whisper · tiny|small"). Ders Modu üst barına STT rozeti eklendi (`_sttBadge`, yeşil=Vosk, turuncu=Whisper). Bas Konuş'a da eklenebilir (sonra). → Mehmet artık fallback'i Ders Modu'nda kaynak dili değiştirerek doğrulayabilir.

**Sıradaki (bu burst sonrası):** çeviri 3-katman mimarisi (önce orta-seviye motor adayı araştır + LLM flutter_gemma fizibilite spike) + Ders Modu chunk'lı canlı transkript (#2, StreamingMicAudioInput entegrasyonu).

### 🔤 Vosk Türkçe ASR de-risk + Model Yönetimi UX (2026-06-01) — ✅ DE-RISK GEÇTİ + YENİ STRATEJİK YÖNLER

**CİHAZ TESTİ SONUCU — ✅ DE-RISK BAŞARILI (Mehmet, birebir):**
> "test başarılı kalite çok daha iyi hala minik pürüzler var ama bu pürüzleri gidermenin en harika yolu bence çeviride llm çeviri opsiyonu sunmak çünkü kelimeler tam birleşmeyebiliyor ancak anlam hala orada kalıyor mantık yürütemeyen düz bir çeviri motoru bunları kaçıracaktır ama llm tabanlı bir çeviri buradaki yazım noktalama ve kelime kaymalarını tespit edebilecektir. tabi bunu nasıl sunacağımız şimdilik net değil. localde çalışması şart o bir kesin ancak anlık çeviride kullanır mıyız emin değilim sistemi aşırı yavaşlatacak olursa kullanamayız ama transkript kayıt edileceği için özellikle ders modunda çok daha işlevsel olacaktır ayrıca vosk apache 2.0 kullanıyor ve gayet de yetenekli diğer diller için de sadece whisper kullanmaktansa yine her dilin kendi vosk modelini kullanmalıyız."

**İndirme hızı sorunu çözüldü:** alphacephei.com ~30 KB/s throttle (35MB ≈ 20 dk) → **HuggingFace aynası `rhasspy/vosk-models` ~8 MB/s** (`VoskModelManager.modelUrl` değiştirildi). Cihazda hızlı indi.

**YENİ STRATEJİK YÖNLER (Mehmet, bu testten):**
1. **VOSK = ANA STT, HER DİL KENDİ VOSK MODELİYLE.** "Sadece Whisper kullanmaktansa yine her dilin kendi vosk modelini kullanmalıyız." Vosk Apache-2.0 (lisans dostu) + Türkçede Whisper'dan belirgin iyi. → Vosk'u `SttEngine` Strategy implementasyonu yap (`VoskSttEngine`, çok dilli, dil başına model). **AÇIK KARAR (Mehmet'e soruldu):** Whisper tamamen kalksın mı yoksa iyi Vosk modeli olmayan diller için fallback mı? + ilk dil seti?
2. **LLM TABANLI ÇEVİRİ OPSİYONU (yeni, kalite için).** Vosk'un "minik pürüzleri" (kelime birleşme/kayma, noktalama) düz MLKit çevirisinde anlamı bozabilir; mantık yürüten LLM bunları toparlar. **Şartlar:** localde çalışmalı (kesin); anlık çeviride kullanım belirsiz (yavaşlatırsa hayır); **özellikle Ders Modu'nda transkript kayıtlı olduğu için post-process olarak çok işlevsel.** "Nasıl sunacağımız şimdilik net değil." → Strategy Pattern `TranslationEngine` zaten swappable; `flutter_gemma` (TranslateGemma/Gemma/Qwen) adayı. **Faz: tasarım/araştırma sonra; şimdi DEĞİL.**

**MEHMET KARARLARI (2026-06-01, AskUserQuestion):**
- **STT mimarisi = Vosk + Whisper fallback.** Her dil için Vosk modeli; iyi Vosk modeli olmayan diller Whisper'a düşer. SttEngine bir router olur (dil→Vosk varsa Vosk, yoksa Whisper).
- **LLM çeviri = SONRA.** Önce çok-dilli Vosk STT'yi oturt + cihazda doğrula; LLM çeviriyi ayrı turda (Ders Modu post-process önceliği).

**UYGULAMA — Burst 1 ✅ CİHAZ TESTİ GEÇTİ (2026-06-01, Mehmet birebir: "hepsi indirilip silinebiliyor sorun yok").** Dil-başına Vosk model yönetimi. `lib/core/models/vosk_models.dart` (`VoskModelInfo` + `VoskModels.byLang` registry: en/tr/es/fr/de/it, HF aynası URL'leri doğrulandı — İngilizce klasör `en` ama model `en-us`). `VoskModelManager` artık dil-parametreli (`VoskModelManager(info)` / `.forLang(code)`). `managed_model.dart` tek `_VoskTrModel` → dil başına `_VoskLanguageModel` (Ayarlar'da 6 Vosk dili görünür, indir/sil/ilerleme). VoskTestScreen TR'ye sabit kaldı (de-risk). analyze temiz.
**UYGULAMA — Burst 2 ✅ KOD (2026-06-01, cihaz testi bekliyor):** Vosk asıl STT + router pipeline'a bağlandı.
- `lib/core/engines/stt/vosk_stt_engine.dart` — `VoskSttEngine implements SttEngine`. Dil başına model bellekte tek tutulur (dil değişince eski dispose); `transcribeFile` WAV'ın 44-byte header'ını atlar, ham PCM16'yı 8000'lik chunk'larla `acceptWaveformBytes` → `getFinalResult` → JSON'dan `text` ayıkla → `reset`. `canHandle(lang)` = VoskModels.supports + inmiş. `setSpeedMode`/`initialize` no-op (small tek model, tembel yükleme).
- `lib/core/engines/stt/hybrid_stt_engine.dart` — `HybridSttEngine implements SttEngine` ROUTER: dil Vosk'ta var+inmişse Vosk, değilse (veya Vosk patlarsa try/catch) Whisper fallback. **`initialize()` TEMBEL** (eager Whisper init ETMEZ → Vosk işi yapacakken Whisper small ~466MB inmesin; her iki motor transcribeFile'da lazy-init). `setSpeedMode` Whisper'a iletir.
- Gerçek mod ekranlarına bağlandı: `lecture_screen`, `push_to_talk_screen`, `session_test_screen` artık `HybridSttEngine()`. Manuel ekran (main.dart, m4a kaydı — Vosk ham PCM ister) Whisper'da BIRAKILDI. Throwaway test ekranları (push_to_talk_test, streaming_test) da Whisper'da.
- analyze temiz, 89/89 test.
- **✅ CİHAZ TESTİ GEÇTİ (2026-06-01, Mehmet):** "transkript gayet yeterli şekilde çıkarılıyor" — Vosk STT modlarda çalışıyor, doğruluk yeterli. **→ STT KATMANI TAMAM.** Yeni sorunlar çeviri + Ders Modu streaming/ilk-kelime (↓ ayrı Polish notu).

**Önceki not (de-risk hazırlık — KOD durumu, hâlâ geçerli):**


Önceki oturumun "İLK İŞ" pivotu (Türkçe için ayrı offline ASR) ele alındı.

**Yapılanlar (bu oturum):**
- **`vosk_flutter` → `vosk_flutter_2` 1.0.5**: orijinal paket `permission_handler ^10` istiyordu (bizde `^11`, çakışma). Fork `vosk_flutter_2` `permission_handler ^11` uyumlu → eklendi. Pubspec'e `http: ^1.1.0` da eklendi (indirme ilerlemesi için).
- **Android build fix'leri:** (1) vosk minSdk 30 istiyor → `build.gradle.kts` `minSdk = maxOf(flutter.minSdkVersion, 30)` (geçici, Android 11+; vosk benimsenmezse geri al — eski cihaz desteği). (2) vosk_flutter_2 eski AGP'ye göre yazılmış, `namespace` yok → AGP 8 build patlıyordu; proje `build.gradle.kts`'e reflection ile namespace enjekte eden hedefli subprojects bloğu + alphacephei maven repo eklendi.
- **`VoskTestScreen`** (`lib/features/vosk_test/`): SADECE Türkçe (Whisper/çeviri yok), `vosk-model-small-tr-0.3` (~35MB) ağdan, canlı partial (mor italik) + birikmiş final cümleler → Whisper'a kıyas için saf ölçüm. Manuel Çeviri AppBar'ında `Icons.translate` ile erişilir.
- **Model indirme UX (Mehmet isteği, aşağıda birebir):** Vosk modeli OTOMATİK inmiyor → önce "Türkçe model gerekli (~35MB)" uyarı ekranı + İndir butonu + **gerçek yüzde ilerleme çubuğu** (`VoskModelManager` ModelLoader'ı bayt-sayan custom http client ile sarıp progress alıyor).
- **Ayarlar ekranı** (`lib/features/settings/`, ana ekran AppBar dişli ikonu): tüm modeller tek listede (Whisper tiny=yerleşik/silinemez, Whisper small, Vosk Türkçe, 6 ML Kit çeviri dili) — durum (hazır/inmemiş) + indir (ilerlemeli, destekleyende) + sil (onaylı). `ManagedModel` soyutlaması + `ModelRegistry` (`lib/core/models/`).
- analyze temiz, build ✅, cihaza kuruldu.

**Mehmet karar teyidi (birebir):**
> "anladım sadece türkçeye özel ayrı motor kullanacağız"

→ **HİBRİT kesinleşti:** İngilizce vb. = Whisper (small + hız tuning), Türkçe = Vosk. Whisper KALDIRILMIYOR.

**Model yönetimi UX isteği (birebir):**
> "ayrıca bu model indirmelerini takip etmek şuanda çok zor her bir model indirmesi için ör: vosk testi tıklandığında model indirmesi gerekmektedir tarzında bir uyarı versin ve indir butonuna basıldığında bir ilerleme gösterilsin sadece dümdüz beklemeyelim. ana menüye ayarlar butonu ekle orada da yüklü bütün modeller görünsün istenirse istenen model(ler) silinebilsin veya indirilebilsin."

→ Uygulandı (yukarıda). **NOT:** ML Kit çeviri dili indirmeleri ilerleme yüzdesi VEREMİYOR (ML Kit API hook sunmuyor) → belirsiz spinner. Whisper small de şimdilik ilerlemesiz (whisper_ggml downloadModel hook'u yok); gerekirse ileride streamed-download'a çevrilebilir (Vosk'taki gibi).

**CİHAZ TESTİ BEKLİYOR (sıradaki):** (1) Ayarlar → Vosk Türkçe indir (ilerleme çubuğu çalışıyor mu, %), (2) Vosk Test ekranı → Türkçe konuş → Whisper'ın saçmaladığı cümlelerde doğruluğu KIYASLA (de-risk asıl kararı — Vosk TR Whisper'dan iyi mi?). İyiyse hibrit kalıcı; değilse sherpa-onnx. (3) Ayarlar sil/indir akışı + diğer modeller. Sonuç birebir buraya.

### ⚠️ Step 7 burst-3 — Ders Modu KALİTE SORUNLARI (2026-05-31 akşam, 2. oturum) — UI ERTELENDİ, kaliteye odak

Ders Modu ekranı (`LectureScreen`) çalışıyor (UI yeterli), AMA Mehmet 3 büyük sorun bildirdi → **UI bir süre ertelenir, motor/pipeline kalitesine geçilir.**

**Kullanıcı geri bildirimi (birebir):**
> "ui şimdilik gayet yeterli gözüküyor ancak çok büyük bir kaç sorunumuz var o yüzden ui'ı bir süreliğine erteleyebiliriz. en büyük problem çeviri de ders modunun motoru yavaş olabilir ancak doğruluğu yüksek olmak zorunda hem transkript aşamasında hem de çevirisini aşamasında yetersiz. ayrıca ayrı bir sorun ise sistem transkripti yazmak için konuşmacının susmasını bekliyor bu kabul edilemez daha akışkan bir transkript olmalı belirli chunk'lar ile hareket etmeli"

**Ayrıştırma + durum:**
1. **Transkript doğruluğu (Whisper) yetersiz** → **KÖK NEDEN BULUNDU + FIX:** Manager `SessionQuality.full`'u Whisper modeline HİÇ bağlamıyordu → Ders Modu yanlışlıkla **tiny** kullanıyordu. Fix: `Manager.start()` artık `stt.setSpeedMode(full→accurate=small / fast→fast=tiny)`. 16/16 test. **Cihaz testi ✅ Mehmet: "çok daha doğru çalışıyor"** — small belirgin daha doğru. **ANCAK çok yavaş** ("beklediğimden çok daha fazla yavaş"). → **HIZ TUNING uygulandı (small'ı koruyarak):** `WhisperCppEngine` artık `WhisperController`'ı bypass edip `Whisper`'ı doğrudan `noFallback:true` (yavaş temperature-fallback re-decode kapalı, en büyük yavaşlık kaynağı) + `threads`=tüm CPU (SD860=8; controller sabit 6 veriyordu) ile çağırıyor. Model/doğruluk değişmez. **Cihaz testi ✅ Mehmet: "fark edilir şekilde daha hızlı"** (doğruluk korundu). Transkript doğruluk+hız sorunu ÇÖZÜLDÜ. İleride daha da gerekirse seçenekler: (a) **base** modeli (small'dan 3-4x hızlı, tiny'den doğru — doğruluk/hız ortası), (b) **sherpa-onnx** streaming-ASR'ye geçiş (hem hızlı hem GERÇEK streaming → sorun #3'ü de çözer; büyük entegrasyon, Strategy Pattern hazır). (medium ~1.5GB çok büyük.)
2. **Çeviri doğruluğu (MLKit) yetersiz** → AÇIK KARAR: Ders Modu accuracy önceliği → MLKit yetersiz. Online AI (Gemini/LLM) mu, offline mı? Mehmet'in eski kararı "fast=MLKit, full=AI ileride" idi; şimdi Ders (full) için öne çekiliyor. **Karar Mehmet'e soruldu.**
3. **Streaming/chunked transkript** → "sistem konuşmacının susmasını bekliyor, kabul edilemez, akışkan/chunk'lı olmalı." → **ÇÖZÜLDÜ (burst-1a, cihaz ✅).** `StreamingMicAudioInput` (record.startStream + VAD audioStream) + `StreamingTestScreen`: konuşurken her ~2sn canlı partial + her ~5sn (susmasa bile) commit + sessizlikte tail commit. Mehmet "her şey yolunda". Karar: partial canlı (kaynak-only), çeviri final'de. **Sıradaki: burst-1b Manager+LectureScreen entegrasyonu.**

4. **TÜRKÇE TANIMA ZAYIF + CRASH → ASR PİVOTU (yeni, KRİTİK, sıradaki büyük iş)** → Mehmet (birebir): *"sorun türkçe algılamasında, ingilizce altyazıları neredeyse mükemmel tanıyor ama türkçede aşırı saçmalıyor"* ve sonra: *"çeviri zaten yavaştı artık durma noktasına geldi hatta app crash yaşadı çözüm model boyutunu büyütmek değil daha akıllı bir modele geçmek mesela kendi minik llm'mimizi çalıştırabilir miyiz... veya başka hangi alternatiflerimiz var?"*
   - **CRASH teşhisi:** streaming test iki Whisper modelini (tiny+small) AYNI ANDA RAM'e yüklüyordu → **OOM crash.** Düzeltildi: streaming_test artık **tek motor** (small+fallback). Ders Modu/Manager zaten tek motor — etkilenmedi.
   - **KRİTİK AYRIM (Mehmet'e açıklandı):** Türkçe "saçmalama" = **TRANSKRİPT (STT/Whisper)** sorunu. **LLM çeviri yapar, transkript YAPMAZ** → LLM TR tanımayı düzeltmez. Önce ASR katmanı çözülmeli.
   - **Araştırma:** on-device mini LLM çeviri **mümkün** (`flutter_gemma` + TranslateGemma/Gemma 270M/Qwen3 0.6B) ama CPU-yavaş + çeviriyi düzeltir, transkripti değil. Online Gemini (multimodal) TR tanı+çeviriyi birlikte çözer (online+ücret). SeamlessM4T Faz 2.
   - **KARAR (Mehmet):** **Türkçe TANIMA'yı düzelt → alternatif offline ASR (sherpa-onnx / Vosk TR).** Önerim: **önce Vosk** (kesin Türkçe modeli `vosk-model-small-tr-0.3`, hafif, native streaming → TR+hız+streaming birlikte). sherpa escalation. Akıllı çeviri (LLM/Gemini) ayrı/sonraki yükseltme.
   - **DURUM:** `flutter pub add vosk_flutter` ağ hatası verdi (pub.dev'e ulaşılamadı, internet/proxy) — eklenemedi, pubspec temiz. **Sıradaki oturum: vosk_flutter ekle (internet düzelince) → Türkçe model → VoskTestScreen de-risk (6r-d gibi, Whisper/çeviri yok, sadece TR Vosk doğruluğu+streaming cihazda).** Whisper transkript (EN için) + small+noFallback+threads hız tuning'i çalışıyor, kalıyor.

### 🎨 Step 9 — TASARIM BAŞTAN SONA YENİLENECEK (2026-05-31 akşam, 2. oturum — Mehmet)

**Kullanıcı geri bildirimi (birebir):**
> "polish aşamasına not düş tasarım baştan sona tekrardan yenilenecek ve elden geçirilecek şuanki hali gayet iyi ama demode duruyor daha farklı renkler kullanmalıyız ayrıca daha şık bir temaya ihtiyacımız var meseala liquid glass gibi"

**Aksiyon (Step 9):** Tüm UI teması baştan elden geçirilecek — mevcut dark #0F0F0F + #7C6FE0 "demode". Daha farklı renk paleti + **"liquid glass" benzeri şık tema** (glassmorphism / blur / saydam katmanlar). Şu anki ekranlar (home, dil seçim, Bas Konuş, test ekranları) fonksiyonel referans; görsel dil komple değişecek. Bu büyük bir polish işi, Step 9'da ayrı ele alınır.

### Step 7 burst-2 — Bas Konuş gerçek ekranı cihaz testi (2026-05-31 akşam, 2. oturum) — ✅ GEÇTİ

İki yarı + üst 180° + şeffaf/sadece-basılınca butonlar + DM-box chat (çeviri karşı tarafa) + gerçek Manager (pushToTalk) + seçilen diller + TTS.

**Kullanıcı geri bildirimi (birebir):**
> "her şey harika ancak en üstteki bas konuş label ı çok yer kaplıyor ve çok çirkin onu oradan kaldır ve daha minimal şekilde ortaya yerleştir ama sadece tr<->en yazsın geri çıkma butonu da yine aynı şekilde orta kısıma taşınsın ve ekran tam ekran olsun üstte bildirim çubuğu görünmesin."

**Aksiyon (uygulandı):** AppBar kaldırıldı; ekran ortasına minimal kontrol pill'i (geri X + "src ↔ tgt" + meşgul spinner); tam ekran immersive (`SystemUiMode.immersiveSticky`, dispose'da geri alınır).

**2. tur geri bildirimi (birebir):**
> "her şey harika ama bottom overflowed hatası alıyorum ayrıca ekranın üstü tam olarak yerine oturmuyor bildirim çubuğu görünmüyor ama onun yeri hala sabit duruyor."

**2. tur düzeltme (uygulandı):** (1) **bottom overflow** → yarıdaki chat `SingleChildScrollView(reverse, NeverScrollable)` ile klip'lendi (mesaj birikince taşmıyor, en yeni ayraca yakın). (2) **üstte sabit boş yer** → `Scaffold(primary: false)` (AppBar yokken bile eklenen status-bar üst boşluğu kaldırıldı) + `resizeToAvoidBottomInset: false`. **DOĞRULANACAK** — oturum kapanırken deploy edildi, Mehmet sonraki açılışta teyit edecek.

### Step 7 burst-1 — Navigasyon (HomeScreen + dil seçim) cihaz testi (2026-05-31 akşam, 2. oturum) — ✅ GEÇTİ

Ana ekran mod kartları (Ders/Bas Konuş/Manuel + Voice Translator disabled) → `LanguageSelectScreen` → placeholder mod ekranı. Manuel → mevcut `TranslationTestScreen` (dev test butonları orada).

**Kullanıcı geri bildirimi (birebir):**
> "her şey çalışıyor ancak ileride daha fazla dil seçeneği de eklemek istiyorum"

**Ayrıştırma:** ✅ navigasyon geçti. 📋 **Dil listesi genişletilecek** — şu an `LanguageSelectScreen._languages` 5 dil (tr/en/es/de/fr). İleride genişletilmeli; ideali MLKit desteklenen + indirilmiş modellere bağlamak (`TranslationEngine.downloadLanguage`/`isLanguageReady` zaten var) → dil yönetimi Step 8/9.

### Step 6r-e — Bas Konuş PushToTalkAudioInput cihaz smoke (2026-05-31 akşam, 2. oturum) — ✅ ÇEKİRDEK GEÇTİ

`PushToTalkAudioInput` (record.startStream ham PCM) + çift yönlü Manager kodlandı (79/79 test), minimal iki-yarı PTT test ekranı eklendi (üst yarı 180° dönük=secondary, alt yarı=primary), cihaza kuruldu.

**Kullanıcı geri bildirimi (birebir):**
> "2 TEST de başarılı ama hala portre modu kilitlenmemiş landscape moda geçiş oluyor telefon çeviriliriken, türkçe transkript çok saçmalıyor hata oranı çok fazla. ayrıca ui test amaçlı olarak bu şekilde değil mi çünkü olması gereken mod seçiminden sonra dil tercihinin yapılması ardından tercüme ekranına geçildiğinde sadece butonların yer alması gerekiyor ayrıca transkript konuşan kişinin tarafında gözüküyor iyi hoş ama çevirisinin de karşı tarafa yazdırılması gerekiyor ayrıca bas konuş butonları daha şefaf olmalı hatta sadece basıldıklarında görünmeliler butonların altında ise dm box şeklinde her iki tarafa özel 180 dönmüş chat olmalı"

**Ayrıştırma (analiz):**
- ✅ **6r-e ÇEKİRDEĞİ GEÇTİ** — "2 test de başarılı": iki yarı da yakalıyor, çift yönlü routing + record.startStream PCM + press/release gating cihazda çalışıyor.
- ✅ **Portre kilidi yoktu** → `main.dart`'a `SystemChrome.setPreferredOrientations([portraitUp])` eklendi (uygulama geneli). **Cihazda doğrulandı (Mehmet: "portre kilidi aktif").**
- ⚠️ **Türkçe transkript çok saçmalıyor, hata oranı yüksek** → Whisper TR doğruluğu zayıf. AÇIK SORUN. Olası nedenler: tiny model (quality=fast), 16kHz WAV dönüşümü, mic mesafe/gürültü. Step 9'da araştır: (a) `full` (small) modelle TR farkı ölç, (b) WAV/sample doğrula, (c) VAD'li akışla (Ders Modu) karşılaştır. **Not: bu PTT'ye özel değil, genel STT kalite konusu.**
- 📋 **Step 7 Bas Konuş GERÇEK UI gereksinimleri (test ekranı throwaway, Mehmet teyit etti "ui test amaçlı"):**
  1. Akış: **mod seçimi → dil tercihi → tercüme ekranı** (tercüme ekranında sadece butonlar).
  2. **Çeviri karşı tarafa yazdırılmalı** — şu an test ekranı sadece konuşanın tarafında transkript gösteriyor; gerçekte konuşanın transkripti kendi tarafında + ÇEVİRİSİ karşı yarıda görünmeli (Manager zaten çift yönlü çeviriyor, UI bağlama eksik).
  3. **Bas-konuş butonları daha şeffaf, hatta sadece basılıyken görünür** (tasarım "görünmez bas-konuş alanı" ile uyumlu).
  4. **Butonların altında her iki tarafa özel "DM box" şeklinde chat** — üst tarafınki 180° dönük (karşı taraf okur).

### Step 6r-h — Manager tam pipeline entegrasyon cihaz testi (2026-05-31 akşam, 2. oturum) — ✅ GEÇTİ

`SessionTestScreen` (`lib/features/session_test/`, throwaway harness) gerçek `ConversationSessionManager` + gerçek motorlar (WhisperCpp + MLKit + NativeTTS + Drift + PushToTalkAudioInput) ile uçtan uca: iki yarı bas-konuş → transkript → çeviri → TTS sesli → mesaj balonu + DB → Bitir'de başlık. Çift yönlü doğrulandı.

**Kullanıcı geri bildirimi (birebir):**
> "her şey harika ama düzeltilmesi ve eklenmesi gereken özellikler var: transkript canlı olarak belirmeli konuşma bittikten sonra bir süre bekleyip öyle bir anda çıkmamalı, translate motorları yeterince zeki değil gerekirse yapay zeka temelli transalate motoruna geçilmeli ama yinede düşününce bu mod fast olarak kalmalı ileride yavaş ama doğru olan modu gerçekleştirdiğimizde kullanmalıyız."

**Ayrıştırma (analiz):**
- ✅ **6r-h GEÇTİ → Step 6 refactor TAMAM.** Tam pipeline gerçek motorlarla cihazda çalışıyor (transkript + çift yönlü çeviri + TTS sesli + DB + başlık).
- 📋 **Canlı (live) transkript** — şu an transkript konuşma bitip Whisper işledikten SONRA tek seferde çıkıyor (bekleme + ani belirme). İstenen: konuşurken canlı belirmeli. Tasarımda Ders Modu zaten "live subtitle, latency <3sn" hedefliyor. Streaming/partial Whisper sonucu gerektirir → **Step 7 (Ders Modu live subtitle) / Step 9 polish.** Bas Konuş'ta da release sonrası gecikme bu yüzden.
- 📌 **Çeviri kalitesi kararı (Mehmet net):** MLKit çevirisi "yeterince zeki değil". AMA **fast mod MLKit ile fast kalacak** — değiştirme. İleride **"yavaş ama doğru" (full/quality) mod** yapıldığında **yapay zeka temelli translate motoru** (Gemini/LLM) o moda bağlanacak. Strategy Pattern (`TranslationEngine` swappable) zaten hazır. → **Faz 2 / full-mod altyapısı.** SessionQuality.full bu AI translate ile anlam kazanacak.

### Step 6r-f + 6r-g — TitleGenerator + DB Test başlık cihaz smoke (2026-05-31 akşam, 2. oturum) — ✅ GEÇTİ

DB Test ekranında oturum aç → mesaj ekle → kapat → timestamp başlık üretilip kartta + listede göründü.

**Kullanıcı geri bildirimi (birebir):**
> "test başarılı devam"

Açık konu yok. (Gemini gerçek başlık üretimi Step 9'da; şu an timestamp fallback çalışıyor.)

### 📌 Devreye alınmayı bekleyen altyapı — Language ID (2026-05-30 not düşüldü)

`lib/core/engines/language_id/` + `google_mlkit_language_id` paketi mevcut + 8 unit test geçiyor ama Step 6 refactor sonrası **bilinçli olarak `ConversationSessionManager`'dan koparıldı** (3 mod mimarisinde donanım/UI kim konuşuyor'u belirliyor, dil tespitine ana akışta ihtiyaç yok). Step 9 polish'inde iki olası kullanım için altyapı hazır bekliyor:

1. **Yanlış dil uyarısı** — User TR seçti ama mic'e ES söyledi. Whisper TR olarak forced transkript yapıp saçma çıkacak. LangID konuşulan dilin seçilenle uyumsuzluğunu yakalayıp "yanlış dilde konuşuyorsunuz" uyarısı verebilir.
2. **Çok dilli/hibrit ders modu** — Hocanın bir cümleyi İngilizce, bir cümleyi Türkçe söylediği derslerde (Türkiye'deki yabancı dil dersleri sık) baştan tek dil seçmek yanlış olur. Ders Modu için "hibrit ders" toggle açıldığında her transkript için LangID çağrılır, Whisper o dilde forced çalıştırılır.

**Aksiyon:** Step 9'a geldiğinde bu iki kullanım için Settings toggle ve `ConversationSessionManager` tekrar bağlama. Pakette ~3MB APK bloat + her transkript ~50ms latency maliyeti kabul edilebilir (toggle ile opt-in).

### Step 6r-d-faz1 — Dual mic concurrent capture cihaz testi (2026-05-31 akşam) — ❌ BAŞARISIZ → PİVOT

**Bu testin sonucu Voice Translator'ı (Yöntem B) Faz 2'ye erteletti.** Native plugin yazıldı, build edildi, Poco X3 Pro'ya kuruldu (MIUI kurulum iznini reddetti → telefondan "USB ile kurulum" onayı verildi). Ardından kaynak (AudioSource) seçimi test ekranına dropdown olarak eklenip 5 kombinasyon × 2 kulaklık tipi denendi.

**Kullanıcı geri bildirimi (birebir) — ilk MIC/MIC testleri:**
> "kablolu kulaklığı takıp ... Bluetooth kulaklığı öncele switchini kapalı konuma getirip testi başlattığımda sadece mic A'dan yani kablolu kulaklıktan ses alınabiliyor mic B'den yani dahili mic'den ses alınamıyor. altta ise mic A kablolu kulaklık olarak ... mic B dahili mic olarak doğru ... concurrent destek eve(API29+). BT SCO başlatıldı hayır." (switch açık halde de aynı)
> "kablosuz kulaklığı takıp ... switchini açık ... sadece mic B'dan yani dahili mic'den ses alınabiliyor mic A'den yani kablosuz kulaklıkdan ses alınamıyor ... BT SCO başlatıldı evet. ... Mic A(primary): 'Bluetooth SCO (M2102J20SG)'. AYRICA aynı testi bir kaç kez tekrar ettiğimde mic A'dan ses almayı başardım ancak bu seferde dahili mikrofondan ses alınamıyor. testlerden birinde testin yarsınıda bir anda kulaklık mikrofonundan ses almayı kesti ve dahili mikrofondan ses almaya başladı ve daha da ilginci mic A kablosuz kulaklığı temsil etmesine rağmen dahili mikrofon ses aldığında mic'A nın çubuğu hareket ediyordu. ek not: hiç bir kulaklık takılı olmadığında her iki mikrofonunda çubuğu beraber şekilde inip kalıyor"

**Kullanıcı geri bildirimi (birebir) — AudioSource taraması (kablolu VE kablosuz aynı çıktı):**
> "3 MIC / VOICE_RECOGNITION: A ve B'den farklı seviyede sesler geliyordu yani çubuklar ... birbirlerinden mesafeliydiler ama maalesef ses sadece kulaklığın mikrofonuna konuştuğumda tespit yapıyordu. (kablosuzda: A'da hiçbir tespit yok, sadece B/dahili ses alıyor)
> 1 VOICE_COMMUNICATION / VOICE_RECOGNITION: iki bar bağımsız hareket ediyor ama yinede ikiside telefon mikrofonuna bağımlı gibi
> 2 VOICE_COMMUNICATION / MIC: yine bağımsız hareket ediyor iki barda ancak ikiside telefon mikrofonuna bağımlı gibi
> 4 VOICE_COMMUNICATION / CAMCORDER: iki bar bağımsız ... ama ikiside telefon mikrofonuna bağımlı gibi
> 5 VOICE_COMMUNICATION / UNPROCESSED: iki bar bağımsız ... ama ikiside telefon mikrofonuna bağımlı gibi"

**Analiz / Sonuç:**
- **Kök neden:** Poco X3 Pro (MIUI/Android 13) aynı anda **tek fiziksel giriş route'u** servis ediyor. İki `AudioRecord` concurrent açılabiliyor (kanıt: kulaklık yokken iki bar birlikte = ikisi de dahili mic) ama farklı `setPreferredDevice` ile iki ayrı cihazı eş zamanlı besleyemiyor.
  - **Kablolu:** tek route = kulaklık, dahili mic donanımda kesik (B ölü).
  - **BT:** tek route = dahili; SCO capture `AudioRecord`'a tutmuyor (A ölü/flaky, test ortasında route el değiştiriyor).
  - **`VOICE_COMMUNICATION`** her zaman dahili/comms mic'i kapıyor, `setPreferredDevice(SCO)`'yu eziyor → 1/2/4/5'te "ikisi de telefona bağımlı". Bağımsız barlar yanılsama (aynı kaynak, farklı source işleme → farklı seviye).
- **İnternet bulgusu (`CAMCORDER` + `CHANNEL_IN_STEREO`):** gerçek ama farklı sorunu çözer — telefonun **iki dahili mic'ini** L/R kanala ayırır (kulaklık+telefon değil). Konuşmacı ayrımına yaramaz (iki dahili mic ~10cm, ikisi de iki konuşmacıyı duyar → beamforming gerekir).
- **Karar (Mehmet):** Voice Translator → Faz 2. Faz 1 = Ders Modu + Bas Konuş + Manuel. 6r-d kodu **silinmedi** — `HermesDualMicPlugin.kt`, `dual_mic_channel.dart` (artık `DualMicSource` enum + parametrik AudioSource), `dual_mic_test_screen.dart` (dropdown'lu deney harness'ı) negatif bulgu kanıtı + Faz 2 başlangıç noktası olarak duruyor. `main.dart` 🎧 AppBar girişi + AndroidManifest `BLUETOOTH_CONNECT` + `MainActivity` plugin register de kalıyor.
- **Faz 2 için fikir:** turn-based capture (tek aktif route zaten sorunsuz) + çıkış routing (A'nın dili → kulaklık TTS, B'nin dili → hoparlör TTS); veya farklı cihaz/donanımda dual-mic yeniden dene; veya SeamlessM4T.

### Step 1 — TTS cihaz testi (2026-05-17)

**Kullanıcı geri bildirimi (birebir):**
> "6 maddenin her biri doğru şekilde çalışıyor ancak bazı sorunlar var:
> 1-) bahsettiğim indirilmiş olan ve olmayan diller mevcut değil.
> 2-) 'çevrilecek metin (yaz veya konuş)' alanına tıklandığında bottom overflowed by 2.3 pixels uyarısı veriyor.
> 3-) session mantığı implemente edilmemiş.
> 4-) sesler çok robotik ses paketlerini ilerde veya uygun görüyorsan şimdiden değiştirelim."

**Aksiyonlar:**
- 1 → Step 2'de yapıldı ✅
- 2 → Step 2'de Switch tap target ile düzeltildi ✅
- 3 → Step 6'ya planlandı (ConversationSessionManager)
- 4 → **Step 9 polish notu**: Native TTS robotic geliyor. İki yaklaşım: (a) Settings ekranında "Cihaz TTS engine'ini Google TTS yap" yönlendirmesi (Xiaomi cihazlarda varsayılan TTS robotic, Google TTS daha doğal), (b) `setSpeechRate` 0.5 → 0.55 ince ayar. Coqui/neural TTS Faz 2'ye işaretli.

### Step 3 — VAD (Silero v4) cihaz testi (2026-05-17)

**Kullanıcı geri bildirimi (birebir):**
> "1: her şey doğru.
> 2: her şey doğru her cümleyi tespit etti sadece 'iki kahve lütfen'de kısa olması ve benim biraz hızlı söylemem sebebiyle bazen algılayamadı.
> 3: her şey doğru çalıştı.
> 4: 'ee' veya öksürük gibi sesleri ekran yüzüme dönükse veya mikrofon ağzıma yakınsa sözce olarak algılandı, eğer ekran yüzüme dönük değilse veya mikrofon ağzıma yakın değilse hem sözce olarak hem de misfire olarak algılamadı yani direk duymazdan geldi ancak en sevdiğim özelliği yankılı bir koridordaydım ve uzakta birisi telefonla konuşuyordu onun sesini tespit etti ve misfire olarak değerlendirdi.
> 5: sessizlikte hiçbir sayaç artmadı uzakta birisi telefonla konuşuyor olmasına rağmen hiç bir sayaç artmadı."

**Analiz:**
> Mükemmel sonuçlar — özellikle 4. madde Silero VAD'in kalitesini doğruluyor: yakındaki "ee"/öksürük false positive bazen kaçıyor (mikrofon SNR yüksek olunca konuşma sanıyor, beklenen), ama uzaktaki gerçek başka konuşma misfire olarak sınıflandırıldı — yani konuşma tespit edildi ama min frame eşiğini geçemedi → kabul edilmedi. Sessizlikte sayaç artmadı = gürültü kalibrasyonu doğru.
>
> "İki kahve lütfen" kaçırılması bilinen trade-off: `minSpeechFrames=3` varsayılan eşik, hızlı/kısa cümlelerde feed yetmiyor.

**Step 9 polish'de değerlendirilecek aksiyonlar:**
- VAD: `minSpeechFrames: 3 → 2` veya v5 modeline geçiş (kısa "iki kahve lütfen" tipi cümleleri kurtarmak için)
- VAD: Yakın mikrofon false positive'i için ek filter — belki RealSpeechStart event'ini bekleyip SpeechStart'taki erken tetiklemeyi yutma; ya da `positiveSpeechThreshold: 0.5 → 0.55` ile sınırı yukarı çekme
- Cihazda v5 modelini de bundle'a ekle (silero_vad_v5.onnx), Settings'te `SileroVadController(modelVersion: 'v4' | 'v5')` toggle
- **Koruma altına alınmalı**: uzaktaki gerçek başka konuşma → misfire davranışı; bu Konuşma Modu'nda kritik (false trigger önler). Min frame ayarını düşürürken bu davranışı bozmamaya dikkat.

### Step 6r-c — AudioInput strategy smoke testi (2026-05-30)

**Kullanıcı geri bildirimi (birebir):**
> "her şey çalışıyor ancak artık bir mola verme zamanı geldi her şeyi kaydet ve not tut punch board a punchını düş ve toplan"

**Analiz / Aksiyonlar:**
- Manager iç bağımlılığı `VadController` → `AudioInput` taşındı, dışarıdan gözle görülür değişiklik yok (Manager UI'a hâlâ bağlı değil), 4 ekran (Translation/STT, VAD, DB, ana) çalışmaya devam ediyor ✅
- `SingleMicAudioInput` VAD ara state'lerini yutup sadece bitmiş utterance'ı yayınlıyor — Manager'a temiz kontrat
- `AudioUtteranceEvent.source` (primary/secondary) altyapısı hazır; 6r-e/h'de Manager bunu sağ/sol routing için kullanacak (6r-d'de DualMic plugin source ayrımı verir)
- VAD Test ekranı bozulmadı (VadController interface'i hiç değişmedi, ekran zaten doğrudan VadController kullanır)

### Step 6r-b — Schema v2 migration cihaz testi (2026-05-30)

**Kullanıcı geri bildirimi (birebir):**
> "her şey testde istediği gibi çalışıyor devam et"

**Analiz / Aksiyonlar:**
- Drift v1 → v2 migration ilk DB açışında otomatik çalıştı, cihazda doğrulandı ✅
- Eski Step 5 testinden kalan `'fast'` oturumları → `voiceTranslator/fast`, varsa `'full'` → `lecture/full` olarak görüldü (DB Test ekranı bunu kart başlığında göstermeye yarıyor)
- Mesajlar (cascade üzerinden) kaybolmadı, oturum kalıcılığı sağlam
- Yeni oturum açma → `voiceTranslator/fast` default ile düşüyor
- Hot reload bağlantısı bittikten sonra `flutter run` task'i exit etti (bilinen davranış, cheatsheet tuzak #4)

### Step 6r-a — Manager LangID kopartma smoke testi (2026-05-30)

**Kullanıcı geri bildirimi (birebir):**
> "her şey çalışıyor sadece mikrofon butonuna basılıp konuşulmadan geri kapatıldığında çok uzun süre bekliyor(sanki bir sonsuz döngüye giriyor) ayrıca telefon yan çevirilidğinide landscape moduna girmemesi lazım ancak giriyor ve girdiğinde bottom pverflowed by 131 pixels diye hata veriyor. ama bunların hiçbirinin önemi yok diye tahmin ediyorum çünkü UI zaten baştan tasarlanacak ve bir çok şey zaten değişecek."

**Analiz / Aksiyonlar:**
- Refactor smoke ✅ — Translation/STT, VAD, DB Test ekranları çalışıyor, Manager değişikliği başka bir yeri kırmadı
- **Sonsuz döngü (mikrofon basılıp konuşulmadan kapatıldığında):** Manager'a değil eski Translation Test ekranındaki STT akışına ait olma ihtimali yüksek (boş audio'ya Whisper'ın askıda kaldığı bir bug olabilir). Step 7+ UI yeniden yazılırken aynı davranış Manager üzerinden devam ediyorsa orada bir guard (`if samples.length < minMs → skip`) eklenir
- **Landscape orientation lock yok + 131 px overflow:** Mevcut test ekranı portrait kabulüyle yazılmış ama lock yok, döndürülünce overflow veriyor. **Mehmet 2026-05-30 düzeltti:** TÜM Hermes modları portrait zorunlu — Bas Konuş bile (telefon dik tutulur, sadece üst yarının widget içeriği `RotatedBox(quarterTurns: 2)` ile 180° döner). Step 7+ UI'da app-genelinde `SystemChrome.setPreferredOrientations([portraitUp])` ile landscape kilitlenir.
- Mehmet "önemi yok, UI baştan tasarlanacak" dedi — doğru, eski test ekranı Step 7+ ile silinecek. Yine de yukarıdaki iki not Step 7+ planlanırken hatırlanmalı.

### Step 5 — Drift + ConversationRepository cihaz testi (2026-05-17)

**Kullanıcı geri bildirimi (birebir):**
> "bütün testler başarılı!"

Test senaryoları (Mehmet'in cihazda uyguladığı 6 adım):
1. AppBar → storage ikonu → DB Test ekranı açıldı, "(henüz oturum yok)" yazısı görüldü
2. `Oturum Aç` → `#1 tr ↔ en · fast` kartı + yeşil "açık" etiketi + `Oturum #1 açıldı.` status — ✅
3. `Mesaj Ekle` 3× → tr "Merhaba, nasılsın?", en "I am fine, thank you.", tr "İki kahve lütfen." sırasıyla düştü, sayaç 3'e çıktı — ✅
4. `Oturumu Kapat` → yeşil "açık" → gri "kapalı HH:MM:SS", status `Oturum #1 kapatıldı.` — ✅
5. Yeni `Oturum Aç` + mesaj → `#2` üstte, `#1` aşağıda (en yeni önce sıralama) — ✅
6. **Kalıcılık testi**: Recent apps'tan kill → tekrar aç → DB Test ekranında `#1` ve `#2` tüm mesajlarıyla yerinde — ✅

**Analiz / Aksiyonlar:**
- SQLite native lib (`sqlite3_flutter_libs`) Poco X3 Pro Android 13'te sorunsuz yüklendi.
- `getApplicationDocumentsDirectory()` altındaki `hermes.sqlite` dosyası cold-start sonrası persist ediyor.
- `PRAGMA foreign_keys=ON` `beforeOpen` migration cihazda da geçerli (cascade delete unit test'te doğrulandı, prod'da Step 6'da olası senaryolarda gözlenecek).
- `startedAt` desc + id desc tiebreak prod sıralamada doğru çalıştı (aynı saniyede iki oturum açıldı senaryosu).
- **Step 9'a not yok** — geri bildirim "her şey beklendiği gibi", polish gerektiren gözlem yok.
- **Korunmasını istediğimiz davranış**: cold-start kalıcılığı. Step 6 `ConversationSessionManager` yazılırken `AppDatabase` instance lifecycle'ı (singleton mı app-scope DI mı?) dikkat: birden fazla `AppDatabase()` aynı dosyayı locklayabilir → Step 6'da DI ile tek instance şart.

---

### Polish notu kaydetme ilkesi

Her cihaz testi sonrasında kullanıcı geri bildirimi bu bölüme **birebir, parafraze etmeden** eklenir. Format:
```
### Step N — [özellik adı] cihaz testi (YYYY-MM-DD)

**Kullanıcı geri bildirimi (birebir):**
> "...kullanıcının yazdığı her şey..."

**Analiz / Aksiyonlar:**
- Hemen düzeltilecek olanlar
- Step 9'a not edilenler
- Korunmasını istediğimiz davranışlar
```

---

## Süreç Notları

- Her step bitiminde: `flutter analyze` clean → USB cihaz testi → roadmap güncelle → sonraki step
- Tasarım/kararlarda değişiklik gerekirse önce `HERMES_KONUSMA_MODU_TASARIM.md` güncellenir, sonra roadmap'e yansıtılır
- Cihaz testi başarısız olursa step yarıda kalır, fix → re-test döngüsü ile bitirilir
