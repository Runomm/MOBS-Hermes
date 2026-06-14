import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/audio/streaming_mic_audio_input.dart';
import '../../core/audio/wav_writer.dart';
import '../../core/engines/stt/stt_engine.dart';
import '../../core/engines/stt/whisper_cpp_engine.dart';

/// Streaming de-risk test ekranı (Step 7 streaming burst-1a, throwaway).
///
/// `StreamingMicAudioInput`'u gerçek Whisper'la sürer: konuşurken **partial**
/// transkript canlı güncellenir (fast/tiny — hız), konuşma bitince **final**
/// işlenir. Amaç: "susmayı bekleme, canlı/chunk'lı transkript" akışının
/// cihazda çalıştığını Manager/LectureScreen'e dokunmadan kanıtlamak.
class StreamingTestScreen extends StatefulWidget {
  const StreamingTestScreen({super.key});

  @override
  State<StreamingTestScreen> createState() => _StreamingTestScreenState();
}

class _StreamingTestScreenState extends State<StreamingTestScreen> {
  final StreamingMicAudioInput _mic = StreamingMicAudioInput();
  // NOT: İki Whisper modelini (tiny+small) aynı anda yüklemek OOM crash
  // veriyordu → TEK motor (small+fallback). Bu dev ekranı Vosk pivotuyla
  // büyük ölçüde geçersiz; Türkçe için alternatif ASR (Vosk) gelecek.
  final SttEngine _stt = WhisperCppEngine(noFallback: false);
  final WavWriter _wav = const WavWriter();

  StreamSubscription<List<double>>? _partialSub;
  StreamSubscription<List<double>>? _finalSub;
  StreamSubscription<String>? _errSub;

  String _lang = 'tr';
  bool _running = false;
  bool _busy = false;
  String _status = 'Başlat\'a bas, konuş (susmana gerek yok).';
  String _livePartial = '';
  final List<String> _committed = [];

  @override
  void dispose() {
    unawaited(_partialSub?.cancel());
    unawaited(_finalSub?.cancel());
    unawaited(_errSub?.cancel());
    unawaited(_mic.dispose());
    unawaited(_stt.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_running) {
      await _mic.stop();
      await _partialSub?.cancel();
      await _finalSub?.cancel();
      await _errSub?.cancel();
      setState(() {
        _running = false;
        _status = 'Durduruldu.';
        _livePartial = '';
      });
      return;
    }
    setState(() => _status = 'Whisper hazırlanıyor (small)…');
    await _stt.setSpeedMode(SttSpeedMode.accurate);
    await _stt.initialize();
    _partialSub = _mic.partials.listen(_onPartial);
    _finalSub = _mic.finals.listen(_onFinal);
    _errSub = _mic.errors.listen((e) {
      if (mounted) setState(() => _status = 'Hata: $e');
    });
    await _mic.start();
    if (!mounted) return;
    setState(() {
      _running = true;
      _status = 'Dinleniyor — konuş, partial canlı güncellenecek.';
    });
  }

  Future<void> _onPartial(List<double> samples) async {
    if (_busy) return; // önceki transkript bitmeden yenisini başlatma
    _busy = true;
    try {
      final text = await _transcribe(_stt, samples);
      if (mounted) setState(() => _livePartial = text);
    } catch (_) {
      // partial hatası sessiz
    } finally {
      _busy = false;
    }
  }

  Future<void> _onFinal(List<double> samples) async {
    // Final önemli — busy ise kısa bekle, sonra işle.
    var guard = 0;
    while (_busy && guard++ < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _busy = true;
    try {
      final text = await _transcribe(_stt, samples);
      if (!mounted) return;
      setState(() {
        if (text.isNotEmpty) _committed.add(text);
        _livePartial = '';
      });
    } catch (_) {
      // final hatası sessiz
    } finally {
      _busy = false;
    }
  }

  Future<String> _transcribe(SttEngine stt, List<double> samples) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'hermes_stream_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final file = await _wav.writeMono16kHz(samples, path);
    try {
      return (await stt.transcribeFile(file.path, language: _lang)).trim();
    } finally {
      unawaited(file.delete().catchError((_) => file));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Test — burst-1a'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          DropdownButton<String>(
            value: _lang,
            dropdownColor: const Color(0xFF1A1A1A),
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Color(0xFF7C6FE0), fontSize: 14),
            onChanged: _running
                ? null
                : (v) {
                    if (v != null) setState(() => _lang = v);
                  },
            items: const [
              DropdownMenuItem(value: 'tr', child: Text('TR')),
              DropdownMenuItem(value: 'en', child: Text('EN')),
              DropdownMenuItem(value: 'es', child: Text('ES')),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  for (final c in _committed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        c,
                        style: const TextStyle(
                          color: Color(0xFFF0F0F0),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  if (_livePartial.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C6FE0).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_livePartial …',
                        style: const TextStyle(
                          color: Color(0xFFB9AEF0),
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(_running ? Icons.stop : Icons.mic),
              label: Text(_running ? 'Durdur' : 'Başlat'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _running ? Colors.red.shade900 : null,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _status,
              style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
