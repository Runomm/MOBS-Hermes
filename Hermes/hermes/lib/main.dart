import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'core/engines/stt/stt_engine.dart';
import 'core/engines/stt/whisper_cpp_engine.dart';
import 'core/engines/translation/google_mlkit_engine.dart';
import 'core/engines/translation/translation_engine.dart';
import 'core/engines/tts/native_tts_engine.dart';
import 'core/engines/tts/tts_engine.dart';
import 'features/db_test/db_test_screen.dart';
import 'features/vad_test/vad_test_screen.dart';

void main() {
  runApp(const HermesApp());
}

class HermesApp extends StatelessWidget {
  const HermesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C6FE0),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        useMaterial3: true,
      ),
      home: const TranslationTestScreen(),
    );
  }
}

class TranslationTestScreen extends StatefulWidget {
  const TranslationTestScreen({super.key});

  @override
  State<TranslationTestScreen> createState() => _TranslationTestScreenState();
}

class _TranslationTestScreenState extends State<TranslationTestScreen> {
  final TextEditingController _inputController = TextEditingController(
    text: 'Hello world, how are you today?',
  );

  // Strategy Pattern motorları
  final TranslationEngine _translationEngine = GoogleMLKitEngine();
  final SttEngine _sttEngine = WhisperCppEngine();
  final TtsEngine _ttsEngine = NativeOsTtsEngine();
  final AudioRecorder _recorder = AudioRecorder();

  String _fromCode = 'en';
  String _toCode = 'tr';
  String _result = '';
  String _status = 'Hazır';

  bool _isRecording = false;
  bool _isBusy = false; // transcribe veya translate sürerken
  bool _isSpeaking = false;
  bool _autoSpeak = true; // çeviri biter bitmez otomatik seslendir

  String? _currentRecordingPath;

  /// Dil kodu → cihazda paket indirilmiş mi?
  /// null = henüz sorulmadı (yükleniyor).
  final Map<String, bool?> _languageReady = {};

  static const Map<String, String> _languages = {
    'en': 'İngilizce',
    'tr': 'Türkçe',
    'es': 'İspanyolca',
    'fr': 'Fransızca',
    'de': 'Almanca',
    'it': 'İtalyanca',
  };

  @override
  void initState() {
    super.initState();
    // Açılışta her dilin indirilmiş olup olmadığını öğren.
    for (final code in _languages.keys) {
      _languageReady[code] = null;
    }
    unawaited(_refreshLanguageStates());
  }

  Future<void> _refreshLanguageStates() async {
    for (final code in _languages.keys) {
      try {
        final ready = await _translationEngine.isLanguageReady(code);
        if (!mounted) return;
        setState(() => _languageReady[code] = ready);
      } catch (_) {
        if (!mounted) return;
        setState(() => _languageReady[code] = false);
      }
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    unawaited(_translationEngine.dispose());
    unawaited(_sttEngine.dispose());
    unawaited(_ttsEngine.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  // ---------- TRANSLATE ----------

  Future<void> _translate(String text) async {
    if (text.isEmpty) return;

    setState(() {
      _isBusy = true;
      _status = 'Çeviriliyor (ilk seferde model indirilebilir)…';
      _result = '';
    });

    try {
      final translated =
          await _translationEngine.translate(text, _fromCode, _toCode);
      if (!mounted) return;
      setState(() {
        _result = translated;
        _status = '${_translationEngine.engineName} · '
            '${_translationEngine.isOfflineCapable ? "offline" : "online"}';
        _isBusy = false;
      });

      if (_autoSpeak) {
        unawaited(_speak(translated));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = '';
        _status = 'Çeviri hatası: $e';
        _isBusy = false;
      });
    }
  }

  Future<void> _onTranslatePressed() => _translate(_inputController.text.trim());

  // ---------- TTS ----------

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    try {
      setState(() {
        _isSpeaking = true;
        _status = '${_ttsEngine.engineName} · seslendiriliyor…';
      });
      await _ttsEngine.speak(text, _toCode);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'TTS hatası: $e');
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _onSpeakPressed() async {
    if (_isSpeaking) {
      await _ttsEngine.stop();
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    } else {
      await _speak(_result);
    }
  }

  // ---------- RECORD + TRANSCRIBE ----------

  Future<void> _onMicPressed() async {
    if (_isRecording) {
      await _stopRecordingAndProcess();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _status = 'Mikrofon izni reddedildi.');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/hermes_rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(const RecordConfig(), path: path);

      _currentRecordingPath = path;
      setState(() {
        _isRecording = true;
        _status = 'Dinleniyor… Konuş ve tekrar dokun.';
        _result = '';
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        _status = 'Kayıt başlatılamadı: $e';
      });
    }
  }

  Future<void> _stopRecordingAndProcess() async {
    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _isBusy = true;
        _status = 'Transkript ediliyor… (Whisper)';
      });

      final audioPath = path ?? _currentRecordingPath;
      if (audioPath == null || !File(audioPath).existsSync()) {
        setState(() {
          _isBusy = false;
          _status = 'Kayıt dosyası bulunamadı.';
        });
        return;
      }

      final transcript =
          await _sttEngine.transcribeFile(audioPath, language: _fromCode);

      if (!mounted) return;
      setState(() {
        _inputController.text = transcript;
        _status = 'Transkript hazır, çeviriliyor…';
      });

      // Otomatik çeviri
      await _translate(transcript);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = 'Transkript hatası: $e';
      });
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hermes — Çeviri + STT Testi'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(
            tooltip: 'VAD Test (Silero)',
            icon: const Icon(Icons.graphic_eq),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VadTestScreen()),
            ),
          ),
          IconButton(
            tooltip: 'DB Test (Drift + SQLite)',
            icon: const Icon(Icons.storage),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DbTestScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _buildLanguageDropdown(true)),
                const SizedBox(width: 12),
                const Icon(Icons.arrow_forward),
                const SizedBox(width: 12),
                Expanded(child: _buildLanguageDropdown(false)),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _inputController,
              maxLines: 4,
              enabled: !_isRecording && !_isBusy,
              decoration: const InputDecoration(
                labelText: 'Çevrilecek metin (yaz veya konuş)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: (_isBusy || _isRecording) ? null : _onTranslatePressed,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isBusy && !_isRecording
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Çevir', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  width: 56,
                  child: FilledButton.tonal(
                    onPressed: _isBusy ? null : _onMicPressed,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor:
                          _isRecording ? Colors.red.shade900 : null,
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording ? Colors.white : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 48),
                          child: Text(
                            _result.isEmpty
                                ? '(çeviri burada görünür)'
                                : _result,
                            style: TextStyle(
                              fontSize: 18,
                              color: _result.isEmpty
                                  ? const Color(0xFF707070)
                                  : const Color(0xFFF0F0F0),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip:
                            _isSpeaking ? 'Seslendirmeyi durdur' : 'Seslendir',
                        onPressed: (_result.isEmpty || _isBusy)
                            ? null
                            : _onSpeakPressed,
                        icon: Icon(
                          _isSpeaking ? Icons.stop_circle : Icons.volume_up,
                          color: _isSpeaking
                              ? Colors.red.shade300
                              : const Color(0xFF7C6FE0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Switch(
                  value: _autoSpeak,
                  onChanged: (v) => setState(() => _autoSpeak = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Çeviri biter bitmez seslendir',
                    style: TextStyle(fontSize: 13, color: Color(0xFFC0C0C0)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              _status,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF909090),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageDropdown(bool isSource) {
    final selected = isSource ? _fromCode : _toCode;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: isSource ? 'Kaynak' : 'Hedef',
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          isDense: true,
          dropdownColor: const Color(0xFF1A1A1A),
          // Kapalı dropdown'da yalnızca düz Text göster.
          // _LanguageRow (Row+Icon+Expanded(Text)) inline render edilince
          // InputDecorator+RenderIndexedStack baseline döngüsü patlıyor.
          selectedItemBuilder: (context) => _languages.values
              .map((name) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      name,
                      style: const TextStyle(color: Color(0xFFF0F0F0)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          items: _languages.entries
              .map((e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: _LanguageRow(
                      name: e.value,
                      ready: _languageReady[e.key],
                      sizeMb: _translationEngine.estimatedDownloadSizeMb(e.key),
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            unawaited(_handleLanguageChange(isSource, v));
          },
        ),
      ),
    );
  }

  /// Dropdown'da yeni bir dil seçildiğinde çağrılır.
  /// Paket indirilmemişse onay dialog'u + indirme akışı tetiklenir.
  /// Onay verilmezse seçim geri alınır.
  Future<void> _handleLanguageChange(bool isSource, String code) async {
    final ready = _languageReady[code] ?? false;

    if (!ready) {
      final accepted = await _showDownloadDialog(code);
      if (accepted != true) {
        // Kullanıcı reddetti → dropdown UI'sini eski değere zorla geri al.
        setState(() {});
        return;
      }

      setState(() {
        _isBusy = true;
        _status =
            '${_languages[code]} paketi indiriliyor (~${_translationEngine.estimatedDownloadSizeMb(code)}MB)…';
      });

      try {
        await _translationEngine.downloadLanguage(code);
        if (!mounted) return;
        setState(() {
          _languageReady[code] = true;
          _isBusy = false;
          _status = '${_languages[code]} paketi hazır.';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isBusy = false;
          _status = 'Indirme başarısız: $e';
        });
        return;
      }
    }

    setState(() {
      if (isSource) {
        _fromCode = code;
      } else {
        _toCode = code;
      }
    });
  }

  Future<bool?> _showDownloadDialog(String code) {
    final name = _languages[code] ?? code;
    final sizeMb = _translationEngine.estimatedDownloadSizeMb(code);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('$name paketini indir'),
        content: Text(
          'Bu dilin çeviri modeli (~${sizeMb}MB) cihazına henüz indirilmedi. '
          'İnternet üzerinden indirilecek. Sonrasında offline çalışacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('İndir'),
          ),
        ],
      ),
    );
  }
}

/// Dropdown öğesinde dil adı + indirme durumu görseli.
/// İndirilmiş: beyaz metin + ✓ ikonu. İndirilmemiş: gri metin + ⬇ ikonu + ~MB.
/// Yükleniyor (null): nötr gri.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.name,
    required this.ready,
    required this.sizeMb,
  });

  final String name;
  final bool? ready;
  final int sizeMb;

  @override
  Widget build(BuildContext context) {
    final isReady = ready == true;
    final isUnknown = ready == null;

    final color = isReady
        ? const Color(0xFFF0F0F0)
        : isUnknown
            ? const Color(0xFFA0A0A0)
            : const Color(0xFF808080);

    return Row(
      children: [
        Icon(
          isReady
              ? Icons.check_circle
              : isUnknown
                  ? Icons.hourglass_empty
                  : Icons.download,
          size: 16,
          color: isReady ? const Color(0xFF7C6FE0) : color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: TextStyle(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!isReady && !isUnknown)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '~${sizeMb}MB',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF808080),
              ),
            ),
          ),
      ],
    );
  }
}
