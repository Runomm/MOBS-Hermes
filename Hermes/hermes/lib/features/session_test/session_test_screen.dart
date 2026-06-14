import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/audio_input.dart';
import '../../core/audio/push_to_talk_audio_input.dart';
import '../../core/database/app_database.dart';
import '../../core/engines/stt/hybrid_stt_engine.dart';
import '../../core/engines/translation/google_mlkit_engine.dart';
import '../../core/engines/tts/native_tts_engine.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/session/conversation_session_manager.dart';

/// 6r-h — Manager tam pipeline entegrasyon cihaz testi (throwaway harness).
///
/// Gerçek `ConversationSessionManager`'ı gerçek motorlarla sürer:
/// bas-konuş (PushToTalkAudioInput) → Whisper → FillerClean → MLKit çeviri →
/// NativeTTS sesli → Drift'e mesaj → kapanışta TitleGenerator başlık.
/// Amaç: uçtan uca akışı Step 7 UI yatırımından önce cihazda görmek.
///
/// Bas Konuş mode + çift yönlü: alt yarı = primary (kaynak dil), üst yarı =
/// secondary (hedef dil). Manager `event.source`'a göre yön çevirir.
class SessionTestScreen extends StatefulWidget {
  const SessionTestScreen({super.key});

  @override
  State<SessionTestScreen> createState() => _SessionTestScreenState();
}

class _SessionTestScreenState extends State<SessionTestScreen> {
  late final AppDatabase _db;
  late final ConversationRepository _repo;

  PushToTalkAudioInput? _input;
  ConversationSessionManager? _manager;
  StreamSubscription<ConversationState>? _stateSub;
  StreamSubscription<ConversationEvent>? _eventSub;

  String _sourceLang = 'tr';
  String _targetLang = 'en';

  bool _started = false;
  bool _busy = false;
  AudioSource? _recordingSource;
  ConversationState _state = ConversationState.idle;

  final List<_ChatLine> _chat = [];
  String _status = 'Dil çiftini seç, Başlat.';

  @override
  void initState() {
    super.initState();
    _db = AppDatabase();
    _repo = ConversationRepository(_db);
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    unawaited(_eventSub?.cancel());
    unawaited(_manager?.dispose());
    _db.close();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _status = 'Motorlar hazırlanıyor (Whisper + çeviri modeli)…';
    });
    try {
      final input = PushToTalkAudioInput();
      final manager = ConversationSessionManager(
        audioInput: input,
        stt: HybridSttEngine(),
        translation: GoogleMLKitEngine(),
        tts: NativeOsTtsEngine(),
        repository: _repo,
        sourceLanguage: _sourceLang,
        targetLanguage: _targetLang,
        mode: SessionMode.pushToTalk,
      );
      _stateSub = manager.stateStream.listen((s) {
        if (mounted) setState(() => _state = s);
      });
      _eventSub = manager.eventStream.listen(_onEvent);
      await manager.start();
      if (!mounted) return;
      setState(() {
        _input = input;
        _manager = manager;
        _started = true;
        _busy = false;
        _status = 'Hazır. Bir yarıyı basılı tut, konuş, bırak.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Başlatma hatası: $e';
      });
    }
  }

  Future<void> _finish() async {
    final manager = _manager;
    if (manager == null) return;
    setState(() {
      _busy = true;
      _status = 'Oturum kapatılıyor (başlık üretiliyor)…';
    });
    final sessionId = manager.activeSessionId;
    await manager.end();
    final session = sessionId == null
        ? null
        : await _repo.getSession(sessionId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _started = false;
      _recordingSource = null;
      _status = session?.title != null
          ? 'Kapandı. Başlık: "${session!.title}"'
          : 'Kapandı.';
    });
  }

  void _onEvent(ConversationEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case ConversationMessageAdded(:final message, :final participant):
          _chat.add(
            _ChatLine(
              participant: participant,
              sourceText: message.sourceText,
              translatedText: message.translatedText ?? '(çeviri yok)',
            ),
          );
        case ConversationDropped(:final reason):
          _status = 'Atlandı: $reason';
        case ConversationErrorEvent(:final message):
          _status = 'Hata: $message';
      }
    });
  }

  void _press(AudioSource source) {
    final input = _input;
    if (input == null || _recordingSource != null || _busy) return;
    setState(() => _recordingSource = source);
    unawaited(input.pressTalk(source));
  }

  void _release() {
    final input = _input;
    if (input == null || _recordingSource == null) return;
    setState(() => _recordingSource = null);
    unawaited(input.releaseTalk());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Oturum Entegrasyon — 6r-h'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _controlBar(),
            const SizedBox(height: 8),
            Expanded(child: _chatList()),
            const SizedBox(height: 8),
            if (_started) _talkButtons(),
            const SizedBox(height: 8),
            Text(
              'durum: ${_stateLabel(_state)}  ·  $_status',
              style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlBar() {
    return Row(
      children: [
        _langDropdown(
          'Kaynak',
          _sourceLang,
          _started,
          (v) => setState(() => _sourceLang = v),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.swap_horiz, color: Color(0xFF707070), size: 18),
        const SizedBox(width: 8),
        _langDropdown(
          'Hedef',
          _targetLang,
          _started,
          (v) => setState(() => _targetLang = v),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : _started
              ? _finish
              : _start,
          icon: Icon(_started ? Icons.stop : Icons.play_arrow),
          label: Text(_started ? 'Bitir' : 'Başlat'),
          style: FilledButton.styleFrom(
            backgroundColor: _started ? Colors.red.shade900 : null,
          ),
        ),
      ],
    );
  }

  Widget _chatList() {
    if (_chat.isEmpty) {
      return const Center(
        child: Text('(mesaj yok)', style: TextStyle(color: Color(0xFF606060))),
      );
    }
    return ListView.builder(
      itemCount: _chat.length,
      itemBuilder: (context, i) {
        final line = _chat[i];
        final isSource =
            line.participant == ConversationParticipant.sourceSpeaker;
        return Align(
          alignment: isSource ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: isSource
                  ? const Color(0xFF2A2440)
                  : const Color(0xFF13331F),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.sourceText,
                  style: const TextStyle(
                    color: Color(0xFFF0F0F0),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '→ ${line.translatedText}',
                  style: const TextStyle(
                    color: Color(0xFFA8A8A8),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _talkButtons() {
    return Row(
      children: [
        Expanded(
          child: _TalkButton(
            label: 'KAYNAK ($_sourceLang)',
            active: _recordingSource == AudioSource.primary,
            color: const Color(0xFF7C6FE0),
            onPress: () => _press(AudioSource.primary),
            onRelease: _release,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TalkButton(
            label: 'HEDEF ($_targetLang)',
            active: _recordingSource == AudioSource.secondary,
            color: const Color(0xFF50C878),
            onPress: () => _press(AudioSource.secondary),
            onRelease: _release,
          ),
        ),
      ],
    );
  }

  Widget _langDropdown(
    String label,
    String value,
    bool disabled,
    ValueChanged<String> onCh,
  ) {
    const langs = {'tr': 'TR', 'en': 'EN', 'es': 'ES'};
    return DropdownButton<String>(
      value: value,
      dropdownColor: const Color(0xFF1A1A1A),
      underline: const SizedBox.shrink(),
      style: const TextStyle(color: Color(0xFF7C6FE0), fontSize: 14),
      onChanged: disabled
          ? null
          : (v) {
              if (v != null) onCh(v);
            },
      items: [
        for (final e in langs.entries)
          DropdownMenuItem(value: e.key, child: Text('$label: ${e.value}')),
      ],
    );
  }

  String _stateLabel(ConversationState s) => switch (s) {
    ConversationState.idle => 'boşta',
    ConversationState.listening => 'dinliyor',
    ConversationState.transcribing => 'transkript',
    ConversationState.translating => 'çeviriyor',
    ConversationState.speaking => 'konuşuyor',
    ConversationState.paused => 'duraklatıldı',
    ConversationState.ending => 'kapanıyor',
    ConversationState.error => 'hata',
  };
}

class _ChatLine {
  const _ChatLine({
    required this.participant,
    required this.sourceText,
    required this.translatedText,
  });

  final ConversationParticipant participant;
  final String sourceText;
  final String translatedText;
}

class _TalkButton extends StatelessWidget {
  const _TalkButton({
    required this.label,
    required this.active,
    required this.color,
    required this.onPress,
    required this.onRelease,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onPress;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPress(),
      onPointerUp: (_) => onRelease(),
      onPointerCancel: (_) => onRelease(),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.25)
              : const Color(0xFF161616),
          border: Border.all(
            color: active ? color : const Color(0xFF2A2A2A),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? Icons.mic : Icons.mic_none,
              color: active ? color : const Color(0xFF707070),
              size: 30,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? color : const Color(0xFFC0C0C0),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
