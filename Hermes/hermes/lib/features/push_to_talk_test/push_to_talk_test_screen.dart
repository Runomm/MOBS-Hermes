import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/audio/audio_input.dart';
import '../../core/audio/push_to_talk_audio_input.dart';
import '../../core/audio/wav_writer.dart';
import '../../core/engines/stt/stt_engine.dart';
import '../../core/engines/stt/whisper_cpp_engine.dart';

/// 6r-e — Bas Konuş `PushToTalkAudioInput`'u cihazda doğrulayan standalone
/// smoke ekranı. **VAD YOK** — utterance sınırı buton (bas-tut-konuş).
///
/// Gerçek Bas Konuş paradigması: ekran ortadan **yatay** ikiye bölünür, her
/// yarı kendi tarafının bas-konuş alanı. **Üst yarı 180° döndürülmüş** (karşı
/// taraf telefonu kendine doğru tutarken normal okur), `secondary` source +
/// üst dil. **Alt yarı** normal yön, `primary` source + alt dil. Turn-based:
/// aynı anda tek yarı kayıt alır.
///
/// Amaç: `record.startStream` ham PCM + press/release gating + iki source
/// routing Poco X3 Pro'da çalışıyor mu. Bırakınca samples → WAV → Whisper
/// transkript + süre/peak o yarının içinde gösterilir.
class PushToTalkTestScreen extends StatefulWidget {
  const PushToTalkTestScreen({super.key});

  @override
  State<PushToTalkTestScreen> createState() => _PushToTalkTestScreenState();
}

class _PushToTalkTestScreenState extends State<PushToTalkTestScreen> {
  final PushToTalkAudioInput _input = PushToTalkAudioInput();
  final SttEngine _stt = WhisperCppEngine();
  final WavWriter _wav = const WavWriter();

  StreamSubscription<AudioUtteranceEvent>? _sub;

  bool _armed = false;
  bool _processing = false;

  /// Şu an hangi yarı kayıtta (turn-based, aynı anda tek yarı). null = boşta.
  AudioSource? _recordingSource;

  /// Her yarının Whisper dili. Üst = secondary, Alt = primary.
  String _topLang = 'en';
  String _bottomLang = 'tr';

  final Map<AudioSource, _HalfResult> _results = {};

  String _status = 'Hazırlanıyor…';

  @override
  void initState() {
    super.initState();
    _arm();
  }

  Future<void> _arm() async {
    _sub = _input.utterances.listen(_onUtterance);
    try {
      await _stt.initialize();
      await _input.start(); // izin doğrula + arm
      if (!mounted) return;
      setState(() {
        _armed = true;
        _status = 'Hazır. Bir yarıyı BASILI TUT, konuş, bırak.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Başlatma hatası: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_input.dispose());
    unawaited(_stt.dispose());
    super.dispose();
  }

  void _press(AudioSource source) {
    if (!_armed || _recordingSource != null || _processing) return;
    setState(() {
      _recordingSource = source;
      _status = '🎙 Kayıt (${source.name})… basılı tut';
    });
    unawaited(_input.pressTalk(source));
  }

  void _release() {
    if (_recordingSource == null) return;
    setState(() {
      _recordingSource = null;
      _status = 'İşleniyor…';
    });
    unawaited(_input.releaseTalk());
  }

  Future<void> _onUtterance(AudioUtteranceEvent event) async {
    final lang = event.source == AudioSource.primary ? _bottomLang : _topLang;
    setState(() => _processing = true);

    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'hermes_ptt_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      final file = await _wav.writeMono16kHz(event.samples, path);
      final text = await _stt.transcribeFile(file.path, language: lang);
      unawaited(file.delete().catchError((_) => file));
      if (!mounted) return;
      setState(() {
        _processing = false;
        _results[event.source] = _HalfResult(
          transcript: text.trim().isEmpty ? '(boş transkript)' : text.trim(),
          samples: event.samples.length,
          seconds: event.durationSeconds,
          peak: _peak(event.samples),
        );
        _status = 'Tamam (${event.source.name}). Tekrar dene.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _status = 'Transkript hatası: $e';
      });
    }
  }

  double _peak(List<double> samples) {
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    return peak;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bas Konuş Test — 6r-e'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Column(
        children: [
          _LangBar(
            topLang: _topLang,
            bottomLang: _bottomLang,
            enabled: _armed && _recordingSource == null && !_processing,
            onTop: (v) => setState(() => _topLang = v),
            onBottom: (v) => setState(() => _bottomLang = v),
          ),
          // Üst yarı — karşı taraf (secondary), 180° döndürülmüş içerik.
          Expanded(
            child: RotatedBox(
              quarterTurns: 2,
              child: _HalfButton(
                label: 'ÜST — karşı taraf (secondary)',
                source: AudioSource.secondary,
                recording: _recordingSource == AudioSource.secondary,
                result: _results[AudioSource.secondary],
                color: const Color(0xFF50C878),
                onPress: () => _press(AudioSource.secondary),
                onRelease: _release,
              ),
            ),
          ),
          const Divider(height: 2, thickness: 2, color: Color(0xFF2A2A2A)),
          // Alt yarı — kullanıcı (primary), normal yön.
          Expanded(
            child: _HalfButton(
              label: 'ALT — kullanıcı (primary)',
              source: AudioSource.primary,
              recording: _recordingSource == AudioSource.primary,
              result: _results[AudioSource.primary],
              color: const Color(0xFF7C6FE0),
              onPress: () => _press(AudioSource.primary),
              onRelease: _release,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              _status,
              style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _HalfResult {
  const _HalfResult({
    required this.transcript,
    required this.samples,
    required this.seconds,
    required this.peak,
  });

  final String transcript;
  final int samples;
  final double seconds;
  final double peak;
}

/// Bir ekran yarısının tamamını kaplayan görünmez bas-konuş alanı + feedback.
class _HalfButton extends StatelessWidget {
  const _HalfButton({
    required this.label,
    required this.source,
    required this.recording,
    required this.result,
    required this.color,
    required this.onPress,
    required this.onRelease,
  });

  final String label;
  final AudioSource source;
  final bool recording;
  final _HalfResult? result;
  final Color color;
  final VoidCallback onPress;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPress(),
      onPointerUp: (_) => onRelease(),
      onPointerCancel: (_) => onRelease(),
      child: Container(
        width: double.infinity,
        color: recording
            ? color.withValues(alpha: 0.22)
            : const Color(0xFF111111),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              recording ? Icons.mic : Icons.mic_none,
              size: 44,
              color: recording ? color : const Color(0xFF606060),
            ),
            const SizedBox(height: 8),
            Text(
              recording ? 'KONUŞ…' : 'BASILI TUT KONUŞ',
              style: TextStyle(
                color: recording ? color : const Color(0xFFC0C0C0),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF707070), fontSize: 11),
            ),
            if (result != null) ...[
              const SizedBox(height: 14),
              Text(
                result!.transcript,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFF0F0F0), fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                '${result!.samples} sample · ${result!.seconds.toStringAsFixed(2)} sn · '
                'peak ${result!.peak.toStringAsFixed(3)}',
                style: const TextStyle(color: Color(0xFF707070), fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Üst/alt yarı için Whisper dili seçimi (test kolaylığı; gerçek Bas Konuş'ta
/// dil çifti moda girişte seçilir).
class _LangBar extends StatelessWidget {
  const _LangBar({
    required this.topLang,
    required this.bottomLang,
    required this.enabled,
    required this.onTop,
    required this.onBottom,
  });

  final String topLang;
  final String bottomLang;
  final bool enabled;
  final ValueChanged<String> onTop;
  final ValueChanged<String> onBottom;

  static const _langs = {'tr': 'Türkçe', 'en': 'İngilizce', 'es': 'İspanyolca'};

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _dropdown('Üst dil', topLang, onTop)),
          const SizedBox(width: 16),
          Expanded(child: _dropdown('Alt dil', bottomLang, onBottom)),
        ],
      ),
    );
  }

  Widget _dropdown(String label, String value, ValueChanged<String> onChanged) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: Color(0xFF909090), fontSize: 12),
        ),
        DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF1A1A1A),
          underline: const SizedBox.shrink(),
          style: const TextStyle(color: Color(0xFF7C6FE0), fontSize: 13),
          onChanged: enabled
              ? (v) {
                  if (v != null) onChanged(v);
                }
              : null,
          items: [
            for (final e in _langs.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
        ),
      ],
    );
  }
}
