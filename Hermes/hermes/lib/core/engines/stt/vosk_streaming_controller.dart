import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import '../../models/vosk_model_manager.dart';
import '../../models/vosk_models.dart';

/// **Streaming (kelime kelime canlı) transkripsiyon** soyutlaması.
///
/// Dosya-bazlı [SttEngine.transcribeFile]'dan farklı olarak metni **anında akar**:
/// [partials] hızla değişen canlı tahmin, [finals] doğal duraklamada kesinleşen
/// cümle. Konferans Modu'nun "Gemini hızı" isteğinin (2026-06-05, #1) cevabı.
///
/// Native (Vosk `SpeechService`) implementasyonu [VoskStreamingController];
/// testte sahte stream'lerle implement edilir.
abstract class StreamingTranscriber {
  /// Hızla değişen canlı kısmi tahmin (gösterim için, çeviri tetiklemez).
  Stream<String> get partials;

  /// Doğal duraklamada kesinleşen cümle (çeviri/DB tetikler).
  Stream<String> get finals;

  /// [language] modelini yükle + kaydı hazırla (mic izni dahil). Dinleme
  /// başlamaz — sadece hazırlık (ısınma ekranı için).
  Future<void> load(String language);

  /// Mikrofonu aç, akışı başlat.
  Future<void> start();

  /// Mikrofonu kapat, akışı durdur.
  Future<void> stop();

  /// Kaynakları serbest bırak.
  Future<void> dispose();
}

/// [StreamingTranscriber]'ın Vosk `SpeechService` implementasyonu (native).
///
/// `VoskTestScreen` de-risk'inde (2026-06-01) cihazda kanıtlandı:
/// `createModel → createRecognizer → initSpeechService → onPartial/onResult`.
/// Burada o akış ekrandan ayrıştırılıp yeniden kullanılabilir hâle getirildi.
///
/// Native plugin'e bağımlı olduğu için unit test edilmez (bkz. [VoskSttEngine]);
/// orkestratör ([ConferenceStreamingSession]) sahte transcriber ile test edilir.
class VoskStreamingController implements StreamingTranscriber {
  static const int _sampleRate = 16000;

  /// **Global SpeechService tekil nöbeti.** Vosk `initSpeechService` native
  /// tarafta tek örneğe izin verir; ikinci çağrı `SpeechService instance already
  /// exist` ile patlar. Konferans ısınmasından sistem geri tuşuyla çıkıp tekrar
  /// girince (ekran `dispose`'u fire-and-forget olduğundan) eski SpeechService
  /// henüz yaşıyordu → çökme (2026-06-09). Çözüm: yeni `load()` daima önceki
  /// aktif örneği **tam dispose** edip sonra init eder (ekran nasıl kapanırsa
  /// kapansın güvenli). `dispose()` idempotent (memoized future).
  static VoskStreamingController? _active;

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speech;
  Future<void>? _disposeFuture;

  final StreamController<String> _partials =
      StreamController<String>.broadcast();
  final StreamController<String> _finals = StreamController<String>.broadcast();

  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _resultSub;
  bool _listening = false;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Stream<String> get finals => _finals.stream;

  /// Bu dil için Vosk modeli cihazda inmiş mi? (warmup öncesi kontrol)
  static Future<bool> isModelReady(String language) async {
    if (!VoskModels.supports(language)) return false;
    return VoskModelManager.forLang(language).isDownloaded();
  }

  /// [modelPathOverride] verilirse [language]/VoskModels'a bakılmaz, doğrudan o
  /// dizinden model yüklenir (Vosk EN de-risk ekranı adb-push'lu modelleri test
  /// eder).
  @override
  Future<void> load(String language, {String? modelPathOverride}) async {
    // Re-entry nöbeti: global SpeechService tekil → önceki aktif örneği TAM
    // dispose et (memoized future, init bitmeden "already exist" patlamasın).
    final prev = _active;
    if (prev != null && !identical(prev, this)) {
      await prev.dispose();
    }

    // Vosk SpeechService Android'de RECORD_AUDIO ister.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      throw StateError('Mikrofon izni reddedildi.');
    }

    final String path;
    if (modelPathOverride != null) {
      path = modelPathOverride;
    } else {
      if (!VoskModels.supports(language)) {
        throw StateError('Vosk bu dili desteklemiyor: $language');
      }
      final manager = VoskModelManager.forLang(language);
      if (!await manager.isDownloaded()) {
        throw StateError('Vosk $language modeli inmemiş.');
      }
      path = await manager.modelPath();
    }
    _model = await _vosk.createModel(path);
    _recognizer = await _vosk.createRecognizer(
      model: _model!,
      sampleRate: _sampleRate,
    );
    _speech = await _vosk.initSpeechService(_recognizer!);
    _active = this;

    _partialSub = _speech!.onPartial().listen((p) {
      if (_partials.isClosed) return;
      _partials.add(_extract(p));
    });
    _resultSub = _speech!.onResult().listen((r) {
      if (_finals.isClosed) return;
      final text = _extract(r).trim();
      if (text.isNotEmpty) _finals.add(text);
    });
  }

  @override
  Future<void> start() async {
    if (_speech == null || _listening) return;
    await _speech!.start();
    _listening = true;
  }

  @override
  Future<void> stop() async {
    if (_speech == null || !_listening) return;
    await _speech!.stop();
    _listening = false;
  }

  /// Idempotent: ilk çağrı disposal'ı başlatır, sonraki çağrılar **aynı** future'ı
  /// döner (load()'taki re-entry nöbeti bunu await edip native temizliğin tam
  /// bitmesini garanti eder).
  @override
  Future<void> dispose() => _disposeFuture ??= _doDispose();

  Future<void> _doDispose() async {
    await _partialSub?.cancel();
    await _resultSub?.cancel();
    _partialSub = null;
    _resultSub = null;
    final speech = _speech;
    if (speech != null) {
      try {
        await speech.stop();
      } catch (_) {/* zaten durmuş olabilir */}
      try {
        await speech.dispose();
      } catch (_) {/* çift dispose'a karşı */}
    }
    _speech = null;
    await _recognizer?.dispose();
    _recognizer = null;
    _model?.dispose();
    _model = null;
    _listening = false;
    if (identical(_active, this)) _active = null;
    if (!_partials.isClosed) await _partials.close();
    if (!_finals.isClosed) await _finals.close();
  }

  /// Vosk JSON ({"partial":"..."} / {"text":"..."}) → düz metin.
  String _extract(dynamic raw) {
    final s = raw?.toString() ?? '';
    final match = RegExp(r'"(?:partial|text)"\s*:\s*"([^"]*)"').firstMatch(s);
    return match?.group(1) ?? s;
  }
}
