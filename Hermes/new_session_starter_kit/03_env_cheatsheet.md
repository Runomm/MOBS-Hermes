# 03 — Ortam Cheatsheet

PowerShell tuzakları, runtime quirks, komut şablonları. **Komut çalıştırmadan önce oku.**

## Sistem

- **OS:** Windows 11 Pro
- **Shell:** PowerShell 5.1 (default `powershell.exe`). Bash de mevcut ama PowerShell tercih edilir.
- **Birincil dizin:** `C:\Projects\FonksiyonelProgramlama\` (Mehmet bunu "primary working directory" olarak belirledi)
- **Hermes proje kökü:** `C:\Projects\FonksiyonelProgramlama\Hermes\`
- **Flutter app dizini:** `C:\Projects\FonksiyonelProgramlama\Hermes\hermes\`

## Cihaz

| Cihaz | Tip | USB ID | Android sürüm | Notlar |
|---|---|---|---|---|
| Poco X3 Pro | Mobile (birincil) | `cd61ba57` (M2102J20SG) | 13 (API 33) | USB debugging açık, daimi bağlı |
| Windows masaüstü | Desktop | `windows` | — | Test için kullanılmaz, Flutter web kabul ettiği için listede |
| Chrome | Web | `chrome` | — | Test için kullanılmaz |
| Edge | Web | `edge` | — | Test için kullanılmaz |

Build her zaman: `flutter run -d cd61ba57`.

## Komut şablonları (kopyala-yapıştır)

### Analyze

```powershell
Push-Location "C:\Projects\FonksiyonelProgramlama\Hermes\hermes"; flutter analyze; $exit = $LASTEXITCODE; Pop-Location; Write-Output "EXIT_CODE=$exit"
```

### Test (saf Dart/Flutter testleri)

```powershell
Push-Location "C:\Projects\FonksiyonelProgramlama\Hermes\hermes"; flutter test; $exit = $LASTEXITCODE; Pop-Location; Write-Output "EXIT_CODE=$exit"
```

### Cihaz listesi

```powershell
Push-Location "C:\Projects\FonksiyonelProgramlama\Hermes\hermes"; flutter devices; Pop-Location
```

### Build + cihaza yükle (background'da, log dosyasına yaz)

```powershell
Push-Location "C:\Projects\FonksiyonelProgramlama\Hermes\hermes"; flutter run -d cd61ba57 *> "C:\Projects\FonksiyonelProgramlama\Hermes\hermes\.flutter_run.log"; Pop-Location
```

**`run_in_background=true` kullan** — `flutter run` interactive, kapanmaz. Notification gelince logu kontrol et.

### Log inceleme (UTF-16 farkındalığı)

```powershell
$log = "C:\Projects\FonksiyonelProgramlama\Hermes\hermes\.flutter_run.log"
# Build markers
(Get-Content $log | Select-String -Pattern "Built|Installing|Lost connection|Syncing").Line | Select-Object -Last 5
# Hata aramaları
(Get-Content $log | Select-String -Pattern "EXCEPTION CAUGHT|Failed assertion|Error").Count
```

**Önemli:** `*>` redirect, dosyayı **UTF-16 LE** olarak yazar. Ham `grep` çalışmaz, mutlaka `Get-Content | Select-String` kullan.

### Pub get

```powershell
Push-Location "C:\Projects\FonksiyonelProgramlama\Hermes\hermes"; flutter pub get; $exit = $LASTEXITCODE; Pop-Location; Write-Output "EXIT_CODE=$exit"
```

## ⚠️ Bilinen ortam tuzakları

### 1. PowerShell `*>` redirect log dosyasını kilitleyebilir

**Belirti:** Yeni `flutter run` anında patlar; `out-file : The process cannot access the file '...flutter_run.log' because it is being used by another process.`

**Sebep:** Önceki `flutter run` process'i exit etse bile (debug bağlantısı `Lost connection to device` olsa bile), arka planda dart/flutter_tester process'leri kalabilir ve log handle'ını tutuyor.

**Workaround:**
```powershell
Get-Process | Where-Object { $_.ProcessName -match "flutter_tester|dart" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item "C:\Projects\FonksiyonelProgramlama\Hermes\hermes\.flutter_run.log" -Force -ErrorAction SilentlyContinue
```

Sonra `flutter run` tekrar çalıştırılabilir. Bunu **her yeni run öncesi** uygulamak güvenli.

### 2. PowerShell `2>&1` native command'ları kırar

**Belirti:** `flutter run 2>&1 | Tee-Object` → `NativeCommandError` + exit code yanlış olur.

**Sebep:** PowerShell 5.1 native command'ın stderr'ini ErrorRecord olarak wrap eder, `$?` false olur, kanal patlar.

**Workaround:** `2>&1 | Tee-Object` yerine **`*>` kullan** (tüm stream'leri tek dosyaya redirect).

### 3. Log dosyası UTF-16 LE encoded

Ham `grep`, `head`, `cat` PowerShell'in UTF-16 default'unu okuyamaz. Detayı yukarıda "Log inceleme" bölümünde.

### 4. Flutter assertion errors log'da uçucu

`flutter run`'ın "Lost connection to device" çıktıktan sonra, app cihazda çalışmaya devam edebilir AMA artık hot reload yok, yeni assertion'lar log'a düşmez. Bu yüzden test yaparken log'u önceden incele.

## Build ortamı sabitleri

- **NDK:** `29.0.13113456` (pinli, `android/app/build.gradle.kts` içinde). `whisper_ggml` istedi. Hâlâ r29-beta1, stable çıkınca upgrade.
- **compileSdk:** Flutter default (`flutter.compileSdkVersion`, şu an 34+).
- **Gradle:** Flutter'ın getirdiği sürüm, manuel müdahale yok.
- **Android namespace:** `com.mobstudios.hermes`
- **Min SDK:** Flutter default

## Asset dosyaları

`hermes/assets/models/`:
- `ggml-tiny.bin` (Whisper tiny modeli, ~75MB)
- `silero_vad_legacy.onnx` (Silero VAD v4 modeli, ~1.8MB)

`hermes/pubspec.yaml`'da `assets/models/` declare edilmiş; bütün model dosyaları otomatik dahil.

## AndroidManifest izinleri

`hermes/android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

Eğer Drift için ek izin gerekirse buraya eklenir (genelde yok — sqlite3_flutter_libs kendine yetiyor).

## Dart dil tuzakları

### `String.replaceAll` backreference desteklemez

```dart
// ❌ YANLIŞ — '$1' literal kalır
text.replaceAll(RegExp(r'\s+([,\.])'), r'$1');

// ✅ DOĞRU — manuel callback
text.replaceAllMapped(RegExp(r'\s+([,\.])'), (m) => m.group(1)!);
```

### `caseSensitive: false` Türkçe `İ ↔ i` eşlemez

```dart
// ❌ YANLIŞ — "İşte" yakalanmaz
RegExp(r'\bişte\b', caseSensitive: false);

// ✅ DOĞRU — açık character class
RegExp(r'(?<![\p{L}])[İi]şte(?![\p{L}])', unicode: true);
```

### `\b` word boundary Unicode-aware değil

```dart
// ❌ YANLIŞ — "şey" sınırlarında çalışmaz (Türkçe ş ASCII word char değil)
RegExp(r'\bşey\b');

// ✅ DOĞRU — Unicode harf sınıfı lookaround
RegExp(r'(?<![\p{L}])şey(?![\p{L}])', unicode: true);
```

## Kullanışlı komutlar (tek bakışta)

```powershell
# Process kill (log lock çözümü)
Get-Process | Where-Object { $_.ProcessName -match "flutter_tester|dart" } | Stop-Process -Force

# Hermes proje boyutunu gör
Get-ChildItem "C:\Projects\FonksiyonelProgramlama\Hermes\hermes\lib" -Recurse -Filter *.dart | Measure-Object -Property Length -Sum

# Test cache temizle
Push-Location "C:\Projects\FonksiyonelProgramlama\Hermes\hermes"; flutter clean; Pop-Location
```

---

**Sıradaki: `04_doc_index.md`** — proje dokümanlarına nereden bakacağın.
