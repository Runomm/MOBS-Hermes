import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/crunch_service.dart';
import '../../core/utils/llm_text.dart';

/// 🧪 **Crunch modeli de-risk** (2026-06-09). Phi-4 (3.76GB) GitHub'a sığmıyor +
/// Xet + Poco'da OOM riski → crunch (özet) modeli için yeni de-risk turu.
///
/// 3 aday (hafif→orta→üst) `.task` dosyaları PC'den indirilip **adb-push** ile
/// `<externalAppDir>/crunch_derisk/` altına atılır (GH'e yüklemeden). Bu ekran her
/// modeli `fromFile` ile yükler, sabit Türkçe örnek konuşmayı **gerçek crunch
/// promptlarıyla** (`CrunchService` — translate=kimlik, çünkü örnek zaten TR)
/// özetler; başlık + özet + süre gösterir. Mehmet 3'ünü kıyaslar (kalite/hız/OOM).
///
/// Kazanan → GH Release'e yüklenip kalıcı crunch modeli olur (streamed indirici +
/// `fromFile`). Dev/test ekranı — release'de menüden çıkar.
class CrunchDeriskScreen extends StatefulWidget {
  const CrunchDeriskScreen({super.key});

  @override
  State<CrunchDeriskScreen> createState() => _CrunchDeriskScreenState();
}

class _Candidate {
  const _Candidate(
    this.label,
    this.tier,
    this.type,
    this.fileName,
    this.sizeMb, {
    this.fileType = ModelFileType.task,
  });
  final String label;
  final String tier;
  final ModelType type;
  final String fileName;
  final int sizeMb;
  final ModelFileType fileType;
}

class _Result {
  _Result({
    this.title,
    this.summary,
    this.elapsedMs,
    this.error,
    this.running = false,
  });
  String? title;
  String? summary;
  int? elapsedMs;
  String? error;
  bool running;
}

class _CrunchDeriskScreenState extends State<CrunchDeriskScreen> {
  static const _candidates = <_Candidate>[
    _Candidate(
      'Gemma3-1B-IT q8',
      'hafif/orta · Poco rahat',
      ModelType.gemmaIt,
      'Gemma3-1B-IT_multi-prefill-seq_q8_ekv1280.task',
      1050,
    ),
    _Candidate(
      'Qwen2.5-1.5B q8',
      'orta · Poco rahat · TR güçlü',
      ModelType.qwen,
      'Qwen2.5-1.5B-Instruct_seq128_q8_ekv1280.task',
      1567,
    ),
    _Candidate(
      'Phi-4-mini q8',
      'üst düzey · Poco yavaş/OOM testi',
      ModelType.phi,
      'Phi-4-mini-instruct_multi-prefill-seq_q8_ekv1280.task',
      3761,
    ),
    _Candidate(
      'Gemma-4-E2B (litertlm)',
      'yeni · ~2B elastic · Poco testi',
      ModelType.gemmaIt,
      'gemma-4-E2B-it.litertlm',
      2468,
      fileType: ModelFileType.litertlm,
    ),
  ];

  /// Sabit Türkçe örnek konuşma (Erasmus/turist bağlamı) — crunch girdisi.
  /// translate=kimlik olduğundan crunch doğrudan bu satırları özetler.
  static const _sample = <String>[
    'Merhaba, yarınki tarih dersi sınavı için hangi konulara çalışmalıyız?',
    'Fransız İhtilali ve sonuçları kesinlikle çıkacak, ayrıca Sanayi Devrimi.',
    'Sanayi Devrimi’nin toplumsal etkilerini de soracak mı acaba?',
    'Evet, özellikle işçi sınıfının doğuşu ve kentleşme üzerinde durun dedi.',
    'Bir de ödev vardı değil mi, ne zamana teslim edeceğiz?',
    'Ödev gelecek pazartesiye, iki sayfalık bir deneme yazmamız gerekiyor.',
    'Kaynak olarak ders kitabının dışında bir şey önerdi mi?',
    'Kütüphanedeki Hobsbawm’ın kitabına bakmamızı tavsiye etti.',
    'Tamam, o zaman bu hafta sonu birlikte çalışalım mı?',
    'Olur, cumartesi öğleden sonra kütüphanede buluşalım.',
  ];

  final Map<String, _Result> _results = {};

  Future<String> _dir() async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationSupportDirectory();
    return '${base.path}/crunch_derisk';
  }

  Future<void> _run(_Candidate c) async {
    setState(() => _results[c.fileName] = _Result(running: true));
    InferenceModel? model;
    final sw = Stopwatch()..start();
    try {
      final path = '${await _dir()}/${c.fileName}';
      if (!File(path).existsSync()) {
        throw 'Dosya yok (adb-push edilmeli):\n$path';
      }
      // Yerel dosyadan yükle (kopyalamaz, yerinde referans) + aktif yap.
      await FlutterGemma.installModel(
        modelType: c.type,
        fileType: c.fileType,
      ).fromFile(path).install();
      model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.cpu, // SD860 GPU LLM güvenilmez
      );
      final m = model;
      final svc = CrunchService(
        translate: (t, _, _) async => t, // örnek zaten TR → çeviri yok
        run: (prompt) async {
          final s = await m.createSession();
          try {
            await s.addQueryChunk(Message.text(text: prompt, isUser: true));
            return sanitizeLlmOutput(await s.getResponse());
          } finally {
            await s.close();
          }
        },
      );
      final res = await svc.crunch(
        transcripts: _sample,
        sourceLang: 'tr',
        targetLang: 'tr',
      );
      sw.stop();
      if (!mounted) return;
      setState(
        () => _results[c.fileName] = _Result(
          title: res.title,
          summary: res.summary,
          elapsedMs: sw.elapsedMilliseconds,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _results[c.fileName] = _Result(error: '$e'));
    } finally {
      await model?.close(); // RAM'i boşalt (sıradaki aday için)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('🧪 Crunch Modeli De-risk'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Aynı Türkçe örnek konuşmayı 3 modelle crunch\'la (özet + başlık). '
            'Kalite + süreyi kıyasla. Üst düzey model (Phi-4) Poco\'da OOM ile '
            'çökerse uygulama kapanabilir = o tier flagship\'e ait demektir.',
            style: TextStyle(color: Color(0xFF909090), fontSize: 13),
          ),
          const SizedBox(height: 16),
          for (final c in _candidates) _card(c),
        ],
      ),
    );
  }

  Widget _card(_Candidate c) {
    final r = _results[c.fileName];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.label,
                      style: const TextStyle(
                        color: Color(0xFFF0F0F0),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${c.tier} · ${c.sizeMb} MB',
                      style: const TextStyle(
                        color: Color(0xFF909090),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: (r?.running ?? false) ? null : () => _run(c),
                child: (r?.running ?? false)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Çalıştır'),
              ),
            ],
          ),
          if (r != null && !r.running) ...[
            const SizedBox(height: 10),
            if (r.error != null)
              Text(
                'HATA: ${r.error}',
                style: const TextStyle(color: Color(0xFFE07B7B), fontSize: 13),
              )
            else ...[
              Text(
                'Süre: ${(r.elapsedMs! / 1000).toStringAsFixed(1)} sn',
                style: const TextStyle(color: Color(0xFF8FE0A8), fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                'Başlık: ${r.title}',
                style: const TextStyle(
                  color: Color(0xFFCFC8FF),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Özet:',
                style: TextStyle(color: Color(0xFF909090), fontSize: 12),
              ),
              SelectableText(
                r.summary ?? '',
                style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
