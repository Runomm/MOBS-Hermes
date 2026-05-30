import 'package:flutter_tts/flutter_tts.dart';

import 'tts_engine.dart';

/// Native OS TTS motoru.
/// - iOS: AVSpeechSynthesizer
/// - Android: TextToSpeech API
///
/// Her iki platformda da işletim sistemi ses paketleriyle çalışır; ses paketi
/// indirildiyse tamamen offline'dır.
class NativeOsTtsEngine implements TtsEngine {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _isSpeaking = false;
  String? _currentLanguageTag;

  /// BCP-47 kısa kodları → flutter_tts'in beklediği bölgesel etiketler.
  /// (Kısa kod da kabul edilir ama bölgesel etiket daha güvenilir ses paketi
  /// seçimi sağlar.)
  static const Map<String, String> _localeMap = {
    'tr': 'tr-TR',
    'en': 'en-US',
    'es': 'es-ES',
    'fr': 'fr-FR',
    'de': 'de-DE',
    'it': 'it-IT',
  };

  @override
  String get engineName => 'Native OS TTS';

  @override
  bool get isOfflineCapable => true;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Sentez tamamlanana kadar speak() bekler — sıralı çağrılar için kritik.
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.5); // 0.0–1.0; 0.5 doğal hız
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setCancelHandler(() => _isSpeaking = false);
    _tts.setErrorHandler((msg) => _isSpeaking = false);

    _initialized = true;
  }

  @override
  Future<void> speak(String text, String languageCode) async {
    if (!_initialized) await initialize();
    if (text.trim().isEmpty) return;

    final tag = _localeMap[languageCode] ?? languageCode;
    if (tag != _currentLanguageTag) {
      final available = await _tts.isLanguageAvailable(tag);
      if (available == true) {
        await _tts.setLanguage(tag);
        _currentLanguageTag = tag;
      } else {
        throw Exception('TTS bu dil için ses paketi bulamadı: $tag');
      }
    }

    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
    _initialized = false;
  }
}
