import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../conference/conference_detail_screen.dart';
import '../conference/conference_format.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';

/// SmallTalk arşivi / klasörü (S1) — liquid-glass `ArchiveScreen` stili
/// (2026-06-12 restyle). Hem **hands-free** (`voiceTranslator`) hem **bas
/// konuş** (`pushToTalk`) kayıtlarını tek listede gösterir. Crunch/detay
/// ekranları Konferans'la ortak (mod-bağımsız).
class SmallTalkArchiveScreen extends StatefulWidget {
  const SmallTalkArchiveScreen({super.key});

  @override
  State<SmallTalkArchiveScreen> createState() => _SmallTalkArchiveScreenState();
}

class _SmallTalkArchiveScreenState extends State<SmallTalkArchiveScreen> {
  late final AppDatabase _db;
  late final ConversationRepository _repo;

  List<SessionRow> _sessions = const [];
  bool _loading = true;

  static const _modes = [SessionMode.voiceTranslator, SessionMode.pushToTalk];

  @override
  void initState() {
    super.initState();
    _db = AppDatabase();
    _repo = ConversationRepository(_db);
    _load();
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Future<void> _load() async {
    final sessions = await _repo.listSessionsForModes(_modes);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  Future<void> _open(SessionRow s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConferenceDetailScreen(sessionId: s.id),
      ),
    );
    // Detaydan dönünce crunch durumu değişmiş olabilir → yenile.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return HgScreen(
      scroll: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HgNavHeader(
            title: 'SmallTalk\'larım',
            sub: '${_sessions.length} kayıt',
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: p.smalltalk))
                : _sessions.isEmpty
                ? _empty(p)
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                    itemCount: _sessions.length,
                    itemBuilder: (context, i) => _row(p, _sessions[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(HgPalette p) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HgIcon(HgIcons.folder, size: 44, color: p.faint, strokeWidth: 1.5),
          const SizedBox(height: 12),
          Text(
            'Henüz SmallTalk kaydı yok.',
            style: HgType.sans(14, color: p.sub),
          ),
        ],
      ),
    );
  }

  Widget _row(HgPalette p, SessionRow s) {
    final crunched = s.crunchedAt != null;
    final date = ConferenceFormat.date(s.startedAt);
    final title = crunched ? (s.crunchTitle ?? 'SmallTalk') : date;
    final isPtt = s.mode == SessionMode.pushToTalk.dbValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: HgPressable(
        onTap: () => _open(s),
        child: HgGlass(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(
            children: [
              HgGlass(
                radius: 13,
                elevated: false,
                intensity: 84,
                width: 42,
                height: 42,
                child: Center(
                  child: HgIcon(
                    crunched ? HgIcons.sparkle : HgIcons.smalltalk,
                    size: 21,
                    color: crunched ? p.visual : p.smalltalk,
                    strokeWidth: 1.8,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HgType.sans(16, weight: 700, color: p.text),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '$date · ${isPtt ? 'bas-konuş' : 'eller serbest'}'
                        '${crunched ? ' · özetlendi ✓' : ''}',
                        style: HgType.sans(
                          12.5,
                          color: crunched ? p.live : p.sub,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              HgIcon(HgIcons.chevron, size: 17, color: p.faint, strokeWidth: 2),
            ],
          ),
        ),
      ),
    );
  }
}
