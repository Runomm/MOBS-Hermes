# Hermes

[Türkçe](README.tr.md)

Hermes is a translation app for Android and iOS, written in Flutter. Speech recognition and translation run on the phone, so the main features keep working without an internet connection.

It started as a university project. I had two situations in mind: exchange students trying to follow lectures in a language they don't speak well, and travellers who don't always have mobile data. In both cases you can't count on a connection, so Hermes was built offline-first from the beginning.

The interface is in Turkish.

## What it does

The home screen has four modes:

- **Konferans (Conference):** one-way, continuous listening. The speaker's words show up as translated live subtitles, and the translation can also be read into your headphones. Sessions are saved as text only, no audio. Later you can re-translate the whole transcript with NLLB and get a summary.
- **SmallTalk:** a two-way conversation between two people, either hands-free (the app works out who is speaking) or push-to-talk. In push-to-talk the screen is split in two and the top half is upside down, so the person across from you can read it.
- **Manuel Çeviri (Manual):** type, translate, listen.
- **Görsel Çeviri (Visual):** take or pick a photo. Text blocks are detected, and tapping one shows its translation on top of it.

Conference and SmallTalk sessions are stored in a local SQLite database and can be opened or deleted from the archive. Summaries are generated on the device (Gemma 3 1B), or with Gemini 2.5 Flash if you enter your own API key in Settings.

## How it works

Each engine (speech-to-text, translation, text-to-speech, OCR, language ID) sits behind a small interface, so they can be swapped without touching the screens. Currently:

| Job | Engine | Notes |
|---|---|---|
| Live speech-to-text | Vosk (small models) | 35–50 MB per language, streaming. Android only. |
| Speech-to-text | Whisper (whisper.cpp) | `tiny` is bundled, `small` (~466 MB) is optional. Used for live modes on iOS. |
| Fast translation | Google ML Kit | ~30 MB per language |
| Better translation | NLLB-200 600M (int8, ONNX Runtime) | ~1.3 GB, fully offline |
| Summary | Gemma 3 1B on device, or Gemini 2.5 Flash | Gemini needs your own key |
| Text-to-speech | The phone's built-in voices | via `flutter_tts` |
| OCR | ML Kit Text Recognition | Latin script |
| Storage | Drift (SQLite) | |

Only small models are bundled with the app (Whisper tiny and Silero VAD). The rest are downloaded from the Settings screen: NLLB and the Gemma file come from this repo's [Releases](https://github.com/Runomm/MOBS-Hermes/releases), Vosk models from the `rhasspy/vosk-models` mirror on Hugging Face, and ML Kit models through Google Play Services.

Languages: the live modes support Turkish, English, Spanish, German, French, Italian, Dutch, Russian and Chinese. Manual translation offers 10 languages with ML Kit and 35 with NLLB.

## Building

You need Flutter 3.41 (Dart 3.11) and the Android SDK. The NDK version is pinned to 29.0.13113456 in `android/app/build.gradle.kts`. The minimum Android version is 11 (API 30), because the Vosk plugin requires it.

```bash
cd Hermes/hermes
flutter pub get
flutter run
```

The generated Drift code (`app_database.g.dart`) is committed. If you change the database schema, regenerate it with `dart run build_runner build`.

Tests run on the host with fake engines, so no models are needed:

```bash
flutter test
```

### iOS

I don't have a Mac, so iOS builds run on Codemagic. The `ios-unsigned` workflow in `codemagic.yaml` produces an unsigned `.ipa`, which I sign and install with Sideloadly using a free Apple ID. That signature expires after 7 days.

### Keys and tokens

The Gemini API key (and the optional Hugging Face token) are entered in the app and stored on the device. They're never in the repo. After cloning, turn on the pre-commit hook, which blocks commits that contain tokens or keys:

```bash
git config core.hooksPath .githooks
```

## Status and known issues

This is a student project, not a finished product.

- Most of the testing was done on a single Android phone (Poco X3 Pro, Android 13). The iOS build has seen much less testing.
- The Vosk plugin doesn't support iOS, so live modes there use Whisper. That's slower, and there are no partial results while someone is talking. ML Kit translation is also turned off on iOS, and NLLB is used instead.
- On Android, ML Kit models are downloaded by Google Play Services. On some phones that download can stall. NLLB doesn't depend on it.
- NLLB and the on-device summary model use a lot of memory. The app warns about this on low-RAM phones, but things can still be slow there.
- The developer menu (🧪) with test screens is still part of the app.

## Repository layout

```
Hermes/
  hermes/                 Flutter app
    lib/core/             engines, audio input, sessions, database, services
    lib/features/         screens (conference, smalltalk, manual and visual translation, settings, dev tests)
    test/
  *.md                    design notes, roadmap and course lab reports (Turkish)
codemagic.yaml            unsigned iOS build
.githooks/pre-commit      secret check before each commit
```

## Model licenses

The model weights aren't part of the source code, and each model keeps its own license. In particular, NLLB-200 is CC BY-NC 4.0 (non-commercial use only), and Gemma is covered by Google's Gemma Terms of Use.
