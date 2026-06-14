import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/services/title_generator.dart';

/// Step 5 cihaz testi — gerçek SQLite (Drift + sqlite3_flutter_libs) Poco
/// X3 Pro üzerinde dosya açabiliyor mu, oturum/mesaj yazıp okuyabiliyor mu
/// doğrulamak için izole test ekranı.
///
/// Faz 1 sonrası kaldırılabilir. Step 6 `ConversationSessionManager` aynı
/// repository'i sarınca prod akışı oluşur.
class DbTestScreen extends StatefulWidget {
  const DbTestScreen({super.key});

  @override
  State<DbTestScreen> createState() => _DbTestScreenState();
}

class _DbTestScreenState extends State<DbTestScreen> {
  late final AppDatabase _db;
  late final ConversationRepository _repo;

  /// Cihazda açılan SQLite dosyasının ortaya çıkardığı oturumlar.
  List<SessionRow> _sessions = const [];
  Map<int, List<MessageRow>> _messagesBySession = const {};

  /// Yeni mesajların hangi oturuma ekleneceği (varsayılan: en son açılan).
  int? _activeSessionId;

  String _status = 'Hazır';

  // Demo mesajları (Türkçe ↔ İngilizce).
  static const List<_DemoPair> _demoMessages = [
    _DemoPair(
      lang: 'tr',
      source: 'Merhaba, nasılsın?',
      translated: 'Hello, how are you?',
    ),
    _DemoPair(
      lang: 'en',
      source: 'I am fine, thank you.',
      translated: 'İyiyim, teşekkür ederim.',
    ),
    _DemoPair(
      lang: 'tr',
      source: 'İki kahve lütfen.',
      translated: 'Two coffees please.',
    ),
  ];

  int _demoIndex = 0;

  @override
  void initState() {
    super.initState();
    _db = AppDatabase();
    _repo = ConversationRepository(_db);
    _refresh();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final sessions = await _repo.listAllSessions();
      final byId = <int, List<MessageRow>>{};
      for (final s in sessions) {
        byId[s.id] = await _repo.listMessagesForSession(s.id);
      }
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _messagesBySession = byId;
        _activeSessionId ??= sessions.isNotEmpty ? sessions.first.id : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Listeleme hatası: $e');
    }
  }

  Future<void> _createSession() async {
    try {
      final session = await _repo.createSession(
        mode: SessionMode.voiceTranslator,
        quality: SessionQuality.fast,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );
      if (!mounted) return;
      setState(() {
        _activeSessionId = session.id;
        _status = 'Oturum #${session.id} açıldı.';
        _demoIndex = 0;
      });
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Oturum açma hatası: $e');
    }
  }

  Future<void> _appendMessage() async {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      setState(() => _status = 'Önce oturum aç.');
      return;
    }
    final demo = _demoMessages[_demoIndex % _demoMessages.length];
    try {
      final msg = await _repo.appendMessage(
        sessionId: sessionId,
        speakerLanguage: demo.lang,
        sourceText: demo.source,
        translatedText: demo.translated,
      );
      _demoIndex++;
      if (!mounted) return;
      setState(
        () => _status = 'Mesaj #${msg.id} → oturum #$sessionId (${demo.lang}).',
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Mesaj ekleme hatası: $e');
    }
  }

  Future<void> _endActiveSession() async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    try {
      // 6r-f/g: Manager.end() ile aynı akış — başlık üret + yaz, sonra kapat.
      final session = await _repo.getSession(sessionId);
      final messages = await _repo.listMessagesForSession(sessionId);
      final title = await const TimestampFallbackGenerator().generate(
        mode: SessionMode.fromDbValue(session?.mode ?? 'pushToTalk'),
        messages: messages,
        startedAt: session?.startedAt ?? DateTime.now(),
      );
      await _repo.setTitle(sessionId, title);
      await _repo.endSession(sessionId);
      if (!mounted) return;
      setState(() => _status = 'Oturum #$sessionId kapatıldı · "$title"');
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Kapatma hatası: $e');
    }
  }

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DB Test (Drift + SQLite)'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _createSession,
                  icon: const Icon(Icons.add),
                  label: const Text('Oturum Aç'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _appendMessage,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Mesaj Ekle'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _endActiveSession,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Oturumu Kapat'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB0B0B0)),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _sessions.isEmpty
                  ? const Center(
                      child: Text(
                        '(henüz oturum yok — "Oturum Aç" ile başla)',
                        style: TextStyle(color: Color(0xFF707070)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (context, i) {
                        final s = _sessions[i];
                        final msgs = _messagesBySession[s.id] ?? const [];
                        return _SessionCard(
                          session: s,
                          messages: msgs,
                          isActive: s.id == _activeSessionId,
                          formatTime: _fmt,
                          onTap: () => setState(() => _activeSessionId = s.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoPair {
  const _DemoPair({
    required this.lang,
    required this.source,
    required this.translated,
  });

  final String lang;
  final String source;
  final String translated;
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.messages,
    required this.isActive,
    required this.formatTime,
    required this.onTap,
  });

  final SessionRow session;
  final List<MessageRow> messages;
  final bool isActive;
  final String Function(DateTime) formatTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isActive ? const Color(0xFF2A2440) : const Color(0xFF1A1A1A),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${session.id}',
                    style: const TextStyle(
                      color: Color(0xFF7C6FE0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${session.sourceLanguage} ↔ ${session.targetLanguage} · '
                    '${session.mode}/${session.quality}',
                    style: const TextStyle(color: Color(0xFFD0D0D0)),
                  ),
                  const Spacer(),
                  Text(
                    session.endedAt == null
                        ? 'açık'
                        : 'kapalı ${formatTime(session.endedAt!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: session.endedAt == null
                          ? Colors.greenAccent.shade400
                          : const Color(0xFF808080),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                // 6r-g: başlık (kapanışta üretilir; açık oturumda henüz null).
                session.title ?? '(başlık yok — oturumu kapat)',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: session.title == null
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: session.title == null
                      ? const Color(0xFF707070)
                      : const Color(0xFFE0D8B0),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'başladı: ${formatTime(session.startedAt)} · '
                '${messages.length} mesaj',
                style: const TextStyle(fontSize: 11, color: Color(0xFF808080)),
              ),
              if (messages.isNotEmpty) ...[
                const Divider(color: Color(0xFF303030), height: 16),
                ...messages.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            m.speakerLanguage,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFB0B0B0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.sourceText,
                                style: const TextStyle(
                                  color: Color(0xFFF0F0F0),
                                  fontSize: 13,
                                ),
                              ),
                              if (m.translatedText != null)
                                Text(
                                  '→ ${m.translatedText}',
                                  style: const TextStyle(
                                    color: Color(0xFF909090),
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
