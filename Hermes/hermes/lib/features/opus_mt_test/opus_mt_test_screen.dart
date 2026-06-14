import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/engines/translation/opus_mt_onnx_translator.dart';
import '../../core/models/opus_mt_model_manager.dart';

/// Opus-MT de-risk ekranı (spike) — **çift-özel Marian NMT**.
///
/// Mehmet 2026-06-06 (SMaLL-100/NLLB-600M yetersiz, NLLB-1.3B OOM): Opus-MT
/// çift-özel küçük (~156MB) → OOM yok + hızlı. Amaç: tr→en kalitesi NLLB'yi
/// geçiyor mu? Geçerse fast moda + en-tr eklenir.
class OpusMtTestScreen extends StatefulWidget {
  const OpusMtTestScreen({super.key});

  @override
  State<OpusMtTestScreen> createState() => _OpusMtTestScreenState();
}

class _OpusMtTestScreenState extends State<OpusMtTestScreen> {
  final _mgr = OpusMtModelManager();
  final OpusMtPair _pair = OpusMtModelManager.pairs.first;
  OpusMtOnnxTranslator? _translator;

  final _input = TextEditingController(
    text: 'Merhaba, yakınlarda iyi bir market var mı?',
  );

  final Map<String, double> _progress = {};
  final Map<String, bool> _downloaded = {};
  bool _allReady = false;
  bool _busy = false;
  String _output = '';
  String _debug = '';
  int? _loadMs;
  int? _genMs;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    for (final f in OpusMtModelManager.filesFor(_pair)) {
      _downloaded['${_pair.id}/${f.id}'] = await _mgr.isDownloaded(_pair, f);
    }
    _allReady = await _mgr.allDownloaded(_pair);
    _set(() {});
  }

  Future<void> _downloadAll() async {
    _set(() => _busy = true);
    try {
      for (final f in OpusMtModelManager.filesFor(_pair)) {
        if (_downloaded['${_pair.id}/${f.id}'] == true) continue;
        await _mgr.download(
          _pair,
          f,
          onProgress: (p) => _set(() => _progress[f.id] = p),
        );
      }
      await _refresh();
    } catch (e) {
      _set(() => _output = '⚠️ İndirme hatası: $e\n(Xet ise PC adb push.)');
    } finally {
      _set(() => _busy = false);
    }
  }

  Future<void> _translate() async {
    if (_busy || !_allReady) return;
    _set(() {
      _busy = true;
      _output = '';
      _debug = '';
      _loadMs = null;
      _genMs = null;
    });
    try {
      _translator ??= OpusMtOnnxTranslator(
        encoderPath: await _mgr.pathFor(_pair, _file('encoder')),
        decoderPath: await _mgr.pathFor(_pair, _file('decoder')),
        decoderWithPastPath: await _mgr.pathFor(_pair, _file('decoder_past')),
        tokenizerJsonPath: await _mgr.pathFor(_pair, _file('tokenizer')),
        decoderStartId: _pair.decoderStartId,
        eosId: _pair.eosId,
      );

      final loadSw = Stopwatch()..start();
      await _translator!.load();
      loadSw.stop();

      final t = _translator!;
      _debug =
          'enc.in=${t.encoderInputNames}\n'
          'dec.in=${t.decoderInputNames}\ndec.out=${t.decoderOutputNames}';

      final genSw = Stopwatch()..start();
      final out = await _translator!.translate(_input.text.trim());
      genSw.stop();

      _set(() {
        _output = out;
        _loadMs = loadSw.elapsedMilliseconds;
        _genMs = genSw.elapsedMilliseconds;
      });
    } catch (e) {
      _set(() => _output = '⚠️ HATA: $e');
    } finally {
      _set(() => _busy = false);
    }
  }

  OpusMtFile _file(String id) =>
      OpusMtModelManager.filesFor(_pair).firstWhere((f) => f.id == id);

  Future<void> _unload() async {
    await _translator?.dispose();
    _set(() => _translator = null);
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    _input.dispose();
    unawaited(_translator?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Opus-MT de-risk'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView(
          children: [
            _modelSection(),
            const SizedBox(height: 12),
            TextField(
              controller: _input,
              maxLines: 3,
              style: const TextStyle(color: Color(0xFFF0F0F0)),
              decoration: const InputDecoration(
                labelText: 'Metin',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: (!_allReady || _busy) ? null : _translate,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate),
              label: Text(_busy ? 'Çalışıyor…' : 'Çevir (${_pair.label})'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3DB39E),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            if (_translator?.isLoaded == true) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _busy ? null : _unload,
                icon: const Icon(Icons.memory, size: 16),
                label: const Text('Durdur — RAM\'den boşalt'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE0A03D),
                  side: const BorderSide(color: Color(0x55E0A03D)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _resultBox(),
            if (_genMs != null) ...[
              const SizedBox(height: 6),
              Text(
                '⚡ üretim ${(_genMs! / 1000).toStringAsFixed(2)}sn · '
                'yükleme ${(_loadMs! / 1000).toStringAsFixed(2)}sn',
                style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 11),
              ),
            ],
            if (_debug.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _debug,
                style: const TextStyle(
                  color: Color(0xFF6699AA),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modelSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_pair.label} (~156MB)',
            style: const TextStyle(color: Color(0xFFC0C0C0), fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final f in OpusMtModelManager.filesFor(_pair)) _fileRow(f),
          if (!_allReady) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _downloadAll,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Eksikleri indir'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3DB39E),
                side: const BorderSide(color: Color(0x553DB39E)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fileRow(OpusMtFile f) {
    final done = _downloaded['${_pair.id}/${f.id}'] == true;
    final prog = _progress[f.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: done ? const Color(0xFF3DB39E) : const Color(0xFF606060),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${f.fileName} (~${f.sizeMb}MB)',
              style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 11),
            ),
          ),
          if (!done && prog > 0)
            Text(
              '%${(prog * 100).toStringAsFixed(0)}',
              style: const TextStyle(color: Color(0xFF3DB39E), fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _resultBox() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _output.isEmpty ? '(çeviri burada görünecek)' : _output,
        style: TextStyle(
          fontSize: 16,
          height: 1.35,
          color: _output.isEmpty
              ? const Color(0xFF606060)
              : (_output.startsWith('⚠️')
                    ? const Color(0xFFFFB0B0)
                    : const Color(0xFFF0F0F0)),
        ),
      ),
    );
  }
}
