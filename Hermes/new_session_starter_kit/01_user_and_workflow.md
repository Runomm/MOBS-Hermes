# 01 — Kullanıcı ve Çalışma Akışı

## Mehmet kim?

- **Ad:** Mehmet Onur Boyraz
- **Mail:** mehonuboy@gmail.com
- **Anadil:** Türkçe (genellikle Türkçe yazıyor, Türkçe cevap ver; teknik terimler İngilizce kalabilir)
- **Cihazlar:**
  - **Birincil geliştirme/test cihazı:** Poco X3 Pro (Snapdragon 860, Android 13, USB ID `cd61ba57`)
  - **Demo cihazı:** iPhone 17 Pro Max (iOS build için Mac lazım, **Mac yok** — Codemagic veya üniversite Mac lab opsiyon)
  - **PC:** Windows 11 Pro, RTX 4060
- **Stack:** Flutter (mobile), Python (data/AI projeleri), PowerShell shell
- **Önceki proje:** GEOengine (OSINT fotoğraf konum tahmini). Lab2-6 teslim edildi, terk edildi. Hermes mevcut aktif proje.

## Çalışma stili — Mehmet'in kuralları

Bunlar memory'de feedback olarak kayıtlı ve Mehmet defalarca pekiştirdi:

### Kural 1: Step-by-step, asla atlamadan

Her motor/feature için döngü:

```
1. Tek bir motor/feature için kod yaz
2. flutter analyze → temiz olmalı
3. USB cihaz testi (gerçek Poco X3 Pro üzerinde) → davranışsal doğrula
4. ANCAK BUNDAN SONRA bir sonraki step
```

**Neden:** Token/zaman ekonomisi (rate-limit'lere takılıyor) + mobile'da analyzer yakalayamadığı runtime/permission/asset bug'ları çok yaygın. Her motoru ayrı doğrulamak debug yüzeyini küçültür. Sessionlar arasında bilgisayar kapanması/token bitmesi olduğunda nerede kalındığını net tutmak için "son başarılı cihaz testi" = checkpoint.

**Geçmiş ihlal:** Bir tur ben (önceki Claude) Whisper'ı cihazda test etmeden TTS'e geçtim — Mehmet revert ettirdi. Bu tür shortcut'lar yapma.

### Kural 2: Cihaz testi geri bildirimini BİREBİR sakla

Kullanıcı cihaz testinden döndüğünde yazdığı her şey `HERMES_ROADMAP.md` → "Polish Notları (Step 9 için biriken cihaz testi gözlemleri)" bölümüne **kelime kelime, parafraze etmeden** eklenir. Yanına senin analizin de aynen yazılır.

**Format:**
```markdown
### Step N — [özellik] cihaz testi (YYYY-MM-DD)

**Kullanıcı geri bildirimi (birebir):**
> "...kullanıcının yazdığı her şey..."

**Analiz / Aksiyonlar:**
- Hemen düzeltilecek olanlar
- Step 9'a not edilenler
- Korunmasını istediğimiz davranışlar
```

**Neden:** Step 9'a (polish) ay sonra gelindiğinde "neyi düzeltecektim?" sorusunun cevabı orada olsun. Mehmet sözlü test sonuçlarını sonradan yazıya dökmek zorunda kalmasın.

### Kural 3: Her step bitiminde roadmap güncelle

`HERMES_ROADMAP.md`'de:
- Step `[ ]` → `[x]` (tikle), yanına 1 cümle özet + cihaz testi sonucu
- "Aktif İş" bölümünü bir sonraki step'e taşı
- "Son güncelleme" tarihini değiştir
- Cihaz testinden gelen geri bildirim varsa "Polish Notları"na ekle

### Kural 4: Tasarım kararlarını sorma, dokümanda var

Konuşma Modu (Hermes'in killer feature'ı) için detaylı tasarım `HERMES_KONUSMA_MODU_TASARIM.md`'de. **Açık sorular (a-f) onaylandı**, kararlar yazılı:

- (a) VAD: `vad_silero` (✓ Step 3'te yapıldı)
- (b) TTS çakışma: mod-bazlı (Hızlı Mod → kes, Tam Mod → kuyrukta bekle)
- (c) Aynı dil üst üste: sessizce devam, iki ayrı mesaj
- (d) Filler: conservative default + aggressive toggle + master kapatma
- (e) Background: Faz 1'de `wakelock_plus`, Foreground Service Faz 2
- (f) Dil tespit belirsizlik: confidence < 0.6 → sessizce drop

Yeni karar gerekirse Mehmet'e sor, dokümandaki kararı **değiştirmeden** uyma.

### Kural 5: Yorum yazma alışkanlığı

- Mehmet Türkçe konuşuyor, dosyalardaki yorumlar Türkçe olabilir
- Kod yorumu yazma kuralı: WHAT yazma (kod zaten gösterir), WHY yaz (gizli kısıt, sürpriz davranış, bug workaround). Mehmet bunu sevdi.
- Mehmet "step-by-step" çalışıyor, yani küçük scope'lar tercih ediyor — büyük refactor'lar yapma

## Mehmet'in iletişim stili

- Türkçe yazıyor, gündelik dilde
- "abi", "kardeşim" gibi samimi seslenme kullanabilir
- Hızlı bağlamla çalışıyor — uzun açıklamalar yerine eylem + sonuç tercih ediyor
- Cihazda test edip dönüyor, sonuçları liste halinde yazıyor (örn: "1: doğru, 2: kısalık nedeniyle kaçırdı")
- Bir kez "hiçbir şey anlaşılmıyor" dedi → soruları teknik jargon ağır olunca somut sahne + tradeoff'la açıklamak gerek

## Sözlük

- **Faz 1**: Ders + Konuşma modu çekirdek özellikler. Halen sürüyor (4/9 step).
- **Faz 2**: Belge Modu, Coqui TTS, foreground service, Gemini cleanup.
- **Faz 3**: SeamlessM4T, GeoEngine entegrasyonu.
- **Konuşma Modu**: Iki kişi sürekli iki dilde konuşup VAD ile chat'e dökülen mod. Mehmet'in "Google Translate'ten ayıran özellik" dediği şey.
- **Ders Modu / Tam Mod**: Tek yönlü, sürekli, Whisper small (varsa), doğruluk öncelik.
- **Konuşma Modu / Hızlı Mod / Turist Modu**: Çift yönlü, Whisper tiny, hız öncelik. (Mod isimleri subject to change.)
- **Polish Notları**: `HERMES_ROADMAP.md` içindeki bölüm, Step 9'a kadar biriken cihaz testi gözlemleri.

---

**Sıradaki: `02_project_state.md`** — şu an nerede kaldık, sıradaki tek satırlık iş.
