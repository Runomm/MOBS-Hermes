import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/engines/stt/vosk_streaming_controller.dart';

/// 🧪 **Vosk EN model de-risk** (2026-06-09). Mevcut `vosk-model-small-en-us-0.15`
/// (39MB) İngilizce'de zayıf olabiliyor → daha doğru EN modeli arayışı.
///
/// Canlı mic ile aynı konuşmayı farklı modellerle transkript edip doğruluk +
/// hız + RAM (çökme) kıyaslanır. Adaylar (Mehmet sırası: önce daanzu):
///   - `vosk-model-small-en-us-0.15` — mevcut baseline (39MB, managed)
///   - **`vosk-model-en-us-daanzu-20200905`** — ~922MB (ÖNCE bunu)
///   - `vosk-model-en-us-0.22` — ~1.8GB (daanzu yetmezse)
///
/// Büyük modeller adb-push ile `<externalAppDir>/vosk_en_derisk/<dir>` altına
/// atılır; ekran `VoskStreamingController.load(modelPathOverride:)` ile yükler.
/// Kazanan → `vosk_models.dart` EN kaydına alınır. Dev/test ekranı (release'de
/// menüden çıkar).
class VoskEnDeriskScreen extends StatefulWidget {
  const VoskEnDeriskScreen({super.key});

  @override
  State<VoskEnDeriskScreen> createState() => _VoskEnDeriskScreenState();
}

class _Cand {
  const _Cand(this.label, this.dirName);
  final String label;

  /// adb-push'lu model dizin adı; `null` → managed baseline (VoskModelManager).
  final String? dirName;
}

class _VoskEnDeriskScreenState extends State<VoskEnDeriskScreen> {
  static const _candidates = <_Cand>[
    _Cand('small-en-us-0.15 (baseline, 39MB)', null),
    _Cand('daanzu-20200905 (~922MB)', 'vosk-model-en-us-daanzu-20200905'),
    _Cand('en-us-0.22 (~1.8GB)', 'vosk-model-en-us-0.22'),
  ];

  VoskStreamingController? _controller;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _finalSub;

  _Cand? _active;
  bool _busy = false;
  String _partial = '';
  final List<String> _finals = [];
  String? _error;

  Future<String> _dir() async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationSupportDirectory();
    return '${base.path}/vosk_en_derisk';
  }

  @override
  void dispose() {
    unawaited(_partialSub?.cancel());
    unawaited(_finalSub?.cancel());
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _listen(_Cand cand) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _partial = '';
      _finals.clear();
    });
    try {
      await _partialSub?.cancel();
      await _finalSub?.cancel();
      await _controller?.dispose();
      _controller = null;

      String? override;
      if (cand.dirName != null) {
        override = '${await _dir()}/${cand.dirName}';
        if (!Directory(override).existsSync()) {
          throw 'Model yok (adb-push edilmeli):\n$override';
        }
      }
      final c = VoskStreamingController();
      await c.load('en', modelPathOverride: override);
      _partialSub = c.partials.listen((p) {
        if (mounted) setState(() => _partial = p);
      });
      _finalSub = c.finals.listen((f) {
        if (mounted && f.trim().isNotEmpty) {
          setState(() => _finals.add(f.trim()));
        }
      });
      await c.start();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _active = cand;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _active = null;
        _busy = false;
      });
    }
  }

  Future<void> _stop() async {
    await _partialSub?.cancel();
    await _finalSub?.cancel();
    _partialSub = null;
    _finalSub = null;
    await _controller?.dispose();
    if (!mounted) return;
    setState(() {
      _controller = null;
      _active = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final listening = _controller != null;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('🧪 Vosk EN De-risk'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Bir model seç → İngilizce konuş → doğruluğu kıyasla. Büyük modeller '
              'önce adb-push edilmeli. Aynı cümleleri her modelle söyle.',
              style: TextStyle(color: Color(0xFF909090), fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final c in _candidates) _candTile(c, listening),
            const SizedBox(height: 8),
            if (listening)
              FilledButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop),
                label: const Text('Durdur'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                'HATA: $_error',
                style: const TextStyle(color: Color(0xFFE07B7B), fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            if (_partial.trim().isNotEmpty)
              Text(
                _partial,
                style: const TextStyle(
                  color: Color(0xFF8FE0A8),
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _finals.isEmpty
                        ? '(transkript burada birikir)'
                        : _finals.join('\n'),
                    style: TextStyle(
                      color: _finals.isEmpty
                          ? const Color(0xFF707070)
                          : const Color(0xFFE0E0E0),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candTile(_Cand c, bool listening) {
    final isActive = identical(_active, c);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              c.label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF8FE0A8)
                    : const Color(0xFFE0E0E0),
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          FilledButton(
            onPressed: (_busy || isActive) ? null : () => _listen(c),
            child: Text(isActive ? 'Dinleniyor' : 'Dinle'),
          ),
        ],
      ),
    );
  }
}
