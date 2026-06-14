import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio/audio_input.dart';
import '../../core/audio/push_to_talk_audio_input.dart';
import '../../core/database/app_database.dart';
import '../../core/engines/stt/hybrid_stt_engine.dart';
import '../../core/engines/translation/translation_tier.dart';
import '../../core/engines/tts/native_tts_engine.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/services/ram_manager.dart';
import '../../core/session/conversation_session_manager.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../conference/conference_detail_screen.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';

/// Bas Konuş — SmallTalk'ın alt-modu (Step 7 burst-2 + S2 SmallTalk sarmalı).
///
/// **UI (Mehmet kararı 2026-06-05): eski bölünmüş 180° ekran KORUNUR; liquid-glass
/// restyle 2026-06-12, hand-off §SmallTalkSplit.** Ekran ortadan yatay ikiye
/// bölünür; üst yarı 180° dönük (karşı taraf okur); her yarı görünmez bas-konuş
/// alanı; çeviri karşı tarafa yazılır; turn-based. Aksan = `smalltalk` (yeşil).
///
/// **S2 SmallTalk yaşam döngüsü:** Konferans'taki gibi **warmup** (motor ısıtma)
/// → **running** (split UI) → **ended** (sonucu aç/sonra). Oturum
/// `mode=pushToTalk` ile kaydedilir → SmallTalk klasöründe (arşiv ikisini gösterir),
/// `runConferenceCrunch` mod-bağımsız çalışır (DB `sourceText`'ten).
class PushToTalkScreen extends StatefulWidget {
  const PushToTalkScreen({
    super.key,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.tier = TranslationTier.mlkit,
    this.hfToken,
  });

  final String sourceLanguage;
  final String targetLanguage;
  final TranslationTier tier;
  final String? hfToken;

  @override
  State<PushToTalkScreen> createState() => _PushToTalkScreenState();
}

enum _Phase { warmup, running, ended, error }

class _PushToTalkScreenState extends State<PushToTalkScreen> {
  late final AppDatabase _db;
  late final ConversationRepository _repo;

  PushToTalkAudioInput? _input;
  ConversationSessionManager? _manager;
  HybridSttEngine? _stt;
  StreamSubscription<ConversationEvent>? _eventSub;
  StreamSubscription<ConversationState>? _stateSub;

  _Phase _phase = _Phase.warmup;
  bool _warmingUp = true;
  String? _error;
  AudioSource? _recordingSource;
  ConversationState _state = ConversationState.idle;

  int? _endedSessionId;

  /// DEV overlay için son drop/hata teknik detayı (release'de gizli).
  String? _devTech;

  /// Aynı anda birden çok hata dialog'u açılmasın.
  bool _dialogOpen = false;

  final List<_Entry> _entries = [];

  String get _langPair =>
      '${widget.sourceLanguage.toUpperCase()} ⇄ '
      '${widget.targetLanguage.toUpperCase()}';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _db = AppDatabase();
    _repo = ConversationRepository(_db);
    _warmUp();
  }

  /// Motorları arka planda yükle (kullanıcı "Başlat"a basana kadar).
  Future<void> _warmUp() async {
    try {
      // Temiz başlangıç: artakalan özet LLM'ini boşalt (NLLB resident kalır).
      await RamManager.freeForLiveSession();
      final input = PushToTalkAudioInput();
      final stt = HybridSttEngine();
      final manager = ConversationSessionManager(
        audioInput: input,
        stt: stt,
        translation: createTranslationEngine(
          widget.tier,
          hfToken: widget.hfToken,
        ),
        tts: NativeOsTtsEngine(),
        repository: _repo,
        sourceLanguage: widget.sourceLanguage,
        targetLanguage: widget.targetLanguage,
        mode: SessionMode.pushToTalk,
      );
      await manager.prepare();
      if (!mounted) {
        unawaited(manager.dispose());
        return;
      }
      _input = input;
      _manager = manager;
      _stt = stt;
      setState(() => _warmingUp = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '$e';
      });
    }
  }

  Future<void> _start() async {
    final manager = _manager;
    if (manager == null || _warmingUp) return;
    _eventSub = manager.eventStream.listen(_onEvent);
    _stateSub = manager.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    try {
      await manager.start();
      if (!mounted) return;
      setState(() => _phase = _Phase.running);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    unawaited(_eventSub?.cancel());
    unawaited(_stateSub?.cancel());
    // Önce manager (end() → boş oturum silme), SONRA DB. Eskiden _db.close()
    // senkron çalışıp deleteSessionIfEmpty'yi boşa düşürüyordu (Mehmet 2026-06-13).
    final manager = _manager;
    unawaited(() async {
      await manager?.dispose();
      await _db.close();
    }());
    super.dispose();
  }

  void _onEvent(ConversationEvent event) {
    if (!mounted) return;
    if (event is ConversationMessageAdded) {
      setState(() {
        _entries.add(
          _Entry(
            participant: event.participant,
            sourceText: event.message.sourceText,
            translatedText: event.message.translatedText ?? '…',
          ),
        );
      });
    } else if (event is ConversationErrorEvent) {
      // Teknik detay yalnız DEV overlay'e; kullanıcıya sade, kapatılabilir mesaj.
      setState(() => _devTech = 'ERR: ${event.message}');
      _showUserError('Çeviri tamamlanamadı. Lütfen tekrar deneyin.');
    } else if (event is ConversationDropped) {
      setState(() => _devTech = 'DROP: ${event.reason}');
      _showUserError(_friendlyDrop(event.reason));
    }
  }

  /// Drop sebebini son kullanıcıya uygun dile çevir (motor adı sızdırmadan).
  String _friendlyDrop(String reason) {
    if (reason.contains('algılan') || reason.contains('konuşma')) {
      return 'Ses algılanamadı. Lütfen butona basılı tutarken konuşun.';
    }
    return reason;
  }

  /// Kullanıcıya hitap eden hatayı **kapatılabilir** (Tamam butonlu) dialog ile
  /// göster — ekranda kalıcı yer kaplamasın (Mehmet 2026-06-06).
  void _showUserError(String message) {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;
    final p = HgPalette.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        contentPadding: EdgeInsets.zero,
        content: HgGlass(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message,
                style: HgType.sans(15, color: p.text, height: 1.4),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: HgPressable(
                  onTap: () => Navigator.pop(ctx),
                  child: HgGlass(
                    radius: 13,
                    elevated: false,
                    tint: p.smalltalk,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    child: Text(
                      'Tamam',
                      style: HgType.sans(14, weight: 700, color: p.text),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _dialogOpen = false);
  }

  void _press(AudioSource source) {
    final input = _input;
    if (input == null || _recordingSource != null) return;
    setState(() => _recordingSource = source);
    unawaited(input.pressTalk(source));
  }

  void _release() {
    final input = _input;
    if (input == null || _recordingSource == null) return;
    setState(() => _recordingSource = null);
    unawaited(input.releaseTalk());
  }

  Future<void> _end() async {
    // end() boş transkriptli oturumu siler → null döner (kaydedilmedi).
    _endedSessionId = await _manager?.end();
    if (!mounted) return;
    setState(() => _phase = _Phase.ended);
  }

  /// Crunch artık 2 adım (Daha İyi Çevir + Özetle), detay ekranında.
  void _openDetail() {
    final id = _endedSessionId;
    if (id == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ConferenceDetailScreen(sessionId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return HgScreen(
      scroll: false,
      padded: false,
      child: switch (_phase) {
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
        title: 'Bas Konuş',
        sub: '$_langPair · SmallTalk',
        label: label,
        dotColor: dot,
      ),
    );
  }

  // ---- Isınma ----

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
                accent: p.smalltalk,
              ),
              const SizedBox(height: 26),
              HgSerifTitle(
                warming ? 'Motor ısınıyor' : 'Bas Konuş hazır',
                size: 24,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 6, 40, 0),
                child: Text(
                  'Telefonu ikinizin arasına koy. Konuşmak için kendi '
                  'yarına basılı tut; karşı taraf üstteki (dönük) yarıyı kullanır.',
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

  // ---- Çalışan (split UI) ----

  Widget _runningView(HgPalette p) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: RotatedBox(
                quarterTurns: 2,
                child: _Half(
                  side: AudioSource.secondary,
                  language: widget.targetLanguage,
                  entries: _entries,
                  recording: _recordingSource == AudioSource.secondary,
                  locked: _recordingSource == AudioSource.primary,
                  onPress: () => _press(AudioSource.secondary),
                  onRelease: _release,
                ),
              ),
            ),
            Expanded(
              child: _Half(
                side: AudioSource.primary,
                language: widget.sourceLanguage,
                entries: _entries,
                recording: _recordingSource == AudioSource.primary,
                locked: _recordingSource == AudioSource.secondary,
                onPress: () => _press(AudioSource.primary),
                onRelease: _release,
              ),
            ),
          ],
        ),
        // Orta cam pill (hand-off divider): hairline + "SmallTalk · pair" + Bitir.
        Align(alignment: Alignment.center, child: _centerPill(p)),
        if (kPttDevOverlay && _stt != null) _devOverlay(_stt!),
      ],
    );
  }

  /// DEV bilgi şeridi — release'de [kPttDevOverlay]=false ile kapanır.
  Widget _devOverlay(HybridSttEngine stt) {
    return Positioned(
      top: 2,
      left: 8,
      right: 8,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xCC101010),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: ValueListenableBuilder<String>(
              valueListenable: stt.activeBackend,
              builder: (_, backend, _) => Text(
                'DEV · STT: $backend · Çeviri: ${widget.tier.label} '
                '($_tierModelName) · TTS: Native · '
                '${widget.sourceLanguage}→${widget.targetLanguage}'
                '${_devTech != null ? '\n${_devTech!}' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8FE0A8), fontSize: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// DEV overlay'de gösterilecek çeviri model adı (katmandan türetilir).
  String get _tierModelName => switch (widget.tier) {
    TranslationTier.mlkit => 'ML Kit',
    TranslationTier.nllb => 'NLLB-600M',
    TranslationTier.gemma => 'Gemma3-1B-IT',
    TranslationTier.qwen => 'Qwen2.5-1.5B',
  };

  Widget _centerPill(HgPalette p) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Hairline ayraç (hand-off: ekranı ortadan bölen ince çizgi).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(height: 1, color: p.hairline),
        ),
        HgGlass(
          radius: 16,
          elevated: false,
          intensity: 86,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HgPressable(
                onTap: _end,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: HgIcon(
                    HgIcons.stop,
                    size: 17,
                    color: p.manual,
                    strokeWidth: 2,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              HgDot(color: p.smalltalk),
              const SizedBox(width: 7),
              Text(
                'SmallTalk · $_langPair',
                style: HgType.sans(12.5, weight: 700, color: p.text),
              ),
              if (_busy) ...[
                const SizedBox(width: 9),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(p.smalltalk),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---- Bitti — sonuç ----

  Widget _endedView(HgPalette p) {
    // Boş transkript → oturum silindi, kaydedilmedi (Mehmet 2026-06-11).
    if (_endedSessionId == null) return _emptyEndedView(p);
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
                const HgSerifTitle('Konuşma kaydedildi'),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Tam çeviri + özet + başlık çıkarmak ister misin?',
                    style: HgType.sans(13.5, color: p.sub, height: 1.45),
                  ),
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
            label: 'Sonra',
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
    );
  }

  /// Hiç konuşma yakalanmadı → kayıt oluşturulmadı.
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
                const HgSerifTitle('Bas Konuş başlatılamadı', size: 28),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 20),
                  child: Text(
                    'Bir hata oluştu. Mikrofon iznini kontrol edip tekrar dene.',
                    style: HgType.sans(13.5, color: p.sub, height: 1.45),
                  ),
                ),
                if (kPttDevOverlay && _error != null)
                  HgWarnGlass(
                    icon: HgIcons.warning,
                    child: Text(
                      'DEV: $_error',
                      style: HgType.sans(12.5, color: p.text, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
          HgGradientButton(
            label: 'RAM\'i boşalt ve tekrar dene',
            onTap: () async {
              await RamManager.freeAll();
              if (!mounted) return;
              setState(() {
                _phase = _Phase.warmup;
                _warmingUp = true;
                _error = null;
              });
              await _warmUp();
            },
          ),
          const SizedBox(height: 10),
          HgGlassButton(
            label: 'Geri',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  bool get _busy => switch (_state) {
    ConversationState.transcribing => true,
    ConversationState.translating => true,
    ConversationState.speaking => true,
    _ => false,
  };
}

class _Entry {
  const _Entry({
    required this.participant,
    required this.sourceText,
    required this.translatedText,
  });

  final ConversationParticipant participant;
  final String sourceText;
  final String translatedText;
}

/// **DEV — release'de `false` yap / kaldır.** Bas Konuş çalışırken aktif STT
/// motoru/modeli + çeviri katmanı/modeli + son drop/hata teknik detayını ekrana
/// basar (Mehmet 2026-06-06: "hangi motor/model kullanılıyor görünsün, ama
/// release'de kaldıralım"). Son kullanıcıya gösterilmemeli. Bkz RELEASE_CHECKLIST.
const bool kPttDevOverlay = true;

/// Bir ekran yarısı — tüm alan görünmez bas-konuş + bu tarafın okunur chat'i
/// (hand-off §STHalf: cam balonlar + altta mic ipucu).
class _Half extends StatelessWidget {
  const _Half({
    required this.side,
    required this.language,
    required this.entries,
    required this.recording,
    required this.locked,
    required this.onPress,
    required this.onRelease,
  });

  final AudioSource side;
  final String language;
  final List<_Entry> entries;
  final bool recording;
  final bool locked;
  final VoidCallback onPress;
  final VoidCallback onRelease;

  ConversationParticipant get _owner => side == AudioSource.primary
      ? ConversationParticipant.sourceSpeaker
      : ConversationParticipant.targetSpeaker;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final ac = p.smalltalk;
    return Listener(
      onPointerDown: locked ? null : (_) => onPress(),
      onPointerUp: (_) => onRelease(),
      onPointerCancel: (_) => onRelease(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        color: recording
            ? ac.withValues(alpha: p.noir ? 0.14 : 0.10)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Stack(
          children: [
            Positioned.fill(child: _chat(p, ac)),
            if (recording) Positioned.fill(child: _RecordingOverlay(ac: ac)),
            if (!recording)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(child: _hint(p, ac)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hint(HgPalette p, Color ac) {
    return Opacity(
      opacity: 0.85,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HgGlass(
            radius: 20,
            elevated: false,
            width: 40,
            height: 40,
            child: Center(
              child: HgIcon(HgIcons.mic, size: 20, color: ac, strokeWidth: 1.9),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Basılı tut, konuş ($language)',
            style: HgType.sans(12.5, weight: 600, color: p.sub),
          ),
        ],
      ),
    );
  }

  Widget _chat(HgPalette p, Color ac) {
    final lines = <Widget>[];
    final recent = entries.length > 5
        ? entries.sublist(entries.length - 5)
        : entries;
    for (final e in recent) {
      final isOwn = e.participant == _owner;
      lines.add(
        _bubble(
          p,
          ac,
          text: isOwn ? e.sourceText : e.translatedText,
          isOwn: isOwn,
        ),
      );
    }
    return SingleChildScrollView(
      reverse: true,
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      ),
    );
  }

  Widget _bubble(
    HgPalette p,
    Color ac, {
    required String text,
    required bool isOwn,
  }) {
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 270),
        child: HgGlass(
          radius: 18,
          tint: ac,
          tintStrength: isOwn ? 0.7 : 0.4,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Text(
            text,
            style: HgType.sans(15.5, weight: 600, color: p.text, height: 1.3),
          ),
        ),
      ),
    );
  }
}

class _RecordingOverlay extends StatelessWidget {
  const _RecordingOverlay({required this.ac});

  final Color ac;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HgIcon(HgIcons.mic, color: ac, size: 40, strokeWidth: 2),
          const SizedBox(height: 8),
          Text('konuş…', style: HgType.sans(15, weight: 700, color: ac)),
        ],
      ),
    );
  }
}
