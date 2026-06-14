import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/engines/translation/small100_onnx_translator.dart';
import '../../core/models/small100_model_manager.dart';

/// SMaLL-100 fast-mod de-risk ekranı (spike) — **tek motor: SMaLL-100**.
///
/// Amaç (Mehmet 2026-06-06, ONNX'e geçiş kararı): SMaLL-100 ONNX'in SD860'ta
/// (1) yükleniyor mu, (2) Türkçe çeviri kalitesi LLM'leri geçiyor mu,
/// (3) hız ne (KV-cache YOK → büyüyen dizi decode, etiketli). Protokol doğru mu
/// (hedef dil token'ı kaynağa eklenir) burada doğrulanır. Geçerse fast moda
/// entegre edilir + full=NLLB ile birlikte fast/full'e bağlanır.
class Small100TestScreen extends StatefulWidget {
  const Small100TestScreen({super.key});

  @override
  State<Small100TestScreen> createState() => _Small100TestScreenState();
}

/// BCP-47 kodu → ad. Translator `__<code>__` token'ına çevirir.
const _langs = {
  'tr': 'Türkçe',
  'en': 'İngilizce',
  'es': 'İspanyolca',
  'de': 'Almanca',
  'fr': 'Fransızca',
  'it': 'İtalyanca',
};

class _Small100TestScreenState extends State<Small100TestScreen> {
  final _mgr = Small100ModelManager();
  Small100OnnxTranslator? _translator;

  final _input = TextEditingController(
    text: 'Merhaba, yakınlarda iyi bir market var mı?',
  );
  String _src = 'tr';
  String _tgt = 'en';

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
    for (final f in Small100ModelManager.files) {
      _downloaded[f.id] = await _mgr.isDownloaded(f);
    }
    _allReady = await _mgr.allDownloaded();
    _set(() {});
  }

  Future<void> _downloadAll() async {
    _set(() => _busy = true);
    try {
      for (final f in Small100ModelManager.files) {
        if (_downloaded[f.id] == true) continue;
        await _mgr.download(
          f,
          onProgress: (p) => _set(() => _progress[f.id] = p),
        );
        _set(() => _downloaded[f.id] = true);
      }
      await _refresh();
    } catch (e) {
      _set(
        () => _output =
            '⚠️ İndirme hatası: $e\n\n(Xet TLS ise PC\'den '
            'adb push gerekir — konsola bak.)',
      );
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
      _translator ??= Small100OnnxTranslator(
        encoderPath: await _mgr.pathFor(
          Small100ModelManager.fileById('encoder'),
        ),
        decoderPath: await _mgr.pathFor(
          Small100ModelManager.fileById('decoder'),
        ),
        decoderWithPastPath: await _mgr.pathFor(
          Small100ModelManager.fileById('decoder_past'),
        ),
        tokenizerJsonPath: await _mgr.pathFor(
          Small100ModelManager.fileById('tokenizer'),
        ),
      );

      final loadSw = Stopwatch()..start();
      await _translator!.load();
      loadSw.stop();

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
        title: const Text('SMaLL-100 fast de-risk'),
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
              label: Text(_busy ? 'Çalışıyor…' : 'Çevir (SMaLL-100)'),
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
                '(KV-cache YOK)',
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
            'Model dosyaları (~580MB)',
            style: TextStyle(color: Color(0xFFC0C0C0), fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final f in Small100ModelManager.files) _fileRow(f),
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

  Widget _fileRow(Small100File f) {
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
