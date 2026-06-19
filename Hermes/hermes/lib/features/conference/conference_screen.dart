import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/engines/stt/vosk_streaming_controller.dart';
import '../../core/engines/stt/whisper_streaming_transcriber.dart';
import '../../core/engines/translation/translation_tier.dart';
import '../../core/engines/tts/native_tts_engine.dart';
import '../../core/engines/tts/silent_tts_engine.dart';
import '../../core/engines/tts/tts_engine.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/services/ram_manager.dart';
import '../../core/session/conference_streaming_session.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';
import '../shared/models_required_gate.dart';
import 'conference_detail_screen.dart';

/// Konferans Modu çalışan ekranı (K1–K4 + streaming #1) — liquid-glass
/// `ConferenceLive` 5-faz akışı (2026-06-12 restyle; SmallTalk canlı ekranıyla
/// yapısal olarak aynı, fark: tek yönlü dinleme + tam genişlik altyazı kartları).
///
/// **Streaming pipeline** (Mehmet #1, "Gemini hızı"): Vosk `SpeechService`
/// kelime kelime canlı transkript üretir → dosya turu yok, geride kalma yok.
/// [ConferenceStreamingSession] üzerinden çalışır (Manager bypass).
class ConferenceScreen extends StatefulWidget {
  const ConferenceScreen({
    super.key,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.ttsEnabled,
    this.tier = TranslationTier.mlkit,
  });

  final String sourceLanguage;
  final String targetLanguage;
  final bool ttsEnabled;

  /// Canlı çeviri katmanı: fast = MLKit (anında), full = NLLB (offline NMT).
  final TranslationTier tier;

  @override
  State<ConferenceScreen> createState() => _ConferenceScreenState();
}

enum _Phase { checking, needsModels, warmup, running, ended, error }

class _ConferenceScreenState extends State<ConferenceScreen> {
  late final AppDatabase _db;
  late final ConversationRepository _repo;
  ConferenceStreamingSession? _session;

  StreamSubscription<String>? _translationSub;
  StreamSubscription<String>? _partialSub;

  _Phase _phase = _Phase.checking;
  bool _warmingUp = true;
  String? _error;
  List<String> _missing = [];

  int? _endedSessionId;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;

  final List<String> _translations = [];
  String _partial = '';
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _db = AppDatabase();
    _repo = ConversationRepository(_db);
    unawaited(_checkModel());
  }

  @override
  void dispose() {
    unawaited(_translationSub?.cancel());
    unawaited(_partialSub?.cancel());
    _scroll.dispose();
    // Önce session'ı kapat (end() → boş oturum silme), SONRA DB'yi kapat. Eskiden
    // _db.close() senkron çalışıp deleteSessionIfEmpty'yi boşa düşürüyordu → boş
    // transkriptler kalıyordu (Mehmet 2026-06-13).
    final session = _session;
    unawaited(() async {
      await session?.dispose();
      await _db.close();
    }());
    super.dispose();
  }

  /// STT (Vosk) + çeviri katmanı (fast=MLKit dil paketi / full=NLLB) hazır mı?
  /// İkisi de hazırsa ısınmaya geç; değilse **indirme kapısı YOK** — eksik model
  /// adlarını listeleyip kullanıcıyı Ayarlar'a yönlendir (Mehmet 2026-06-09:
  /// indirmeler yalnız Ayarlar'dan). Ayarlar'dan dönünce bu kontrol tekrarlanır.
  Future<void> _checkModel() async {
    setState(() => _phase = _Phase.checking);
    try {
      final voskReady = await ConferenceStreamingSession.isModelReady(
        widget.sourceLanguage,
      );
      final transReady = await isTierReady(
        widget.tier,
        widget.sourceLanguage,
        widget.targetLanguage,
      );
      if (!mounted) return;
      if (voskReady && transReady) {
        await _warmUp();
        return;
      }
      final missing = <String>[];
      if (!voskReady) {
        missing.add(Platform.isIOS
            ? 'Whisper small (~466MB)'
            : 'Vosk ${_langName(widget.sourceLanguage)}');
      }
      if (!transReady) {
        missing.add(
          widget.tier == TranslationTier.nllb
              ? 'NLLB-600M (~1.3GB)'
              : 'ML Kit: ${_langName(widget.sourceLanguage)} + '
                    '${_langName(widget.targetLanguage)}',
        );
      }
      setState(() {
        _missing = missing;
        _phase = _Phase.needsModels;
      });
    } catch (e) {
      _fail(e);
    }
  }

  /// Streaming session'ı kur + motorları ısıt (kullanıcı "Başlat"a basana kadar).
  Future<void> _warmUp() async {
    setState(() {
      _phase = _Phase.warmup;
      _warmingUp = true;
    });
    try {
      // Temiz başlangıç: önceki işten artakalan özet LLM'ini RAM'den boşalt
      // (NLLB resident kalır) → OOM riski azalır (Mehmet 2026-06-13).
      await RamManager.freeForLiveSession();
      final TtsEngine tts = widget.ttsEnabled
          ? NativeOsTtsEngine()
          : const SilentTtsEngine();
      final session = ConferenceStreamingSession(
        // iOS'te Vosk yok → Whisper chunked streaming; Android'de Vosk native.
        transcriber: Platform.isIOS
            ? WhisperStreamingTranscriber()
            : VoskStreamingController(),
        repository: _repo,
        // Canlı çeviri: fast=MLKit (hızlı), full=NLLB (offline NMT). Tam çeviri +
        // özet oturum sonunda crunch'ta.
        translation: createTranslationEngine(widget.tier),
        tts: tts,
        sourceLanguage: widget.sourceLanguage,
        targetLanguage: widget.targetLanguage,
        ttsEnabled: widget.ttsEnabled,
      );
      await session.prepare();
      if (!mounted) {
        unawaited(session.dispose());
        return;
      }
      _session = session;
      setState(() => _warmingUp = false);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _start() async {
    final session = _session;
    if (session == null || _warmingUp) return;
    _translationSub = session.translations.listen(_onTranslation);
    _partialSub = session.livePartial.listen((p) {
      if (mounted) setState(() => _partial = p);
    });
    try {
      await session.start();
      if (!mounted) return;
      _startedAt = DateTime.now();
      setState(() => _phase = _Phase.running);
    } catch (e) {
      _fail(e);
    }
  }

  void _onTranslation(String translated) {
    if (!mounted) return;
    setState(() => _translations.add(translated));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _end() async {
    _elapsed = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    // end() boş transkriptli oturumu siler → null döner (kaydedilmedi).
    _endedSessionId = await _session?.end();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.ended;
      _partial = '';
    });
  }

  /// Crunch artık 2 adım (Derinlemesine Çevir + Özetle) ve detay ekranında
  /// yapılır → bitiş ekranı oraya yönlendirir.
  void _openDetail() {
    final id = _endedSessionId;
    if (id == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ConferenceDetailScreen(sessionId: id)),
    );
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _error = '$e';
    });
  }

  String get _langArrow =>
      '${widget.sourceLanguage.toUpperCase()} → ${widget.targetLanguage.toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return HgScreen(
      scroll: false,
      padded: false,
      child: switch (_phase) {
        _Phase.checking => _spinner(p),
        _Phase.needsModels => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Hg.pad),
          child: ModelsRequiredGate(missing: _missing, onRecheck: _checkModel),
        ),
        _Phase.warmup => _warmupView(p),
        _Phase.running => _runningView(p),
        _Phase.ended => _endedView(p),
        _Phase.error => _errorView(p),
      },
    );
  }

  Widget _topBar(HgPalette p, {String? label, Color? dot}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 0),
      child: HgSerifTopBar(
        title: 'Konferans',
        sub:
            '$_langArrow · ${widget.tier == TranslationTier.nllb ? 'Akıllı' : 'Hızlı'}'
            '${widget.ttsEnabled ? ' · 🎧' : ''}',
        label: label,
        dotColor: dot,
      ),
    );
  }

  Widget _spinner(HgPalette p) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: p.conference),
        const SizedBox(height: 16),
        Text('Hazırlanıyor…', style: HgType.sans(13, color: p.sub)),
      ],
    ),
  );

  // ── warmup ──
  Widget _warmupView(HgPalette p) {
    final warming = _warmingUp;
    return Column(
      children: [
        _topBar(
          p,
          label: warming ? 'Isınıyor' : 'Hazır',
          dot: warming ? p.manual : p.live,
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HgWarmupCircle(
                icon: HgIcons.conference,
                label: warming ? 'Isınıyor…' : 'Dinle',
                warming: warming,
                accent: p.conference,
                onTap: _start,
              ),
              const SizedBox(height: 26),
              HgSerifTitle(
                warming ? 'Motor ısınıyor' : 'Konferansa hazır',
                size: 24,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 6, 40, 0),
                child: Text(
                  'Daireye dokun — model ısınınca çeviri canlı olarak akmaya başlar.',
                  textAlign: TextAlign.center,
                  style: HgType.sans(13, color: p.sub, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── running ──
  Widget _runningView(HgPalette p) {
    final listening = _partial.trim().isNotEmpty;
    return Column(
      children: [
        _topBar(p, label: 'Canlı', dot: p.live),
        Expanded(
          child: _translations.isEmpty && !listening
              ? Center(
                  child: Text(
                    'Dinleniyor…',
                    style: HgType.sans(15, color: p.faint),
                  ),
                )
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 8),
                  children: [
                    for (final t in _translations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: HgGlass(
                          radius: 20,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 13,
                          ),
                          child: Text(
                            t,
                            style: HgType.sans(
                              18,
                              weight: 700,
                              color: p.text,
                              letterSpacing: -0.3,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    if (listening)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                        child: Row(
                          children: [
                            HgEqualizer(
                              color: p.conference,
                              bars: 4,
                              height: 18,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _partial,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: HgType.sans(
                                  13,
                                  color: p.sub,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        // Kontrol barı — merkezde cam pill: Bitir.
        Padding(
          padding: const EdgeInsets.fromLTRB(Hg.pad, 10, Hg.pad, 12),
          child: Center(
            child: HgGlass(
              radius: 26,
              intensity: 84,
              padding: const EdgeInsets.all(9),
              child: HgPressable(
                onTap: _end,
                child: HgGlass(
                  radius: 20,
                  elevated: false,
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HgIcon(HgIcons.stop, size: 17, color: p.manual),
                      const SizedBox(width: 8),
                      Text(
                        'Bitir',
                        style: HgType.sans(14.5, weight: 700, color: p.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── done ──
  Widget _endedView(HgPalette p) {
    if (_endedSessionId == null) return _emptyEndedView(p);
    final mm = _elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(p),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HgResultTile(icon: HgIcons.check, accent: p.live),
                const SizedBox(height: 18),
                const HgSerifTitle('Konferans bitti'),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 20),
                  child: Text(
                    'Transkript kaydedildi · ses kaydı tutulmadı.',
                    style: HgType.sans(13.5, color: p.sub),
                  ),
                ),
                HgStatGlass(
                  stats: [
                    ('Süre', '$mm:$ss'),
                    ('Mesaj', '${_translations.length}'),
                    ('Dil', _langArrow),
                  ],
                ),
              ],
            ),
          ),
          HgGradientButton(
            label: 'Sonucu Aç',
            from: p.conference,
            icon: const HgIcon(
              HgIcons.sparkle,
              size: 17,
              color: Colors.white,
              strokeWidth: 1.8,
            ),
            onTap: _openDetail,
          ),
          const SizedBox(height: 10),
          HgGlassButton(
            label: 'Ana ekrana dön',
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Sonra "Konferanslarım" klasöründen de açabilirsin.',
              style: HgType.sans(12, color: p.faint),
            ),
          ),
        ],
      ),
    );
  }

  /// Hiç konuşma yakalanmadı → kayıt oluşturulmadı (Mehmet 2026-06-11).
  Widget _emptyEndedView(HgPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(p),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HgResultTile(
                  icon: HgIcons.mic,
                  accent: p.manual,
                  filled: false,
                ),
                const SizedBox(height: 18),
                const HgSerifTitle('Konuşma yakalanmadı', size: 28),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Boş oturum kaydedilmedi.',
                    style: HgType.sans(13.5, color: p.sub),
                  ),
                ),
              ],
            ),
          ),
          HgGradientButton(
            label: 'Ana ekrana dön',
            from: p.conference,
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
    );
  }

  // ── error ──
  Widget _errorView(HgPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(p),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HgResultTile(
                  icon: HgIcons.warning,
                  accent: p.manual,
                  filled: false,
                ),
                const SizedBox(height: 18),
                const HgSerifTitle('Ses motoru durdu', size: 28),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 20),
                  child: Text(
                    'Bir hata oluştu. Mikrofon iznini kontrol edip tekrar dene.',
                    style: HgType.sans(13.5, color: p.sub, height: 1.45),
                  ),
                ),
                HgWarnGlass(
                  icon: HgIcons.warning,
                  child: Text(
                    _error ?? 'Bilinmeyen hata',
                    style: HgType.sans(12.5, color: p.text, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          HgGradientButton(
            label: 'Tekrar dene',
            from: p.conference,
            icon: const HgIcon(
              HgIcons.refresh,
              size: 17,
              color: Colors.white,
              strokeWidth: 2.2,
            ),
            onTap: _checkModel,
          ),
          const SizedBox(height: 10),
          HgGlassButton(
            label: 'RAM\'i boşalt ve tekrar dene',
            onTap: () async {
              await RamManager.freeAll();
              if (mounted) await _checkModel();
            },
          ),
          const SizedBox(height: 10),
          HgGlassButton(
            label: 'Ana ekrana dön',
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
    );
  }

  static String _langName(String code) => switch (code) {
    'tr' => 'Türkçe',
    'en' => 'İngilizce',
    'es' => 'İspanyolca',
    'de' => 'Almanca',
    'fr' => 'Fransızca',
    _ => code,
  };
}
