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
    // 2026-06-19: yeni diller (ML Kit/NLLB ile uyumlu).
    'nl': 'nl-NL',
    'ru': 'ru-RU',
    'zh': 'zh-CN',
    'ar': 'ar-SA',
    'pt': 'pt-PT',
    'pl': 'pl-PL',
    'uk': 'uk-UA',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'el': 'el-GR',
    'sv': 'sv-SE',
    'da': 'da-DK',
    'no': 'nb-NO',
    'fi': 'fi-FI',
    'cs': 'cs-CZ',
    'ro': 'ro-RO',
    'hu': 'hu-HU',
    'bg': 'bg-BG',
    'hr': 'hr-HR',
    'sk': 'sk-SK',
    'id': 'id-ID',
    'vi': 'vi-VN',
    'th': 'th-TH',
    'hi': 'hi-IN',
    'fa': 'fa-IR',
    'he': 'he-IL',
    'sr': 'sr-RS',
    'az': 'az-AZ',
    'ka': 'ka-GE',
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
    // Biraz daha sakin/elegant tempo (Mehmet 2026-06-19).
    await _tts.setSpeechRate(0.46); // 0.0–1.0
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
        // Daha elegant/doğal ses: bu dil için varsa enhanced/premium/neural
        // sesi seç (yoksa sistem varsayılanı kalır). Mehmet 2026-06-19.
        await _applyBestVoice(tag);
        _currentLanguageTag = tag;
      } else {
        throw Exception('TTS bu dil için ses paketi bulamadı: $tag');
      }
    }

    await _tts.speak(text);
  }

  /// Verilen locale için cihazda yüklü **en kaliteli** sesi seçer (enhanced/
  /// premium/neural/network/wavenet adı geçenler öncelikli; tam bölge eşleşmesi
  /// bonus). Bulamazsa sistem varsayılanına dokunmaz. Best-effort (hata yutulur).
  Future<void> _applyBestVoice(String tag) async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;
      final prefix = tag.split(RegExp('[-_]')).first.toLowerCase();
      final tagLower = tag.toLowerCase();
      Map<String, String>? best;
      var bestScore = -1;
      for (final v in voices) {
        if (v is! Map) continue;
        final locale = (v['locale'] ?? '').toString().toLowerCase();
        if (!locale.startsWith(prefix)) continue;
        final name = (v['name'] ?? '').toString().toLowerCase();
        var score = 0;
        if (locale == tagLower) score += 2;
        if (name.contains('enhanced') ||
            name.contains('premium') ||
            name.contains('neural') ||
            name.contains('network') ||
            name.contains('wavenet')) {
          score += 5;
        }
        if (score > bestScore) {
          bestScore = score;
          best = {
            'name': (v['name'] ?? '').toString(),
            'locale': (v['locale'] ?? '').toString(),
          };
        }
      }
      if (best != null && bestScore > 0 && best['name']!.isNotEmpty) {
        await _tts.setVoice(best);
      }
    } catch (_) {
      // Ses seçimi best-effort — başarısızsa varsayılan ses kullanılır.
    }
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
