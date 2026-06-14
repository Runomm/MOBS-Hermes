import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/engines/stt/dual_vosk_streaming_controller.dart';
import '../../core/engines/stt/whisper_langid_transcriber.dart';
import '../../core/engines/translation/google_mlkit_engine.dart';
import '../../core/engines/translation/nllb_translation_engine.dart';
import '../../core/engines/translation/translation_tier.dart';
import '../../core/engines/tts/native_tts_engine.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/services/ram_manager.dart';
import '../../core/session/smalltalk_streaming_session.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../conference/conference_detail_screen.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';
import '../shared/models_required_gate.dart';

/// Hands-free SmallTalk çalışan ekranı (S3) — liquid-glass `ConversationLive`
/// 5-faz akışı (gate → warmup → running → done → error; 2026-06-12 restyle).
///
/// Çift yönlü streaming: tek mic → iki Vosk tanıyıcı (master+local) → güven
/// skoruna göre yönlendirme ([SmallTalkStreamingSession]). Balonlar: master sağ
/// (accent tint), local sol (smalltalk tint); soluk orijinal + kalın çeviri +
/// hoparlör butonu. Altta sabit canlı partial barı (ekolayzer + ▍ + Bitir).
///
/// **Ses kanal yönlendirme (kulaklık↔hoparlör) DEFERRED** (Mehmet): TTS şimdilik
/// varsayılan çıkış; narration aktifse local çevirisi otomatik, master çevirisi
/// play ile.
class SmallTalkScreen extends StatefulWidget {
  const SmallTalkScreen({
    super.key,
    required this.masterLang,
    required this.localLang,
    required this.narrationEnabled,
    required this.quality,
  });

  final String masterLang;
  final String localLang;
  final bool narrationEnabled;

  /// 3 katman (Mehmet 2026-06-08): fast=Vosk×2+MLKit, full=Whisper+MLKit,
  /// full+=Whisper+NLLB. STT ve çeviri motoru [handsFreeUsesWhisper]/
  /// [handsFreeUsesNllb] ile seçilir.
  final SessionQuality quality;

  @override
  State<SmallTalkScreen> createState() => _SmallTalkScreenState();
}

/// STT motoru Whisper mı? (full + full+; fast→Vosk). Saf — test edilebilir.
bool handsFreeUsesWhisper(SessionQuality q) => q != SessionQuality.fast;

/// Çeviri motoru NLLB mi? (yalnız full+; fast/full→MLKit). Saf — test edilebilir.
bool handsFreeUsesNllb(SessionQuality q) => q == SessionQuality.fullPlus;

enum _Phase { checking, needsModels, warmup, running, ended, error }

class _SmallTalkScreenState extends State<SmallTalkScreen> {
  late final AppDatabase _db;
  late final ConversationRepository _repo;
  SmallTalkStreamingSession? _session;

  StreamSubscription<SmallTalkMessage>? _msgSub;
  StreamSubscription<String>? _partialSub;

  _Phase _phase = _Phase.checking;
  bool _warmingUp = true;
  String? _error;
  List<String> _missing = [];

  int? _endedSessionId;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;

  final List<SmallTalkMessage> _messages = [];
  String _partial = '';
  final ScrollController _scroll = ScrollController();

  bool get _usesWhisper => handsFreeUsesWhisper(widget.quality);
  bool get _usesNllb => handsFreeUsesNllb(widget.quality);

  @override
  void initState() {
    super.initState();
    _db = AppDatabase();
    _repo = ConversationRepository(_db);
    unawaited(_checkModels());
  }

  @override
  void dispose() {
    unawaited(_msgSub?.cancel());
    unawaited(_partialSub?.cancel());
    _scroll.dispose();
    // Önce session (end() → boş oturum silme), SONRA DB. Eskiden _db.close()
    // senkron çalışıp deleteSessionIfEmpty'yi boşa düşürüyordu (Mehmet 2026-06-13).
    final session = _session;
    unawaited(() async {
      await session?.dispose();
      await _db.close();
    }());
    super.dispose();
  }

  Future<void> _checkModels() async {
    setState(() => _phase = _Phase.checking);
    try {
      // STT: fast=Vosk×2, full/full+=Whisper. Çeviri: fast/full=MLKit, full+=NLLB.
      // İkisi de gerçekten hazır olmalı (MLKit "hep hazır" değil — dil paketi).
      final sttReady = _usesWhisper
          ? await WhisperLangIdTranscriber.whisperReady()
          : await DualVoskStreamingController.modelsReady(
              widget.masterLang,
              widget.localLang,
            );
      final tier = _usesNllb ? TranslationTier.nllb : TranslationTier.mlkit;
      final transReady = await isTierReady(
        tier,
        widget.masterLang,
        widget.localLang,
      );
      if (!mounted) return;
      if (sttReady && transReady) {
        await _warmUp();
        return;
      }
      // İndirme Ayarlar'da (Mehmet 2026-06-09) → eksik modelleri listele, yönlendir.
      final missing = <String>[];
      if (!sttReady) {
        if (_usesWhisper) {
          missing.add('Whisper small (~466MB)');
        } else {
          missing.add('Vosk ${_langName(widget.masterLang)}');
          missing.add('Vosk ${_langName(widget.localLang)}');
        }
      }
      if (!transReady) {
        missing.add(
          _usesNllb
              ? 'NLLB-600M (~1.3GB)'
              : 'ML Kit: ${_langName(widget.masterLang)} + '
                    '${_langName(widget.localLang)}',
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

  Future<void> _warmUp() async {
    setState(() {
      _phase = _Phase.warmup;
      _warmingUp = true;
    });
    try {
      // Temiz başlangıç: artakalan özet LLM'ini boşalt (NLLB resident kalır).
      await RamManager.freeForLiveSession();
      final DualTranscriber transcriber = _usesWhisper
          ? WhisperLangIdTranscriber(
              masterLang: widget.masterLang,
              localLang: widget.localLang,
            )
          : DualVoskStreamingController(
              masterLang: widget.masterLang,
              localLang: widget.localLang,
            );
      final session = SmallTalkStreamingSession(
        transcriber: transcriber,
        repository: _repo,
        // Canlı çeviri: full+=NLLB (offline NMT), fast/full=MLKit (anında). Tam
        // çeviri + özet oturum sonunda crunch'ta.
        translation: _usesNllb ? NllbTranslationEngine() : GoogleMLKitEngine(),
        tts: NativeOsTtsEngine(),
        masterLang: widget.masterLang,
        localLang: widget.localLang,
        narrationEnabled: widget.narrationEnabled,
        quality: widget.quality,
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
    _msgSub = session.messages.listen(_onMessage);
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

  void _onMessage(SmallTalkMessage m) {
    if (!mounted) return;
    setState(() => _messages.add(m));
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

  /// Crunch artık 2 adım (Derinlemesine Çevir + Özetle), detay ekranında.
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

  String get _langPair =>
      '${widget.localLang.toUpperCase()} ⇄ ${widget.masterLang.toUpperCase()}';

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
          child: ModelsRequiredGate(missing: _missing, onRecheck: _checkModels),
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
        title: 'SmallTalk',
        sub: '$_langPair · Eller serbest',
        label: label,
        dotColor: dot,
      ),
    );
  }

  Widget _spinner(HgPalette p) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: p.accent),
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
                icon: HgIcons.mic,
                label: warming ? 'Isınıyor…' : 'Başlat',
                warming: warming,
                onTap: _start,
              ),
              const SizedBox(height: 26),
              HgSerifTitle(
                warming ? 'Motor ısınıyor' : 'Konuşmaya hazır',
                size: 24,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 6, 40, 0),
                child: Text(
                  'Daireye dokun, ikiniz de doğal şekilde konuşun. '
                  'Çeviri otomatik seslendirilir.'
                  '${widget.narrationEnabled ? ' (🎧 seslendirme açık)' : ''}',
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
    return Column(
      children: [
        _topBar(p, label: 'Canlı', dot: p.live),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    'Dinleniyor…',
                    style: HgType.sans(15, color: p.faint),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) => _bubble(p, _messages[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Hg.pad, 8, Hg.pad, 12),
          child: _partialBar(p),
        ),
      ],
    );
  }

  /// ConvBubble: master sağ (accent), local sol (smalltalk yeşili).
  /// Soluk orijinal üstte, kalın çeviri altta — master kendi dilini görür
  /// (transkript), local'in söylediğinin çevirisini görür.
  Widget _bubble(HgPalette p, SmallTalkMessage m) {
    final isMaster = m.isMaster;
    final ac = isMaster ? p.accent : p.smalltalk;
    final big = isMaster ? m.transcript : m.translation;
    final small = isMaster ? m.translation : m.transcript;
    return Align(
      alignment: isMaster ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: HgGlass(
          radius: 20,
          tint: ac,
          tintStrength: 0.6,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMaster
                    ? 'SEN · ${widget.masterLang.toUpperCase()}'
                    : 'KARŞI · ${widget.localLang.toUpperCase()}',
                style: HgType.sans(
                  10,
                  weight: 700,
                  color: ac,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(small, style: HgType.sans(12.5, color: p.faint)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      big,
                      style: HgType.sans(
                        17,
                        weight: 700,
                        color: p.text,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  HgPressable(
                    onTap: () => _session?.playMessage(m),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: ac.withValues(alpha: p.noir ? 0.3 : 0.16),
                      ),
                      child: Center(
                        child: HgIcon(
                          HgIcons.speaker,
                          size: 16,
                          color: ac,
                          strokeWidth: 1.9,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sabit canlı satır: ekolayzer + partial + ▍ + Bitir.
  Widget _partialBar(HgPalette p) {
    final listening = _partial.trim().isNotEmpty;
    return HgGlass(
      radius: 20,
      intensity: 84,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          HgEqualizer(color: p.accent, running: listening),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listening ? 'DİNLENİYOR' : 'BEKLENİYOR',
                  style: HgType.sans(
                    10.5,
                    weight: 700,
                    color: p.faint,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: listening ? _partial : 'Konuşun…',
                        style: HgType.sans(14.5, weight: 500, color: p.text),
                      ),
                      TextSpan(
                        text: '▍',
                        style: HgType.sans(14.5, weight: 700, color: p.accent),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          HgPressable(
            onTap: _end,
            child: HgGlass(
              radius: 14,
              elevated: false,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HgIcon(HgIcons.stop, size: 15, color: p.manual),
                  const SizedBox(width: 7),
                  Text(
                    'Bitir',
                    style: HgType.sans(13.5, weight: 700, color: p.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                const HgSerifTitle('Konuşma bitti'),
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
                    ('Mesaj', '${_messages.length}'),
                    ('Diller', _langPair),
                  ],
                ),
              ],
            ),
          ),
          HgGradientButton(
            label: 'Sonucu Aç',
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
            icon: const HgIcon(
              HgIcons.refresh,
              size: 17,
              color: Colors.white,
              strokeWidth: 2.2,
            ),
            onTap: _checkModels,
          ),
          const SizedBox(height: 10),
          HgGlassButton(
            label: 'RAM\'i boşalt ve tekrar dene',
            onTap: () async {
              await RamManager.freeAll();
              if (mounted) await _checkModels();
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
