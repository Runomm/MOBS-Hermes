import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/audio/dual_mic_channel.dart';

/// 6r-d faz1 — çift mikrofon eş zamanlı yakalamayı cihazda doğrulayan standalone
/// test ekranı. **VAD YOK** — amaç Poco X3 Pro'da (MIUI) iki mic'in gerçekten
/// aynı anda stream verebildiğini kanıtlamak.
///
/// Smoke senaryosu:
/// - Kulaklık tak, "Başlat"
/// - Kulaklığa konuş → sadece **Mic A** barı yükselmeli
/// - Telefon mic'ine konuş → sadece **Mic B** barı yükselmeli
/// - Aynı anda ikisine konuş → her iki bar da yükselmeli (concurrent kanıtı)
///
/// Bu geçerse 6r-d-faz2 (her stream'e ayrı VAD'li `DualMicAudioInput`) yazılır;
/// geçmezse Mehmet pivot kararı verir.
class DualMicTestScreen extends StatefulWidget {
  const DualMicTestScreen({super.key});

  @override
  State<DualMicTestScreen> createState() => _DualMicTestScreenState();
}

class _DualMicTestScreenState extends State<DualMicTestScreen> {
  final DualMicChannel _channel = DualMicChannel();

  StreamSubscription<Uint8List>? _primarySub;
  StreamSubscription<Uint8List>? _secondarySub;

  bool _isRunning = false;
  bool _isStarting = false;
  bool _preferBluetooth = true; // Mehmet: BT çok daha iyi olur

  // 6r-d faz1 deneyi: farklı AudioSource → ayrı concurrent route mı?
  // Varsayılan promising kombinasyon: primary SCO için VOICE_COMMUNICATION,
  // secondary dahili için VOICE_RECOGNITION (farklı use-case = ayrı input client umudu).
  DualMicSource _primarySource = DualMicSource.voiceCommunication;
  DualMicSource _secondarySource = DualMicSource.voiceRecognition;

  double _primaryLevel = 0;
  double _secondaryLevel = 0;
  int _primaryChunks = 0;
  int _secondaryChunks = 0;

  String _status = 'Hazır. Kulaklığı tak, Başlat\'a bas.';
  DualMicStartInfo? _startInfo;

  @override
  void dispose() {
    unawaited(_primarySub?.cancel());
    unawaited(_secondarySub?.cancel());
    if (_isRunning) unawaited(_channel.stop());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isStarting) return;
    if (_isRunning) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _isStarting = true;
      _status = 'Mikrofon izni isteniyor…';
    });

    final granted = await Permission.microphone.request();
    if (!granted.isGranted) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _status = 'RECORD_AUDIO izni reddedildi — yakalama başlatılamaz.';
      });
      return;
    }

    setState(() => _status = 'Çift yakalama başlatılıyor…');

    // Stream'lere start'tan ÖNCE abone ol — native onListen tetiklensin.
    _primarySub ??= _channel.primaryPcm.listen(
      (pcm) => _onChunk(primary: true, pcm: pcm),
      onError: (Object e) => _onStreamError('Mic A', e),
    );
    _secondarySub ??= _channel.secondaryPcm.listen(
      (pcm) => _onChunk(primary: false, pcm: pcm),
      onError: (Object e) => _onStreamError('Mic B', e),
    );

    try {
      final info = await _channel.start(
        preferBluetooth: _preferBluetooth,
        primarySource: _primarySource,
        secondarySource: _secondarySource,
      );
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isRunning = true;
        _startInfo = info;
        _status = 'Dinleniyor. Kulaklığa / telefona ayrı ayrı konuş.';
      });
    } catch (e) {
      await _primarySub?.cancel();
      await _secondarySub?.cancel();
      _primarySub = null;
      _secondarySub = null;
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isRunning = false;
        _status = 'Başlatma hatası: $e';
      });
    }
  }

  Future<void> _stop() async {
    setState(() => _status = 'Durduruluyor…');
    await _channel.stop();
    await _primarySub?.cancel();
    await _secondarySub?.cancel();
    _primarySub = null;
    _secondarySub = null;
    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _primaryLevel = 0;
      _secondaryLevel = 0;
      _status = 'Durduruldu.';
    });
  }

  void _onChunk({required bool primary, required Uint8List pcm}) {
    if (!mounted) return;
    final level = _rms(pcm);
    setState(() {
      if (primary) {
        // Hızlı yükseliş, yumuşak düşüş — bar göze daha okunaklı.
        _primaryLevel = math.max(level, _primaryLevel * 0.78);
        _primaryChunks += 1;
      } else {
        _secondaryLevel = math.max(level, _secondaryLevel * 0.78);
        _secondaryChunks += 1;
      }
    });
  }

  void _onStreamError(String label, Object e) {
    if (!mounted) return;
    setState(() => _status = '$label stream hatası: $e');
  }

  /// PCM16 LE chunk'tan 0..1 normalize RMS.
  double _rms(Uint8List pcm) {
    if (pcm.length < 2) return 0;
    final data = ByteData.sublistView(pcm);
    final sampleCount = pcm.length ~/ 2;
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += s * s;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    // Konuşma RMS'i tipik olarak düşük; görünürlük için biraz ölçekle.
    return (rms * 3.5).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Çift Mic Test — 6r-d faz1'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MicBar(
              label: 'Mic A — kulaklık (primary → sağ)',
              level: _primaryLevel,
              chunks: _primaryChunks,
              color: const Color(0xFF7C6FE0),
            ),
            const SizedBox(height: 16),
            _MicBar(
              label: 'Mic B — telefon (secondary → sol)',
              level: _secondaryLevel,
              chunks: _secondaryChunks,
              color: const Color(0xFF50C878),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              value: _preferBluetooth,
              onChanged: _isRunning || _isStarting
                  ? null
                  : (v) => setState(() => _preferBluetooth = v),
              title: const Text(
                'Bluetooth kulaklığı öncele',
                style: TextStyle(color: Color(0xFFF0F0F0), fontSize: 14),
              ),
              subtitle: const Text(
                'Kapalı: USB/kablolu öncelik, BT fallback',
                style: TextStyle(color: Color(0xFF909090), fontSize: 12),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 4),
            _SourceDropdown(
              label: 'Mic A kaynağı (primary)',
              value: _primarySource,
              enabled: !_isRunning && !_isStarting,
              onChanged: (v) => setState(() => _primarySource = v),
            ),
            const SizedBox(height: 8),
            _SourceDropdown(
              label: 'Mic B kaynağı (secondary)',
              value: _secondarySource,
              enabled: !_isRunning && !_isStarting,
              onChanged: (v) => setState(() => _secondarySource = v),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isStarting ? null : _toggle,
              icon: Icon(_isRunning ? Icons.stop : Icons.headphones),
              label: Text(
                _isStarting
                    ? 'Hazırlanıyor…'
                    : _isRunning
                    ? 'Durdur'
                    : 'Başlat',
                style: const TextStyle(fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _isRunning ? Colors.red.shade900 : null,
              ),
            ),
            if (_startInfo != null) ...[
              const SizedBox(height: 20),
              _StartInfoCard(info: _startInfo!),
            ],
            const Spacer(),
            Text(
              _status,
              style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 13),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MicBar extends StatelessWidget {
  const _MicBar({
    required this.label,
    required this.level,
    required this.chunks,
    required this.color,
  });

  final String label;
  final double level;
  final int chunks;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFFD0D0D0), fontSize: 13),
            ),
            Text(
              '$chunks chunk',
              style: const TextStyle(color: Color(0xFF707070), fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 28,
            color: const Color(0xFF1A1A1A),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: level.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceDropdown extends StatelessWidget {
  const _SourceDropdown({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final DualMicSource value;
  final bool enabled;
  final ValueChanged<DualMicSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFD0D0D0), fontSize: 13),
          ),
        ),
        DropdownButton<DualMicSource>(
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
            for (final s in DualMicSource.values)
              DropdownMenuItem(value: s, child: Text(s.label)),
          ],
        ),
      ],
    );
  }
}

class _StartInfoCard extends StatelessWidget {
  const _StartInfoCard({required this.info});
  final DualMicStartInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Mic A (primary)', info.primaryDevice),
          _row('Mic B (secondary)', info.secondaryDevice),
          _row('Mic A kaynağı', info.primarySource),
          _row('Mic B kaynağı', info.secondarySource),
          _row(
            'Concurrent destek',
            info.dualCaptureSupported ? 'evet (API 29+)' : 'belirsiz',
          ),
          _row('BT SCO başlatıldı', info.scoStarted ? 'evet' : 'hayır'),
        ],
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              k,
              style: const TextStyle(color: Color(0xFF909090), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(color: Color(0xFFD0D0D0), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
