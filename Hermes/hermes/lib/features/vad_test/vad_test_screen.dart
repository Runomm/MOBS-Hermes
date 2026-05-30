import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/vad_controller.dart';

/// Step 3 — Silero VAD'in cihazda doğru çalıştığını doğrulayan standalone test ekranı.
///
/// Konuşma Modu (Step 6+) için altyapıyı izole olarak doğrular:
/// - Başlat → mikrofon dinlemeye başlar
/// - Her konuşma sözcesi end event'inde counter artar
/// - Misfire'lar ayrı sayılır
/// - Son sözcenin süresi gösterilir
class VadTestScreen extends StatefulWidget {
  const VadTestScreen({super.key});

  @override
  State<VadTestScreen> createState() => _VadTestScreenState();
}

class _VadTestScreenState extends State<VadTestScreen> {
  final VadController _vad = SileroVadController();
  StreamSubscription<VadUtteranceEvent>? _sub;

  bool _isListening = false;
  bool _isStarting = false;
  bool _isSpeechActive = false;

  int _utteranceCount = 0;
  int _misfireCount = 0;
  double? _lastUtteranceSeconds;
  String _status = 'Hazır';

  @override
  void initState() {
    super.initState();
    _sub = _vad.events.listen(_onVadEvent);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_vad.dispose());
    super.dispose();
  }

  void _onVadEvent(VadUtteranceEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case VadSpeechStart():
          _isSpeechActive = true;
          _status = 'Konuşma başladı (ön tespit)…';
        case VadRealSpeechStart():
          _isSpeechActive = true;
          _status = 'Konuşma onaylandı (min frame geçti)';
        case VadSpeechEnd(samples: final samples):
          _isSpeechActive = false;
          _utteranceCount += 1;
          _lastUtteranceSeconds = samples.length / 16000.0;
          _status =
              'Sözce tamamlandı · ${_lastUtteranceSeconds!.toStringAsFixed(2)}s · '
              '${samples.length} sample';
        case VadMisfire():
          _isSpeechActive = false;
          _misfireCount += 1;
          _status = 'Yanlış pozitif (kısa, min frame geçemedi)';
        case VadErrorEvent(message: final m):
          _status = 'Hata: $m';
      }
    });
  }

  Future<void> _toggleListening() async {
    if (_isStarting) return;

    if (_isListening) {
      setState(() => _status = 'Durduruluyor…');
      await _vad.stop();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _isSpeechActive = false;
        _status = 'Durduruldu';
      });
      return;
    }

    setState(() {
      _isStarting = true;
      _status = 'Model yükleniyor (asset)…';
    });
    try {
      await _vad.start();
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isListening = true;
        _status = 'Dinleniyor… Konuşmaya başlayabilirsin.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isListening = false;
        _status = 'Başlatma hatası: $e';
      });
    }
  }

  void _resetCounters() {
    setState(() {
      _utteranceCount = 0;
      _misfireCount = 0;
      _lastUtteranceSeconds = null;
      _status = _isListening ? 'Dinleniyor…' : 'Hazır';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VAD Test — Silero v4'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(
            tooltip: 'Sayaçları sıfırla',
            onPressed: _resetCounters,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              isListening: _isListening,
              isSpeechActive: _isSpeechActive,
            ),
            const SizedBox(height: 20),
            _CountersGrid(
              utteranceCount: _utteranceCount,
              misfireCount: _misfireCount,
              lastSeconds: _lastUtteranceSeconds,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isStarting ? null : _toggleListening,
              icon: Icon(_isListening ? Icons.stop : Icons.mic),
              label: Text(
                _isStarting
                    ? 'Hazırlanıyor…'
                    : _isListening
                        ? 'Durdur'
                        : 'Başlat',
                style: const TextStyle(fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _isListening ? Colors.red.shade900 : null,
              ),
            ),
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.isListening, required this.isSpeechActive});
  final bool isListening;
  final bool isSpeechActive;

  @override
  Widget build(BuildContext context) {
    final color = !isListening
        ? const Color(0xFF707070)
        : isSpeechActive
            ? const Color(0xFF7C6FE0)
            : const Color(0xFF50C878);

    final label = !isListening
        ? 'Beklemede'
        : isSpeechActive
            ? '● Konuşma algılandı'
            : '○ Sessizlik bekleniyor';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CountersGrid extends StatelessWidget {
  const _CountersGrid({
    required this.utteranceCount,
    required this.misfireCount,
    required this.lastSeconds,
  });
  final int utteranceCount;
  final int misfireCount;
  final double? lastSeconds;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Counter(label: 'Sözce', value: '$utteranceCount')),
        const SizedBox(width: 12),
        Expanded(child: _Counter(label: 'Misfire', value: '$misfireCount')),
        const SizedBox(width: 12),
        Expanded(
          child: _Counter(
            label: 'Son süre',
            value: lastSeconds == null
                ? '—'
                : '${lastSeconds!.toStringAsFixed(2)}s',
          ),
        ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              color: Color(0xFFF0F0F0),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF909090)),
          ),
        ],
      ),
    );
  }
}
