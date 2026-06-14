import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// De-risk ekranı — local LLM çeviri (Tier 3) **Qwen ↔ Gemma yan yana kıyas**.
///
/// Mehmet (2026-06-03): Gemma'ya geçmeden önce Qwen ile aynı cümleler üzerinde
/// **kalite + hız** kıyaslaması ister. Bu ekran iki modeli ayrı ayrı indirir,
/// aynı girdiyle sırayla çevirir (OOM'a karşı tek seferde tek model RAM'de),
/// her model için **yükleme** ve **üretim (prompt→sonuç)** sürelerini ölçer ve
/// sonuçları yan yana gösterir.
///
/// - **Qwen2.5-1.5B-Instruct** (Apache-2.0, non-gated, token gerekmez)
/// - **Gemma3-1B-IT** (Gemma Terms of Use, gated → ücretsiz HF token + lisans
///   onayı gerekir; token kutusu aşağıda). Model diske cache'lenir; token
///   yalnızca indirme anında lazım.
class LlmTranslateTestScreen extends StatefulWidget {
  const LlmTranslateTestScreen({super.key});

  @override
  State<LlmTranslateTestScreen> createState() => _LlmTranslateTestScreenState();
}

enum _ModelKind { qwen, gemma }

/// Bir modelin statik tanımı.
class _ModelDef {
  const _ModelDef({
    required this.kind,
    required this.label,
    required this.url,
    required this.modelType,
    required this.fileType,
    required this.sizeMb,
    required this.requiresToken,
    required this.idMatch,
    required this.accent,
  });

  final _ModelKind kind;
  final String label;
  final String url;
  final ModelType modelType;
  final ModelFileType fileType;
  final int sizeMb;
  final bool requiresToken;
  final String idMatch; // listInstalledModels id'sinde aranan alt-dize
  final Color accent;
}

const _qwen = _ModelDef(
  kind: _ModelKind.qwen,
  label: 'Qwen2.5-1.5B',
  url:
      'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_seq128_q8_ekv1280.task',
  modelType: ModelType.qwen,
  fileType: ModelFileType.task,
  sizeMb: 1567,
  requiresToken: false,
  idMatch: 'qwen',
  accent: Color(0xFF7C6FE0),
);

const _gemma = _ModelDef(
  kind: _ModelKind.gemma,
  // Gemma3-1B-IT q4 (555MB, repodaki gerçek dosya — WebFetch ile doğrulandı).
  // SD860'a uygun hafif .task; Gemma-4-E2B (2.6GB) bu cihaz için fazla ağırdı.
  // 401 → token license onayı yapılmamış demektir.
  label: 'Gemma3-1B-IT',
  url:
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
  modelType: ModelType.gemmaIt,
  fileType: ModelFileType.task,
  sizeMb: 555,
  requiresToken: true,
  idMatch: 'gemma',
  accent: Color(0xFF3DB39E),
);

const _models = [_qwen, _gemma];

enum _Phase { checking, needsDownload, downloading, ready, error }

/// Bir modelin çalışma-zamanı durumu.
class _ModelState {
  _Phase phase = _Phase.checking;
  double progress = 0;
  String error = '';
  String output = '';
  int? loadMs; // install(idempotent)+getActiveModel
  int? genMs; // sadece getResponse (prompt→sonuç)
  bool busy = false;
}

class _LlmTranslateTestScreenState extends State<LlmTranslateTestScreen> {
  static const int _maxTokens = 512;

  final Map<_ModelKind, _ModelState> _state = {
    _ModelKind.qwen: _ModelState(),
    _ModelKind.gemma: _ModelState(),
  };

  final TextEditingController _input = TextEditingController(
    text: 'Merhaba, bugün hava çok güzel ve dışarı çıkmak istiyorum.',
  );
  final TextEditingController _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_checkAll());
  }

  _ModelState _s(_ModelKind k) => _state[k]!;
  _ModelDef _def(_ModelKind k) => _models.firstWhere((m) => m.kind == k);

  Future<void> _checkAll() async {
    List<String> installed;
    try {
      installed = await FlutterGemma.listInstalledModels();
    } catch (e) {
      for (final d in _models) {
        _set(
          () => _s(d.kind)
            ..phase = _Phase.error
            ..error = e.toString(),
        );
      }
      return;
    }
    for (final d in _models) {
      final has = installed.any((m) => m.toLowerCase().contains(d.idMatch));
      _set(() => _s(d.kind).phase = has ? _Phase.ready : _Phase.needsDownload);
    }
  }

  Future<void> _download(_ModelKind kind) async {
    final d = _def(kind);
    final s = _s(kind);
    if (d.requiresToken && _token.text.trim().isEmpty) {
      _set(
        () => s
          ..phase = _Phase.error
          ..error = 'Gemma gated — yukarıdaki kutuya HF token yapıştır.',
      );
      return;
    }
    _set(
      () => s
        ..phase = _Phase.downloading
        ..progress = 0
        ..error = '',
    );
    try {
      await FlutterGemma.installModel(
            modelType: d.modelType,
            fileType: d.fileType,
          )
          .fromNetwork(
            d.url,
            token: d.requiresToken ? _token.text.trim() : null,
          )
          .withProgress((p) => _set(() => s.progress = p / 100.0))
          .install();
      _set(() => s.phase = _Phase.ready);
    } catch (e) {
      _set(
        () => s
          ..phase = _Phase.error
          ..error = e.toString(),
      );
    }
  }

  /// Tek bir modelle çeviri. Model RAM'e yüklenir, çevirir, **kapatılır**
  /// (sıradaki modelle OOM olmasın). Yükleme + üretim süreleri ölçülür.
  Future<void> _translateOne(_ModelKind kind, String text) async {
    final d = _def(kind);
    final s = _s(kind);
    if (s.phase != _Phase.ready || s.busy || text.isEmpty) return;

    _set(
      () => s
        ..busy = true
        ..output = ''
        ..loadMs = null
        ..genMs = null,
    );

    InferenceModel? model;
    InferenceModelSession? session;
    try {
      // install() idempotent — indirilmişse atlar, modeli AKTİF yapar (swap).
      final loadSw = Stopwatch()..start();
      await FlutterGemma.installModel(
            modelType: d.modelType,
            fileType: d.fileType,
          )
          .fromNetwork(
            d.url,
            token: d.requiresToken ? _token.text.trim() : null,
          )
          .install();
      model = await FlutterGemma.getActiveModel(
        maxTokens: _maxTokens,
        preferredBackend: PreferredBackend.cpu, // SD860'te GPU LLM güvenilmez
      );
      loadSw.stop();

      session = await model.createSession();
      await session.addQueryChunk(
        Message.text(
          text:
              'Translate the following text from Turkish to English. '
              'Output ONLY the English translation, no explanation.\n\n'
              'Text: $text\n\nTranslation:',
          isUser: true,
        ),
      );

      // Kronometre: prompt gönderildikten SONRA sonuç üretme süresi.
      final genSw = Stopwatch()..start();
      final out = await session.getResponse();
      genSw.stop();

      _set(
        () => s
          ..output = out.trim()
          ..loadMs = loadSw.elapsedMilliseconds
          ..genMs = genSw.elapsedMilliseconds,
      );
    } catch (e) {
      _set(
        () => s
          ..output = '⚠️ HATA: $e'
          ..error = e.toString(),
      );
    } finally {
      await session?.close();
      await model?.close(); // RAM'i boşalt — sıradaki model için
      _set(() => s.busy = false);
    }
  }

  bool get _anyBusy => _state.values.any((s) => s.busy);

  void _set(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void dispose() {
    _input.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('LLM Çeviri — Qwen ↔ Gemma kıyas'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _input,
              maxLines: 2,
              style: const TextStyle(color: Color(0xFFF0F0F0)),
              decoration: const InputDecoration(
                labelText: 'Türkçe metin (her iki model aynı girdiyle)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _token,
              obscureText: true,
              style: const TextStyle(color: Color(0xFFF0F0F0), fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'HuggingFace token (yalnız Gemma indirmesi için)',
                hintText: 'hf_...',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.key, size: 18),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Her modeli kendi "Çevir" butonuyla SIRAYLA çalıştır — '
              'biri çalışırken diğeri kilitli (cihaz ikisini aynı anda RAM\'de tutamaz).',
              style: TextStyle(color: Color(0xFF808080), fontSize: 11),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _modelCard(_qwen)),
                  const SizedBox(width: 8),
                  Expanded(child: _modelCard(_gemma)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelCard(_ModelDef d) {
    final s = _s(d.kind);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: d.accent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, size: 16, color: d.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d.label,
                  style: TextStyle(
                    color: d.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _statusLine(d, s),
          if (s.phase == _Phase.ready) ...[
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _anyBusy
                  ? null
                  : () => _translateOne(d.kind, _input.text.trim()),
              icon: s.busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate, size: 16),
              label: Text(
                s.busy ? 'Çeviriliyor…' : 'Çevir',
                style: const TextStyle(fontSize: 12),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: d.accent,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(child: _resultBox(s)),
          const SizedBox(height: 6),
          _timing(s),
        ],
      ),
    );
  }

  Widget _statusLine(_ModelDef d, _ModelState s) {
    switch (s.phase) {
      case _Phase.checking:
        return const Text(
          'kontrol ediliyor…',
          style: TextStyle(color: Color(0xFF808080), fontSize: 11),
        );
      case _Phase.needsDownload:
        return OutlinedButton.icon(
          onPressed: () => _download(d.kind),
          icon: const Icon(Icons.download, size: 15),
          label: Text(
            'İndir (~${d.sizeMb}MB)',
            style: const TextStyle(fontSize: 11),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            foregroundColor: d.accent,
            side: BorderSide(color: d.accent.withValues(alpha: 0.5)),
          ),
        );
      case _Phase.downloading:
        final pct = (s.progress * 100).clamp(0, 100).toStringAsFixed(0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: s.progress > 0 ? s.progress : null,
                minHeight: 6,
                backgroundColor: const Color(0xFF2A2A2A),
                color: d.accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'indiriliyor %$pct',
              style: TextStyle(color: d.accent, fontSize: 11),
            ),
          ],
        );
      case _Phase.ready:
        return Row(
          children: [
            Icon(Icons.check_circle, size: 13, color: d.accent),
            const SizedBox(width: 4),
            Text('hazır', style: TextStyle(color: d.accent, fontSize: 11)),
            const Spacer(),
            if (s.busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        );
      case _Phase.error:
        return Text(
          'hata: ${s.error}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFFFB0B0), fontSize: 10),
        );
    }
  }

  Widget _resultBox(_ModelState s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Text(
          s.output.isEmpty ? '(çeviri burada)' : s.output,
          style: TextStyle(
            fontSize: 15,
            height: 1.35,
            color: s.output.isEmpty
                ? const Color(0xFF606060)
                : (s.output.startsWith('⚠️')
                      ? const Color(0xFFFFB0B0)
                      : const Color(0xFFF0F0F0)),
          ),
        ),
      ),
    );
  }

  Widget _timing(_ModelState s) {
    if (s.genMs == null) {
      return const Text(
        '—',
        style: TextStyle(color: Color(0xFF606060), fontSize: 11),
      );
    }
    final gen = (s.genMs! / 1000).toStringAsFixed(1);
    final load = s.loadMs != null ? (s.loadMs! / 1000).toStringAsFixed(1) : '?';
    return Text(
      '⚡ üretim ${gen}sn · yükleme ${load}sn',
      style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 11),
    );
  }
}
