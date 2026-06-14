import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import '../../core/models/vosk_model_manager.dart';
import '../../core/models/vosk_models.dart';

/// De-risk ekranı — Türkçe Vosk ASR'yi Whisper'a karşı kıyaslamak için.
///
/// Sadece Türkçe tanıma yapar; çeviri/Whisper YOK. Amaç: Poco X3 Pro'da
/// `vosk-model-small-tr-0.3` ile sürekli streaming tanımanın doğruluk/hızını
/// gözlemleyip Whisper small'un Türkçe zayıflığına alternatif olup
/// olmayacağına karar vermek (punch_board "İLK İŞ: Vosk Türkçe ASR de-risk").
///
/// Model otomatik İNMEZ — Mehmet'in isteği: önce "indirilmesi gerek" uyarısı +
/// İndir butonu + ilerleme çubuğu (düz bekleme yok). Model bir kez inince
/// cihaza cache'lenir, sonraki açılışlarda doğrudan yüklenir.
class VoskTestScreen extends StatefulWidget {
  const VoskTestScreen({super.key});

  @override
  State<VoskTestScreen> createState() => _VoskTestScreenState();
}

enum _Phase { checking, needsDownload, downloading, loading, ready, error }

class _VoskTestScreenState extends State<VoskTestScreen> {
  static const int _sampleRate = 16000;

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  // De-risk ekranı Türkçeye sabit (Whisper TR'de zayıftı, asıl kıyas burası).
  final VoskModelManager _modelManager = VoskModelManager(
    VoskModels.byLang['tr']!,
  );

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _resultSub;

  _Phase _phase = _Phase.checking;
  String _status = 'Model durumu kontrol ediliyor…';
  String _error = '';
  double _downloadProgress = 0;
  String _partial = '';
  final List<String> _finals = [];
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkModel());
  }

  /// Açılışta: model cihazda var mı? Varsa yükle, yoksa indirme uyarısı göster.
  Future<void> _checkModel() async {
    try {
      final downloaded = await _modelManager.isDownloaded();
      if (downloaded) {
        await _loadModelAndSpeech();
      } else {
        _set(() {
          _phase = _Phase.needsDownload;
          _status = 'Türkçe model inmemiş.';
        });
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _download() async {
    _set(() {
      _phase = _Phase.downloading;
      _downloadProgress = 0;
      _status = 'İndiriliyor…';
    });
    try {
      await _modelManager.download(
        onProgress: (p) => _set(() => _downloadProgress = p),
      );
      _set(() => _status = 'Çıkartılıyor…');
      await _loadModelAndSpeech();
    } catch (e) {
      _fail(e);
    }
  }

  /// Model dosyadan yüklenir + recognizer + (Android) SpeechService kurulur.
  Future<void> _loadModelAndSpeech() async {
    _set(() {
      _phase = _Phase.loading;
      _status = 'Model yükleniyor…';
    });

    // Mikrofon izni — vosk SpeechService Android'de RECORD_AUDIO ister.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _set(() {
        _phase = _Phase.error;
        _error = 'Mikrofon izni reddedildi.';
        _status = 'İzin yok';
      });
      return;
    }

    final modelPath = await _modelManager.modelPath();
    _model = await _vosk.createModel(modelPath);
    _recognizer = await _vosk.createRecognizer(
      model: _model!,
      sampleRate: _sampleRate,
    );
    _speechService = await _vosk.initSpeechService(_recognizer!);

    _partialSub = _speechService!.onPartial().listen((p) {
      _set(() => _partial = _extract(p));
    });
    _resultSub = _speechService!.onResult().listen((r) {
      final text = _extract(r);
      if (text.trim().isEmpty) return;
      _set(() {
        _finals.add(text.trim());
        _partial = '';
      });
    });

    _set(() {
      _phase = _Phase.ready;
      _status = 'Hazır — Başlat\'a bas, Türkçe konuş.';
    });
  }

  /// Vosk JSON döndürür ({"partial":"..."} / {"text":"..."}). Sade ayıkla.
  String _extract(dynamic raw) {
    final s = raw?.toString() ?? '';
    final match = RegExp(r'"(?:partial|text)"\s*:\s*"([^"]*)"').firstMatch(s);
    return match?.group(1) ?? s;
  }

  Future<void> _toggle() async {
    if (_speechService == null) return;
    if (_listening) {
      await _speechService!.stop();
      _set(() {
        _listening = false;
        _status = 'Durduruldu.';
      });
    } else {
      await _speechService!.start();
      _set(() {
        _listening = true;
        _partial = '';
        _status = 'Dinleniyor… (Türkçe)';
      });
    }
  }

  void _fail(Object e) => _set(() {
    _phase = _Phase.error;
    _error = e.toString();
    _status = 'Hata';
  });

  void _set(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void dispose() {
    unawaited(_partialSub?.cancel());
    unawaited(_resultSub?.cancel());
    final speech = _speechService;
    if (speech != null) {
      unawaited(speech.stop().then((_) => speech.dispose()));
    }
    final recognizer = _recognizer;
    if (recognizer != null) unawaited(recognizer.dispose());
    _model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vosk Türkçe Test (ASR de-risk)'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          if (_phase == _Phase.ready && _finals.isNotEmpty)
            IconButton(
              tooltip: 'Temizle',
              icon: const Icon(Icons.clear_all),
              onPressed: () => _set(() {
                _finals.clear();
                _partial = '';
              }),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (_phase) {
          _Phase.checking ||
          _Phase.loading => _centered(const CircularProgressIndicator()),
          _Phase.needsDownload => _downloadGate(),
          _Phase.downloading => _downloadingView(),
          _Phase.error => _errorView(),
          _Phase.ready => _readyView(),
        },
      ),
    );
  }

  Widget _centered(Widget child) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        child,
        const SizedBox(height: 16),
        Text(
          _status,
          style: const TextStyle(color: Color(0xFF909090), fontSize: 13),
        ),
      ],
    ),
  );

  Widget _downloadGate() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.cloud_download_outlined,
            size: 64,
            color: Color(0xFF7C6FE0),
          ),
          const SizedBox(height: 20),
          const Text(
            'Türkçe Vosk modeli gerekli',
            style: TextStyle(
              color: Color(0xFFF0F0F0),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Türkçe konuşma tanıma için ~35MB\'lık model bir kez '
            'indirilmeli. Sonrasında offline çalışır.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF909090), fontSize: 14),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download),
            label: const Text('İndir (~35MB)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _downloadingView() {
    final pct = (_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Türkçe model indiriliyor',
            style: TextStyle(color: Color(0xFFF0F0F0), fontSize: 16),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              minHeight: 10,
              backgroundColor: const Color(0xFF2A2A2A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _downloadProgress > 0 ? '%$pct' : _status,
            style: const TextStyle(color: Color(0xFF9C8FF0), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 56, color: Color(0xFFFFB0B0)),
        const SizedBox(height: 16),
        Text(
          'Hata: $_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFFFB0B0)),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () {
            _set(() {
              _error = '';
              _phase = _Phase.checking;
            });
            unawaited(_checkModel());
          },
          child: const Text('Tekrar dene'),
        ),
      ],
    ),
  );

  Widget _readyView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Birikmiş final sonuçlar (Whisper'a kıyas için).
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: const Color(0xFF2A2A2A)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                _finals.isEmpty
                    ? '(tanınan cümleler burada birikecek)'
                    : _finals.join('\n'),
                style: TextStyle(
                  fontSize: 18,
                  height: 1.4,
                  color: _finals.isEmpty
                      ? const Color(0xFF707070)
                      : const Color(0xFFF0F0F0),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Canlı partial.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF14141E),
            border: Border.all(color: const Color(0xFF2A2A3A)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _partial.isEmpty ? '…' : _partial,
            style: const TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: Color(0xFF9C8FF0),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _toggle,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            backgroundColor: _listening ? Colors.red.shade900 : null,
          ),
          child: Text(
            _listening ? 'Durdur' : 'Başlat',
            style: const TextStyle(fontSize: 18, color: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _status,
          style: const TextStyle(fontSize: 12, color: Color(0xFF909090)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
