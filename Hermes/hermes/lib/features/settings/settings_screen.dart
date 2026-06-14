import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/managed_model.dart';
import '../../core/services/download_stats.dart';
import '../../core/services/gemini_client.dart';
import '../../core/services/gemini_key_store.dart';
import '../../core/services/hf_token_store.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';

/// Ayarlar — yüklü modelleri görüntüle, indir, sil. Liquid-glass stil
/// (2026-06-12 restyle; hand-off `SettingsScreen` — gruplu cam bölümler).
///
/// Mehmet isteği: model indirmeleri opak olmasın. Her model için durum
/// (hazır/inmemiş) görünür; indirilebilen modeller indirme onayı + ilerleme
/// ile iner, hazır olanlar silinebilir. Whisper tiny yerleşik (silinemez).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ModelRegistry _registry = ModelRegistry();
  late final List<ManagedModel> _models = _registry.all();

  /// model → hazır mı (null = yükleniyor).
  final Map<ManagedModel, bool?> _ready = {};

  /// İndirilmekte olan modeller → ilerleme (0–1; -1 = belirsiz).
  final Map<ManagedModel, double> _downloading = {};

  /// İndirme anlık istatistikleri (hız/boyut/ETA) — ilerleme destekleyen modeller.
  final Map<ManagedModel, DownloadStats> _stats = {};

  /// Silinmekte olan modeller.
  final Set<ManagedModel> _deleting = {};

  /// Kayıtlı Gemini anahtarı (null = yok/yükleniyor). Çevrimiçi crunch fallback.
  String? _geminiKey;

  @override
  void initState() {
    super.initState();
    for (final m in _models) {
      _ready[m] = null;
    }
    unawaited(_refreshAll());
    unawaited(_loadGeminiKey());
  }

  Future<void> _loadGeminiKey() async {
    final key = await GeminiKeyStore.instance.read();
    if (!mounted) return;
    setState(
      () => _geminiKey = (key != null && key.trim().isNotEmpty)
          ? key.trim()
          : null,
    );
  }

  Future<void> _editGeminiKey() async {
    final saved = _geminiKey ?? '';
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => _GeminiKeyDialog(initial: saved),
    );
    if (entered == null) return; // iptal
    final trimmed = entered.trim();
    if (trimmed.isEmpty) {
      await GeminiKeyStore.instance.save('');
      if (!mounted) return;
      setState(() => _geminiKey = null);
      _snack('Gemini anahtarı silindi.');
      return;
    }
    // Mehmet 2026-06-11: geçersiz anahtar sessizce kabul edilmesin — kaydetmeden
    // önce hafif GET ile doğrula; yalnız 200'de kaydet (401 "expected OAuth2"
    // gibi sorunlar kaydetme anında görünsün).
    _snack('Anahtar doğrulanıyor…');
    final client = GeminiClient(trimmed);
    try {
      await client.validateKey();
    } catch (e) {
      if (!mounted) return;
      _snack('Anahtar kaydedilmedi: $e');
      return;
    } finally {
      client.close();
    }
    await GeminiKeyStore.instance.save(trimmed);
    if (!mounted) return;
    setState(() => _geminiKey = trimmed);
    _snack('Gemini anahtarı doğrulandı ve kaydedildi.');
  }

  Future<void> _refreshAll() async {
    for (final m in _models) {
      try {
        final r = await m.isReady();
        if (!mounted) return;
        setState(() => _ready[m] = r);
      } catch (_) {
        if (!mounted) return;
        setState(() => _ready[m] = false);
      }
    }
  }

  Future<void> _download(ManagedModel m) async {
    // Gemma gated → HF token gerekir. Kayıtlı yoksa iste, kaydet (NS-1/NS-3).
    if (m.requiresToken) {
      final ok = await _ensureToken(m);
      if (!ok) return;
    }
    setState(() => _downloading[m] = m.supportsProgress ? 0 : -1);
    // Hız/ETA = kümülatif ortalama (toplam inen / toplam geçen süre) → titremez.
    final sw = Stopwatch()..start();
    try {
      await m.download(
        onProgress: m.supportsProgress
            ? (p) {
                if (!mounted) return;
                final stats = DownloadStats.from(
                  p,
                  sw.elapsedMilliseconds,
                  m.sizeMb,
                );
                setState(() {
                  _downloading[m] = p;
                  _stats[m] = stats;
                });
              }
            : null,
      );
      if (!mounted) return;
      setState(() {
        _downloading.remove(m);
        _stats.remove(m);
        _ready[m] = true;
      });
      _snack('${m.title} indirildi.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading.remove(m);
        _stats.remove(m);
      });
      _snack('${m.title} indirilemedi: $e');
    }
  }

  Future<void> _delete(ManagedModel m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${m.title} silinsin mi?'),
        content: const Text(
          'Model cihazdan silinecek. Tekrar kullanmak için yeniden '
          'indirmen gerekir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting.add(m));
    try {
      await m.delete();
      if (!mounted) return;
      setState(() {
        _deleting.remove(m);
        _ready[m] = false;
      });
      _snack('${m.title} silindi.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting.remove(m));
      _snack('${m.title} silinemedi: $e');
    }
  }

  /// Gemma indirmeden önce HF token'ın hazır olduğundan emin ol. Kayıtlıysa
  /// kutuyu önceden doldurur; kullanıcı değiştirebilir. İptal → false.
  Future<bool> _ensureToken(ManagedModel m) async {
    final saved = await HfTokenStore.instance.read() ?? '';
    if (!mounted) return false;
    final entered = await showDialog<String>(
      context: context,
      builder: (_) =>
          _HfTokenDialog(title: '${m.title} — HF token', initial: saved),
    );
    if (entered == null || entered.isEmpty) return false;
    await HfTokenStore.instance.save(entered);
    return true;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    // Kategoriye göre grupla (ekleme sırasını koru).
    final categories = <String, List<ManagedModel>>{};
    for (final m in _models) {
      categories.putIfAbsent(m.category, () => []).add(m);
    }

    return HgScreen(
      scroll: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HgNavHeader(title: 'Ayarlar', sub: 'Model yönetimi'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final entry in categories.entries) ...[
                  _groupHeader(p, entry.key),
                  HgGlass(
                    radius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        for (var i = 0; i < entry.value.length; i++)
                          _modelTile(
                            p,
                            entry.value[i],
                            last: i == entry.value.length - 1,
                          ),
                      ],
                    ),
                  ),
                ],
                _geminiSection(p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(HgPalette p, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: HgType.sans(12, weight: 700, color: p.faint, letterSpacing: 0.4),
      ),
    );
  }

  /// Çevrimiçi özet (Gemini) — düşük-RAM cihazlar için yerel Gemma3 yerine
  /// kullanıcının kendi anahtarıyla internet üzerinden crunch.
  Widget _geminiSection(HgPalette p) {
    final hasKey = _geminiKey != null;
    final masked = hasKey
        ? '••••${_geminiKey!.length >= 4 ? _geminiKey!.substring(_geminiKey!.length - 4) : _geminiKey!}'
        : 'Anahtar girilmedi';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupHeader(p, 'Çevrimiçi Özet (Gemini)'),
        HgGlass(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
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
                          'API anahtarı',
                          style: HgType.sans(15.5, weight: 600, color: p.text),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            masked,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: p.sub,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  HgPressable(
                    onTap: _editGeminiKey,
                    child: Text(
                      hasKey ? 'Düzenle' : 'Ekle',
                      style: HgType.sans(13.5, weight: 700, color: p.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Çevrimiçi özet kullanılırsa transkript Google\'a gönderilir.',
                style: HgType.sans(11.5, color: p.faint, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// İlerleme çubuğu altı detay: "{inen}/{toplam} MB · {hız} MB/s · ~{eta}s".
  /// İlerleme/boyut yoksa yalnız boyut (varsa) veya boş.
  String _downloadDetail(ManagedModel m, double progress) {
    if (progress < 0) {
      // Belirsiz (Whisper/MLKit, hook yok) → yalnız boyut.
      return m.sizeMb != null ? '~${m.sizeMb} MB' : '';
    }
    final s = _stats[m];
    if (s == null || s.totalMb == null) return '';
    final dl = s.downloadedMb!.toStringAsFixed(0);
    final tot = s.totalMb!.toStringAsFixed(0);
    final parts = <String>['$dl/$tot MB'];
    if (s.mbPerSec != null) parts.add('${s.mbPerSec!.toStringAsFixed(1)} MB/s');
    final eta = s.etaLabel;
    if (eta != null) parts.add('~$eta');
    return parts.join(' · ');
  }

  Widget _modelTile(HgPalette p, ManagedModel m, {required bool last}) {
    final ready = _ready[m];
    final progress = _downloading[m];
    final isDownloading = progress != null;
    final isDeleting = _deleting.contains(m);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: p.hairline, width: 0.5)),
            ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      style: HgType.sans(15.5, weight: 600, color: p.text),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        m.subtitle,
                        style: HgType.sans(12.5, color: p.sub),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailing(p, m, ready, isDownloading, isDeleting),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: progress >= 0
                    ? Stack(
                        children: [
                          Container(color: p.hairline),
                          FractionallySizedBox(
                            widthFactor: progress.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [p.accent, p.visual],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : LinearProgressIndicator(
                        minHeight: 6,
                        backgroundColor: p.hairline,
                        color: p.accent,
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _downloadDetail(m, progress),
                    style: HgType.sans(11.5, color: p.faint),
                  ),
                ),
                Text(
                  progress >= 0
                      ? '%${(progress * 100).clamp(0, 100).toStringAsFixed(0)}'
                      : 'indiriliyor…',
                  style: HgType.sans(12, weight: 700, color: p.accent),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _trailing(
    HgPalette p,
    ManagedModel m,
    bool? ready,
    bool isDownloading,
    bool isDeleting,
  ) {
    if (m.bundled) {
      return Text('Yerleşik', style: HgType.sans(12.5, color: p.faint));
    }
    if (isDownloading) {
      return const SizedBox(width: 24); // ilerleme aşağıda gösteriliyor
    }
    if (isDeleting) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (ready == null) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (ready) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HgIcon(HgIcons.check, size: 18, color: p.live, strokeWidth: 2.2),
          const SizedBox(width: 6),
          Text('Hazır', style: HgType.sans(13.5, weight: 700, color: p.live)),
          const SizedBox(width: 10),
          HgPressable(
            onTap: () => _delete(m),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: Icon(Icons.delete_outline, size: 20, color: p.faint),
              ),
            ),
          ),
        ],
      );
    }
    return HgPressable(
      onTap: () => _download(m),
      child: HgGlass(
        radius: 13,
        elevated: false,
        intensity: 84,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HgIcon(
              HgIcons.download,
              size: 16,
              color: p.accent,
              strokeWidth: 1.9,
            ),
            const SizedBox(width: 6),
            Text(
              'İndir',
              style: HgType.sans(13.5, weight: 700, color: p.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// HF token giriş dialog'u. Kendi `TextEditingController`'ını **kendi** State
/// yaşam döngüsünde tutar/dispose eder — çağıran tarafta `await showDialog`
/// sonrası senkron `dispose()` yapılırsa dialog kapanış animasyonu sürerken
/// controller bırakılıp InheritedElement deactivation hatası (`_dependents.isEmpty`)
/// çıkıyordu. Stateful dialog bunu kökten önler.
class _HfTokenDialog extends StatefulWidget {
  const _HfTokenDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_HfTokenDialog> createState() => _HfTokenDialogState();
}

class _HfTokenDialogState extends State<_HfTokenDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Gemma gated model. İndirmek için HuggingFace Read token gerekir '
            've o hesapla HF\'de Gemma lisansının kabul edilmiş olması lazım. '
            'Bir kez girersen kaydedilir, tekrar sorulmaz.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: widget.initial.isEmpty,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'HuggingFace token',
              hintText: 'hf_...',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.key, size: 18),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Kaydet & İndir'),
        ),
      ],
    );
  }
}

/// Gemini API anahtarı giriş dialog'u (`_HfTokenDialog` kalıbı). Boş kaydedilirse
/// çağıran tarafta anahtar silinir. Kendi controller'ını yönetir.
class _GeminiKeyDialog extends StatefulWidget {
  const _GeminiKeyDialog({required this.initial});

  final String initial;

  @override
  State<_GeminiKeyDialog> createState() => _GeminiKeyDialogState();
}

class _GeminiKeyDialogState extends State<_GeminiKeyDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gemini API anahtarı'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Google AI Studio\'dan aldığın kendi Gemini API anahtarını yapıştır. '
            'Düşük-RAM cihazlarda yerel özet modeli yerine çevrimiçi özet için '
            'kullanılır. Bir kez girersen kaydedilir. Boş bırakıp kaydedersen silinir.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: widget.initial.isEmpty,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Gemini API key',
              hintText: 'AIza...',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.key, size: 18),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
