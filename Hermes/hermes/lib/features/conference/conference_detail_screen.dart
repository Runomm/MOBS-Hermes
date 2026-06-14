import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/database/app_database.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/services/gemini_key_store.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';
import 'conference_format.dart';
import 'crunch_runner.dart';

/// Tek bir oturum kaydının detayı (K3) — liquid-glass stil (2026-06-12).
///
/// Transkript (`sourceText`) + crunch edilmişse tam çeviri + özet. 2-adımlı
/// crunch: ham → **"Daha İyi Çevir"** (NLLB; canlı çeviriden ayrışan spesifik
/// etiket — Mehmet 2026-06-11 feedback) → çevrildi → **"Özetle"** (Gemma).
/// Gemini anahtarı varsa çevrimiçi yol da sunulur.
class ConferenceDetailScreen extends StatefulWidget {
  const ConferenceDetailScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  State<ConferenceDetailScreen> createState() => _ConferenceDetailScreenState();
}

class _ConferenceDetailScreenState extends State<ConferenceDetailScreen> {
  late final AppDatabase _db;
  late final ConversationRepository _repo;

  SessionRow? _session;
  List<MessageRow> _messages = const [];
  bool _loading = true;
  bool _crunching = false;

  /// Kullanıcının kayıtlı Gemini anahtarı (varsa çevrimiçi crunch butonları çıkar).
  String? _geminiKey;

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
    final session = await _repo.getSession(widget.sessionId);
    final messages = await _repo.listMessagesForSession(widget.sessionId);
    final geminiKey = await GeminiKeyStore.instance.read();
    if (!mounted) return;
    setState(() {
      _session = session;
      _messages = messages;
      _geminiKey = (geminiKey != null && geminiKey.trim().isNotEmpty)
          ? geminiKey.trim()
          : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final session = _session;
    return HgScreen(
      scroll: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HgNavHeader(
            title: session?.crunchedAt != null ? 'Kayıt' : 'Kayıt detayı',
            sub: session == null
                ? null
                : ConferenceFormat.dateTime(session.startedAt),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: p.accent))
                : session == null
                ? Center(
                    child: Text(
                      'Kayıt bulunamadı.',
                      style: HgType.sans(14, color: p.sub),
                    ),
                  )
                : _content(p, session),
          ),
        ],
      ),
    );
  }

  Widget _content(HgPalette p, SessionRow session) {
    final hasTranslation = (session.crunchTranslation ?? '').trim().isNotEmpty;
    final summarized = session.crunchedAt != null;
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        Text(
          summarized
              ? (session.crunchTitle ?? 'Kayıt')
              : ConferenceFormat.date(session.startedAt),
          style: HgType.serif(30, weight: 600, color: p.text, height: 1.05),
        ),
        const SizedBox(height: 20),
        // Özet yapıldıysa: Özet + Tam çeviri. Yalnız çevrildiyse: Tam çeviri.
        if (summarized) ...[
          _section(p, 'Özet', session.crunchSummary ?? ''),
          const SizedBox(height: 16),
          _section(p, 'Tam çeviri', session.crunchTranslation ?? ''),
          const SizedBox(height: 16),
        ] else if (hasTranslation) ...[
          _section(p, 'Tam çeviri', session.crunchTranslation ?? ''),
          const SizedBox(height: 16),
        ],
        _transcriptSection(p),
        // 2-adımlı crunch: ham → "Daha İyi Çevir"; çevrildi → "Özetle".
        if (!summarized) ...[
          const SizedBox(height: 24),
          if (!hasTranslation)
            HgGradientButton(
              label: 'Daha İyi Çevir',
              from: p.visual,
              to: p.accent,
              icon: const HgIcon(
                HgIcons.layers,
                size: 17,
                color: Colors.white,
                strokeWidth: 1.8,
              ),
              onTap: _crunching ? null : _deepTranslate,
            )
          else
            HgGradientButton(
              label: 'Özetle',
              from: p.visual,
              to: p.accent,
              icon: const HgIcon(
                HgIcons.sparkle,
                size: 17,
                color: Colors.white,
                strokeWidth: 1.8,
              ),
              onTap: _crunching ? null : _summarize,
            ),
          // Gemini anahtarı varsa: çevrimiçi (yerel model gerektirmeyen) seçenek.
          if (_geminiKey != null) ...[
            const SizedBox(height: 12),
            _onlineButton(
              p,
              !hasTranslation
                  ? 'Gemini ile Çevir & Özetle'
                  : 'Gemini ile Özetle',
              !hasTranslation ? _onlineCrunch : _onlineSummarize,
            ),
            const SizedBox(height: 6),
            Text(
              'Çevrimiçi · internet gerekir, transkript Google\'a gönderilir.',
              style: HgType.sans(12, color: p.faint),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Cihaz yerel özet modelini çalıştıramıyorsa Ayarlar\'dan kendi '
              'Gemini anahtarınla çevrimiçi özet kullanabilirsin.',
              style: HgType.sans(12, color: p.faint, height: 1.4),
            ),
          ],
        ],
      ],
    );
  }

  Widget _section(HgPalette p, String title, String body) {
    return HgGlass(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: HgType.sans(
              12,
              weight: 700,
              color: p.visual,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            body.trim().isEmpty ? '—' : body.trim(),
            style: HgType.sans(15, color: p.text, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _transcriptSection(HgPalette p) {
    return HgGlass(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TRANSKRİPT',
                style: HgType.sans(
                  12,
                  weight: 700,
                  color: p.sub,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (_messages.isNotEmpty)
                HgPressable(
                  onTap: _copyTranscript,
                  child: Row(
                    children: [
                      HgIcon(
                        HgIcons.copy,
                        size: 15,
                        color: p.sub,
                        strokeWidth: 1.8,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Kopyala',
                        style: HgType.sans(12.5, weight: 600, color: p.sub),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_messages.isEmpty)
            Text('Transkript boş.', style: HgType.sans(14, color: p.faint))
          else
            for (final m in _messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  m.sourceText,
                  style: HgType.sans(15, color: p.sub, height: 1.4),
                ),
              ),
        ],
      ),
    );
  }

  Widget _onlineButton(HgPalette p, String label, VoidCallback onTap) {
    return HgPressable(
      onTap: _crunching ? null : onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.visual, width: 1.2),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_outlined, size: 18, color: p.visual),
              const SizedBox(width: 8),
              Text(
                label,
                style: HgType.sans(14.5, weight: 700, color: p.visual),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deepTranslate() async {
    final session = _session;
    if (session == null || _crunching) return;
    setState(() => _crunching = true);
    final ok = await runDeepTranslate(context, _repo, session);
    if (!mounted) return;
    setState(() => _crunching = false);
    if (ok) await _load(); // çeviri görünsün + "Özetle" çıksın
  }

  Future<void> _summarize() async {
    final session = _session;
    if (session == null || _crunching) return;
    setState(() => _crunching = true);
    final ok = await runSummarize(context, _repo, session);
    if (!mounted) return;
    setState(() => _crunching = false);
    if (ok) await _load(); // özet görünsün
  }

  Future<void> _onlineCrunch() async {
    final session = _session;
    final key = _geminiKey;
    if (session == null || key == null || _crunching) return;
    setState(() => _crunching = true);
    final ok = await runOnlineCrunch(context, _repo, session, key);
    if (!mounted) return;
    setState(() => _crunching = false);
    if (ok) await _load();
  }

  Future<void> _onlineSummarize() async {
    final session = _session;
    final key = _geminiKey;
    if (session == null || key == null || _crunching) return;
    setState(() => _crunching = true);
    final ok = await runOnlineSummarize(context, _repo, session, key);
    if (!mounted) return;
    setState(() => _crunching = false);
    if (ok) await _load();
  }

  Future<void> _copyTranscript() async {
    final text = _messages.map((m) => m.sourceText).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transkript kopyalandı'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}
