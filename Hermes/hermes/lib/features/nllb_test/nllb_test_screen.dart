import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/engines/translation/nllb_onnx_translator.dart';
import '../../core/models/nllb_model_manager.dart';

/// NLLB Tier2 de-risk ekranı (spike) — **tek motor: NLLB**.
///
/// Amaç: NLLB-200-distilled-600M ONNX'in SD860'ta (1) yükleniyor mu, (2) çeviri
/// kalitesi MLKit'i geçiyor mu, (3) hız ne (past'sız decode = yavaş, etiketli).
/// Geçerse sonraki burst MLKit vs NLLB vs Qwen 3-kart kıyasa genişletir.
class NllbTestScreen extends StatefulWidget {
  const NllbTestScreen({super.key});

  @override
  State<NllbTestScreen> createState() => _NllbTestScreenState();
}

/// NLLB dil kodu seçenekleri (FLORES-200).
const _langs = {
  'tur_Latn': 'Türkçe',
  'eng_Latn': 'İngilizce',
  'spa_Latn': 'İspanyolca',
  'deu_Latn': 'Almanca',
  'fra_Latn': 'Fransızca',
};

class _NllbTestScreenState extends State<NllbTestScreen> {
  final _mgr = NllbModelManager();
  NllbOnnxTranslator? _translator;

  final _input = TextEditingController(
    text: 'Merhaba, bugün hava çok güzel ve dışarı çıkmak istiyorum.',
  );
  String _src = 'tur_Latn';
  String _tgt = 'eng_Latn';

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
    for (final f in NllbModelManager.files) {
      _downloaded[f.id] = await _mgr.isDownloaded(f);
    }
    _allReady = await _mgr.allDownloaded();
    _set(() {});
  }

  Future<void> _downloadAll() async {
    _set(() => _busy = true);
    try {
      for (final f in NllbModelManager.files) {
        if (_downloaded[f.id] == true) continue;
        await _mgr.download(
          f,
          onProgress: (p) => _set(() => _progress[f.id] = p),
        );
        _set(() => _downloaded[f.id] = true);
      }
      await _refresh();
    } catch (e) {
      _set(() => _output = '⚠️ İndirme hatası: $e');
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
      _translator ??= NllbOnnxTranslator(
        encoderPath: await _mgr.pathFor(NllbModelManager.fileById('encoder')),
        decoderPath: await _mgr.pathFor(NllbModelManager.fileById('decoder')),
        decoderWithPastPath: await _mgr.pathFor(
          NllbModelManager.fileById('decoder_past'),
        ),
        spModelPath: await _mgr.pathFor(NllbModelManager.fileById('tokenizer')),
      );

      final loadSw = Stopwatch()..start();
      await _translator!.load();
      loadSw.stop();

      // Debug: modelin gerçek girdi/çıktı tensor adları (yanlışsa anında görünür).
      final t = _translator!;
      _debug =
          'enc.in=${t.encoderInputNames} enc.out=${t.encoderOutputNames}\n'
          'dec.in=${t.decoderInputNames} dec.out=${t.decoderOutputNames}';

      final genSw = Stopwatch()..start();
      final out = await _translator!.translate(
        _input.text.trim(),
        srcLang: _src,
        tgtLang: _tgt,
      );
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

  /// Modeli (ONNX session'ları + tokenizer) RAM'den boşaltır. Sonraki çeviri
  /// yeniden yükler. Mehmet isteği: kıyas sırasında üst üste yükleme OOM yapıyor.
  Future<void> _unload() async {
    await _translator?.dispose();
    _set(() {
      _translator = null;
      _loadMs = null;
      _genMs = null;
    });
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
        title: const Text('NLLB Tier2 de-risk'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          if (_allReady)
            IconButton(
              tooltip: 'Modelleri sil',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy
                  ? null
                  : () async {
                      await _mgr.deleteAll();
                      await _translator?.dispose();
                      _translator = null;
                      _progress.clear();
                      await _refresh();
                    },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView(
          children: [
            _modelSection(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _langDropdown('Kaynak', _src, (v) => _src = v)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, color: Color(0xFF808080)),
                ),
                Expanded(child: _langDropdown('Hedef', _tgt, (v) => _tgt = v)),
              ],
            ),
            const SizedBox(height: 10),
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
              label: Text(_busy ? 'Çalışıyor…' : 'Çevir (NLLB)'),
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
                '⚡ üretim ${(_genMs! / 1000).toStringAsFixed(1)}sn · '
                'yükleme ${(_loadMs! / 1000).toStringAsFixed(1)}sn '
                '(KV-cache decode)',
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
          const Text(
            'Model dosyaları (~1.3GB)',
            style: TextStyle(color: Color(0xFFC0C0C0), fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final f in NllbModelManager.files) _fileRow(f),
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

  Widget _fileRow(NllbFile f) {
    final done = _downloaded[f.id] == true;
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

  Widget _langDropdown(
    String label,
    String value,
    ValueChanged<String> onPick,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isDense: true,
      dropdownColor: const Color(0xFF1A1A1A),
      style: const TextStyle(color: Color(0xFFF0F0F0), fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final e in _langs.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) {
        if (v != null) _set(() => onPick(v));
      },
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
