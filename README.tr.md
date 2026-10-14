# Hermes

[English](README.md)

Hermes, Flutter ile yazılmış bir Android/iOS çeviri uygulaması. Konuşma tanıma ve çeviri telefonun üzerinde çalışıyor, bu yüzden temel özellikler internet olmadan da kullanılabiliyor.

Proje bir üniversite dersi için başladı. Aklımda iki durum vardı: yabancı dilde anlatılan dersi takip etmeye çalışan değişim öğrencileri ve yurt dışında her zaman mobil verisi olmayan turistler. İkisinde de internete güvenemeyeceğin için Hermes'i en baştan çevrimdışı çalışacak şekilde kurdum.

Arayüz Türkçe.

## Neler yapıyor

Ana ekranda dört mod var:

- **Konferans:** Tek yönlü, sürekli dinleme. Konuşmacının söyledikleri çevrilip canlı altyazı olarak ekrana akıyor; istersen çeviri kulaklığa sesli de okunuyor. Oturumlar yalnızca metin olarak kaydediliyor, ses tutulmuyor. Sonradan tüm transkripti NLLB ile yeniden çevirip özetini çıkarabiliyorsun.
- **SmallTalk:** İki kişi arasında karşılıklı çeviri. Eller serbest (kimin konuştuğunu uygulama ayırt ediyor) ya da bas-konuş olarak kullanılabiliyor. Bas-konuşta ekran ikiye bölünüyor; üst yarı, karşındaki kişi rahat okusun diye ters duruyor.
- **Manuel Çeviri:** Yaz, çevir, dinle.
- **Görsel Çeviri:** Fotoğraf çek ya da galeriden seç. Metin blokları bulunuyor; bir bloğa dokununca çevirisi bloğun üstünde çıkıyor.

Konferans ve SmallTalk oturumları cihazdaki SQLite veritabanında duruyor; arşivden açılıp silinebiliyor. Özet ya cihazda (Gemma 3 1B) ya da Ayarlar'a kendi API anahtarını girersen Gemini 2.5 Flash ile çıkarılıyor.

## Nasıl çalışıyor

Her motor (konuşma tanıma, çeviri, seslendirme, OCR, dil tespiti) küçük bir arayüzün arkasında duruyor; böylece ekranlara dokunmadan değiştirilebiliyor. Şu an kullanılanlar:

| İş | Motor | Not |
|---|---|---|
| Canlı konuşma tanıma | Vosk (small modeller) | Dil başına 35–50 MB, akış halinde. Sadece Android. |
| Konuşma tanıma | Whisper (whisper.cpp) | `tiny` uygulamayla geliyor, `small` (~466 MB) isteğe bağlı. iOS'te canlı modlar bunu kullanıyor. |
| Hızlı çeviri | Google ML Kit | Dil başına ~30 MB |
| Daha iyi çeviri | NLLB-200 600M (int8, ONNX Runtime) | ~1.3 GB, tamamen çevrimdışı |
| Özet | Cihazda Gemma 3 1B ya da Gemini 2.5 Flash | Gemini için kendi anahtarın gerekiyor |
| Seslendirme | Telefonun kendi sesleri | `flutter_tts` ile |
| OCR | ML Kit Text Recognition | Latin alfabesi |
| Depolama | Drift (SQLite) | |

Uygulamayla yalnızca küçük modeller geliyor (Whisper tiny ve Silero VAD); geri kalanı Ayarlar ekranından indiriliyor. NLLB ve Gemma dosyası bu reponun [Releases](https://github.com/Runomm/MOBS-Hermes/releases) sayfasından, Vosk modelleri Hugging Face'teki `rhasspy/vosk-models` aynasından, ML Kit modelleri de Google Play Hizmetleri üzerinden iniyor.

Diller: canlı modlar Türkçe, İngilizce, İspanyolca, Almanca, Fransızca, İtalyanca, Felemenkçe, Rusça ve Çince destekliyor. Manuel çeviride ML Kit ile 10, NLLB ile 35 dil var.

## Derleme

Flutter 3.41 (Dart 3.11) ve Android SDK gerekiyor. NDK sürümü `android/app/build.gradle.kts` içinde 29.0.13113456 olarak sabitlendi. Vosk eklentisi yüzünden en düşük Android sürümü 11 (API 30).

```bash
cd Hermes/hermes
flutter pub get
flutter run
```

Drift'in ürettiği kod (`app_database.g.dart`) repoda var. Veritabanı şemasını değiştirirsen `dart run build_runner build` ile yeniden üret.

Testler sahte motorlarla bilgisayarda çalışıyor, model indirmek gerekmiyor:

```bash
flutter test
```

### iOS

Mac'im olmadığı için iOS derlemesi Codemagic'te yapılıyor. `codemagic.yaml` içindeki `ios-unsigned` iş akışı imzasız bir `.ipa` üretiyor; ben bunu Sideloadly ve ücretsiz bir Apple ID ile imzalayıp telefona kuruyorum. Bu imza 7 gün geçerli.

### Anahtarlar ve token'lar

Gemini API anahtarı (ve isteğe bağlı Hugging Face token'ı) uygulamanın içinden giriliyor ve cihazda saklanıyor; repoda hiçbir zaman bulunmuyor. Klonladıktan sonra pre-commit kancasını aç; token ya da anahtar içeren commit'leri engelliyor:

```bash
git config core.hooksPath .githooks
```

## Durum ve bilinen sorunlar

Bu bir öğrenci projesi, bitmiş bir ürün değil.

- Testlerin çoğu tek bir Android telefonda yapıldı (Poco X3 Pro, Android 13). iOS sürümü çok daha az denendi.
- Vosk eklentisi iOS'i desteklemiyor, bu yüzden iOS'te canlı modlar Whisper kullanıyor. Bu daha yavaş ve konuşma sürerken ara sonuç göstermiyor. ML Kit çevirisi de iOS'te kapalı; onun yerine NLLB kullanılıyor.
- Android'de ML Kit modellerini Google Play Hizmetleri indiriyor. Bazı telefonlarda bu indirme takılabiliyor. NLLB'nin böyle bir bağımlılığı yok.
- NLLB ve cihazdaki özet modeli çok bellek kullanıyor. Uygulama düşük RAM'li telefonlarda uyarı veriyor ama yine de yavaş çalışabilir.
- Test ekranlarını içeren geliştirici menüsü (🧪) hâlâ uygulamada duruyor.

## Klasör yapısı

```
Hermes/
  hermes/                 Flutter uygulaması
    lib/core/             motorlar, ses girişi, oturumlar, veritabanı, servisler
    lib/features/         ekranlar (konferans, smalltalk, manuel ve görsel çeviri, ayarlar, geliştirici testleri)
    test/
  *.md                    tasarım notları, yol haritası ve ders lab raporları
codemagic.yaml            imzasız iOS derlemesi
.githooks/pre-commit      her commit öncesi gizli bilgi kontrolü
```

## Model lisansları

Model ağırlıkları kaynak kodun parçası değil ve her model kendi lisansıyla geliyor. Özellikle NLLB-200 CC BY-NC 4.0 (yalnızca ticari olmayan kullanım), Gemma ise Google'ın Gemma Kullanım Koşulları kapsamında.
