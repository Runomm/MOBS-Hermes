import 'package:flutter/material.dart';

import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../settings/settings_screen.dart';
import 'hg_icons.dart';
import 'hg_widgets.dart';

/// Bir mod için gerekli modeller yüklü değilken gösterilen yönlendirme kapısı.
///
/// Mehmet kararı (2026-06-09): indirmeler artık **yalnız Ayarlar'dan**. Modlar
/// inline indirme yapmaz; eksik model varsa bu kapı eksik model adlarını listeler
/// + "Ayarları Aç" ile [SettingsScreen]'e götürür. Kullanıcı dönünce [onRecheck]
/// çağrılır (model inmişse mod devam eder). Liquid-glass stile 2026-06-12'de
/// geçirildi (gate fazı görselliği hand-off "gate" ekranıyla hizalı).
class ModelsRequiredGate extends StatelessWidget {
  const ModelsRequiredGate({
    super.key,
    required this.missing,
    required this.onRecheck,
    this.note,
  });

  /// Eksik model adları (örn. ["Vosk Türkçe", "NLLB-600M"]).
  final List<String> missing;

  /// Ayarlar'dan dönünce hazırlığı yeniden kontrol eden callback.
  final Future<void> Function() onRecheck;

  /// Opsiyonel ek bilgi (örn. boyut uyarısı).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: HgResultTile(
                icon: HgIcons.download,
                accent: p.accent,
                filled: false,
              ),
            ),
            const SizedBox(height: 20),
            Center(child: HgSerifTitle('Modeller gerekli', size: 28)),
            const SizedBox(height: 10),
            Text(
              'Bu mod çevrimdışı çalışır; aşağıdaki modeller cihazında '
              'hazır olmalı. Tüm indirmeler Ayarlar → Modeller bölümünden yapılır.',
              textAlign: TextAlign.center,
              style: HgType.sans(13.5, color: p.sub, height: 1.45),
            ),
            const SizedBox(height: 18),
            HgChecklistGlass(
              rows: [
                for (final name in missing)
                  (name, 'İndirilmedi', false, 'Eksik'),
              ],
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  note!,
                  textAlign: TextAlign.center,
                  style: HgType.sans(12, color: p.faint, height: 1.4),
                ),
              ),
            const SizedBox(height: 24),
            HgGradientButton(
              label: 'Ayarları Aç',
              icon: const HgIcon(
                HgIcons.settings,
                size: 18,
                color: Colors.white,
                strokeWidth: 1.9,
              ),
              onTap: () => _openSettings(context),
            ),
            const SizedBox(height: 10),
            HgGlassButton(
              label: 'Geri',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await onRecheck();
  }
}
