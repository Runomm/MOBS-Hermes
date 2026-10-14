import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/engines/translation/llm_translation_engine.dart';
import '../../core/engines/translation/nllb_translation_engine.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/services/crunch_service.dart';
import '../../core/services/gemini_client.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../shared/hg_icons.dart';

/// Crunch artık **iki ayrı adım** (2026-06-09, Mehmet): önce [runDeepTranslate]
/// (NLLB ile transkripti hedef dile çevir), sonra [runSummarize] (Gemma ile bu
/// çeviriyi özetle). İkisi de detay ekranındaki butonlardan çağrılır; ilerleme
/// dialogu gösterip sonucu DB'ye yazar. Modeller yoksa indirme yapmaz — uyarır.
///
/// **Faz A — Derinlemesine Çevir.** NLLB transkripti hedef dile çevirir →
/// `crunchTranslation`. Başarılıysa `true`.
Future<bool> runDeepTranslate(
  BuildContext context,
  ConversationRepository repo,
  SessionRow session,
) async {
  final nllb = NllbTranslationEngine();
  final nllbReady =
      await nllb.isLanguageReady(session.sourceLanguage) &&
      await nllb.isLanguageReady(session.targetLanguage);
  if (!nllbReady) {
    if (context.mounted) {
      await _info(
        context,
        'Çeviri modeli gerekli',
        '"Daha İyi Çevir" için NLLB (~1.3GB) cihazda kurulu olmalı. '
            'Ayarlar → Çeviri Modelleri (NMT)\'den indirip tekrar dene.',
      );
    }
    return false;
  }

  final messages = await repo.listMessagesForSession(session.id);
  final transcripts = messages.map((m) => m.sourceText).toList();

  final progress = ValueNotifier<double>(0);
  if (context.mounted) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CrunchProgressDialog(progress: progress, label: 'Çevriliyor…'),
    );
  }

  final service = CrunchService(
    translate: (text, src, tgt) => nllb.translate(text, src, tgt),
    run: (_) async => '', // özet fazı bu adımda çağrılmaz
  );

  try {
    final translation = await service.translateTranscript(
      transcripts: transcripts,
      sourceLang: session.sourceLanguage,
      targetLang: session.targetLanguage,
      onProgress: (p) => progress.value = p,
    );
    await nllb.dispose();
    await repo.setCrunchTranslation(session.id, translation);
    if (context.mounted) Navigator.of(context).pop();
    return true;
  } catch (e) {
    await nllb.dispose();
    if (context.mounted) {
      Navigator.of(context).pop();
      await _info(context, 'Çeviri başarısız', '$e');
    }
    return false;
  } finally {
    progress.dispose();
  }
}

/// **Faz B — Özetle.** Hazır `crunchTranslation`'ı Gemma ile özetler (ana hikaye
/// + önemli noktalar) → `crunchSummary` + başlık + `crunchedAt`. Çeviri henüz
/// yapılmamışsa uyarır. Başarılıysa `true`.
Future<bool> runSummarize(
  BuildContext context,
  ConversationRepository repo,
  SessionRow session,
) async {
  final translation = session.crunchTranslation;
  if (translation == null || translation.trim().isEmpty) {
    if (context.mounted) {
      await _info(
        context,
        'Önce çevir',
        'Özet için önce "Daha İyi Çevir" adımını çalıştır.',
      );
    }
    return false;
  }

  final crunchModel = LlmModelDef.crunch;
  final modelReady = await LlmTranslationEngine(
    crunchModel,
  ).isLanguageReady('en');
  if (!modelReady) {
    if (context.mounted) {
      await _info(
        context,
        'Özet modeli gerekli',
        '${crunchModel.name} (~${crunchModel.sizeMb}MB) cihazda kurulu olmalı. '
            'Ayarlar → Özet Modeli (Crunch)\'tan indirip tekrar dene.',
      );
    }
    return false;
  }

  final progress = ValueNotifier<double>(0);
  if (context.mounted) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CrunchProgressDialog(progress: progress, label: 'Özetleniyor…'),
    );
  }

  final service = CrunchService(
    translate: (text, _, _) async => text, // çeviri fazı bu adımda çağrılmaz
    run: (prompt) =>
        LlmHost.instance.generate(crunchModel, prompt, maxTokens: 1024),
  );

  // RAM disiplini (Mehmet 2026-06-13): özet LLM'i RAM'e sığsın diye NLLB'yi
  // boşalt; iş bitince LLM'i boşalt + NLLB'yi sessizce geri yükle.
  await NllbTranslationEngine.unloadShared();
  try {
    final result = await service.summarize(
      translationText: translation,
      targetLang: session.targetLanguage,
      onProgress: (p) => progress.value = p,
    );
    await repo.setCrunchSummary(
      session.id,
      title: result.title,
      summary: result.summary,
    );
    if (context.mounted) Navigator.of(context).pop();
    return true;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      await _info(context, 'Özet başarısız', '$e');
    }
    return false;
  } finally {
    progress.dispose();
    try {
      await LlmHost.instance.unload();
    } catch (_) {}
    // NLLB'yi arka planda geri yükle — kullanıcı beklemesin (sessiz).
    unawaited(NllbTranslationEngine.preloadShared());
  }
}

/// **Faz B′ — Çevirmeden Özetle (yerel).** "Daha İyi Çevir" adımını atlayıp ham
/// transkripti doğrudan Gemma ile özetler → `crunchSummary` + başlık +
/// `crunchedAt` (çeviri üretilmez). Hızlı özet isteyen kullanıcı için (Mehmet
/// 2026-06-19). Transkript boşsa / model yoksa uyarır. Başarılıysa `true`.
Future<bool> runSummarizeOnly(
  BuildContext context,
  ConversationRepository repo,
  SessionRow session,
) async {
  final messages = await repo.listMessagesForSession(session.id);
  final transcript = messages.map((m) => m.sourceText).join('\n').trim();
  if (transcript.isEmpty) {
    if (context.mounted) {
      await _info(context, 'Transkript boş', 'Özetlenecek metin yok.');
    }
    return false;
  }

  final crunchModel = LlmModelDef.crunch;
  final modelReady = await LlmTranslationEngine(crunchModel).isLanguageReady('en');
  if (!modelReady) {
    if (context.mounted) {
      await _info(
        context,
        'Özet modeli gerekli',
        '${crunchModel.name} (~${crunchModel.sizeMb}MB) cihazda kurulu olmalı. '
            'Ayarlar → Özet Modeli (Crunch)\'tan indirip tekrar dene.',
      );
    }
    return false;
  }

  final progress = ValueNotifier<double>(0);
  if (context.mounted) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CrunchProgressDialog(progress: progress, label: 'Özetleniyor…'),
    );
  }

  final service = CrunchService(
    translate: (text, _, _) async => text,
    run: (prompt) =>
        LlmHost.instance.generate(crunchModel, prompt, maxTokens: 1024),
  );

  await NllbTranslationEngine.unloadShared();
  try {
    final result = await service.summarize(
      translationText: transcript,
      targetLang: session.targetLanguage,
      onProgress: (p) => progress.value = p,
    );
    await repo.setCrunchSummary(
      session.id,
      title: result.title,
      summary: result.summary,
    );
    if (context.mounted) Navigator.of(context).pop();
    return true;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      await _info(context, 'Özet başarısız', '$e');
    }
    return false;
  } finally {
    progress.dispose();
    try {
      await LlmHost.instance.unload();
    } catch (_) {}
    unawaited(NllbTranslationEngine.preloadShared());
  }
}

/// **Çevrimiçi tam crunch (Gemini).** Düşük-RAM / yerel modeli çalıştıramayan
/// cihazlar için: transkripti kullanıcının kendi [apiKey]'iyle Gemini'ye gönderip
/// hedef dile çevirir + özetler + başlık üretir → `crunchTranslation` +
/// `crunchSummary` + `crunchTitle` + `crunchedAt`. Yerel model GEREKTİRMEZ.
/// Başarılıysa `true`.
Future<bool> runOnlineCrunch(
  BuildContext context,
  ConversationRepository repo,
  SessionRow session,
  String apiKey,
) async {
  final messages = await repo.listMessagesForSession(session.id);
  final transcripts = messages.map((m) => m.sourceText).toList();
  if (transcripts.every((t) => t.trim().isEmpty)) {
    if (context.mounted) {
      await _info(
        context,
        'Transkript boş',
        'Özetlenecek metin yok. Önce bir oturum kaydı yap.',
      );
    }
    return false;
  }

  final gemini = GeminiClient(apiKey);
  final progress = ValueNotifier<double>(0);
  if (context.mounted) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CrunchProgressDialog(
        progress: progress,
        label: 'Gemini ile işleniyor…',
      ),
    );
  }

  // Gemini geniş bağlamlı → büyük parçalar (daha az API çağrısı, daha hızlı/ucuz).
  final service = CrunchService(
    translate: (text, src, tgt) => gemini.generate(
      'Translate the following text from ${CrunchService.languageName(src)} '
      'to ${CrunchService.languageName(tgt)}. Output ONLY the translation, '
      'no notes, no explanations.\n\n$text',
      maxTokens: 2048,
    ),
    run: (prompt) => gemini.generate(prompt, maxTokens: 1024),
    maxCharsPerChunk: 4000,
    reduceCharBudget: 8000,
  );

  try {
    final result = await service.crunch(
      transcripts: transcripts,
      sourceLang: session.sourceLanguage,
      targetLang: session.targetLanguage,
      onProgress: (p) => progress.value = p,
    );
    await repo.setCrunchResult(
      session.id,
      title: result.title,
      translation: result.fullTranslation,
      summary: result.summary,
    );
    gemini.close();
    if (context.mounted) Navigator.of(context).pop();
    return true;
  } catch (e) {
    gemini.close();
    if (context.mounted) {
      Navigator.of(context).pop();
      await _info(context, 'Çevrimiçi crunch başarısız', '$e');
    }
    return false;
  } finally {
    progress.dispose();
  }
}

/// **Çevrimiçi özet (Gemini, hibrit).** Hazır yerel `crunchTranslation`'ı
/// (NLLB çıktısı) kullanıcının kendi [apiKey]'iyle Gemini ile özetler →
/// `crunchSummary` + başlık + `crunchedAt`. Yerel çeviri var ama özet modeli
/// çalışmıyorsa idealdir. Çeviri yoksa uyarır. Başarılıysa `true`.
Future<bool> runOnlineSummarize(
  BuildContext context,
  ConversationRepository repo,
  SessionRow session,
  String apiKey,
) async {
  final translation = session.crunchTranslation;
  if (translation == null || translation.trim().isEmpty) {
    if (context.mounted) {
      await _info(
        context,
        'Önce çevir',
        'Özet için önce "Daha İyi Çevir" adımını çalıştır '
            '(veya "Gemini ile Çevir & Özetle" kullan).',
      );
    }
    return false;
  }

  final gemini = GeminiClient(apiKey);
  final progress = ValueNotifier<double>(0);
  if (context.mounted) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CrunchProgressDialog(
        progress: progress,
        label: 'Gemini ile özetleniyor…',
      ),
    );
  }

  final service = CrunchService(
    translate: (text, _, _) async => text, // çeviri zaten yapılmış
    run: (prompt) => gemini.generate(prompt, maxTokens: 1024),
    maxCharsPerChunk: 4000,
    reduceCharBudget: 8000,
  );

  try {
    final result = await service.summarize(
      translationText: translation,
      targetLang: session.targetLanguage,
      onProgress: (p) => progress.value = p,
    );
    await repo.setCrunchSummary(
      session.id,
      title: result.title,
      summary: result.summary,
    );
    gemini.close();
    if (context.mounted) Navigator.of(context).pop();
    return true;
  } catch (e) {
    gemini.close();
    if (context.mounted) {
      Navigator.of(context).pop();
      await _info(context, 'Çevrimiçi özet başarısız', '$e');
    }
    return false;
  } finally {
    progress.dispose();
  }
}

Future<void> _info(BuildContext context, String title, String body) {
  final p = HgPalette.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title, style: HgType.sans(17, weight: 700, color: p.text)),
      content: Text(body, style: HgType.sans(14, color: p.sub, height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );
}

class _CrunchProgressDialog extends StatefulWidget {
  const _CrunchProgressDialog({
    required this.progress,
    this.label = 'İşleniyor…',
  });

  final ValueNotifier<double> progress;
  final String label;

  @override
  State<_CrunchProgressDialog> createState() => _CrunchProgressDialogState();
}

class _CrunchProgressDialogState extends State<_CrunchProgressDialog> {
  /// İlerleme ilk ölçülebilir değere ulaştığında (p>0) damgalanır → geçen süreyi
  /// buradan sayıp kümülatif-ortalama hızla kalan süreyi (ETA) kestiririz
  /// (Mehmet 2026-06-19). Download'daki [etaLabel] kalıbıyla aynı format.
  DateTime? _firstProgressAt;

  /// Geçen süreden + ilerlemeden tahmini kalan süre. p çok küçükken (<%3)
  /// tahmin çok oynak olur → gösterme.
  String? _etaLabel(double p) {
    final start = _firstProgressAt;
    if (start == null || p < 0.03 || p >= 1) return null;
    final elapsed = DateTime.now().difference(start).inSeconds;
    if (elapsed < 1) return null;
    // Kümülatif ortalama: toplam ≈ elapsed / p → kalan = toplam * (1 - p).
    final remaining = (elapsed / p * (1 - p)).round();
    if (remaining <= 0) return null;
    if (remaining < 60) return '${remaining}sn';
    final m = remaining ~/ 60;
    final ss = remaining % 60;
    return ss == 0 ? '~${m}dk' : '~${m}dk ${ss}sn';
  }

  @override
  Widget build(BuildContext context) {
    // Geri tuşu dialogu düşürürse runner'ın iş-sonu pop()'u ekranın kendisini
    // kapatır — barrierDismissible yalnız dış-tıklamayı engeller, geri tuşunu
    // değil. İşlem bitene kadar kapatma kilitli.
    final pal = HgPalette.of(context);
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<double>(
            valueListenable: widget.progress,
            builder: (context, p, _) {
              if (p > 0 && _firstProgressAt == null) {
                _firstProgressAt = DateTime.now();
              }
              final eta = _etaLabel(p);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      HgIcon(
                        HgIcons.sparkle,
                        size: 22,
                        color: pal.visual,
                        strokeWidth: 1.8,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: HgType.sans(17, weight: 600, color: pal.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: p > 0 ? p : null,
                      minHeight: 8,
                      backgroundColor: pal.hairline,
                      color: pal.visual,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        p > 0
                            ? 'tahmini %${(p * 100).toStringAsFixed(0)}'
                            : 'başlıyor…',
                        style: HgType.sans(13, color: pal.sub),
                      ),
                      if (eta != null)
                        Text(
                          'kalan $eta',
                          style: HgType.sans(13, weight: 600, color: pal.sub),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tam çeviri + özet üretiliyor, bu biraz sürebilir.',
                    style: HgType.sans(12, color: pal.faint),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
