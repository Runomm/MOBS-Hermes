// Hermes — temel smoke test.
// Asıl test kapsamı Faz 5'te (özet, DB) yazılacak.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes/main.dart';

void main() {
  testWidgets('HermesApp splash sonrası ana ekranda mod kartlarıyla başlar',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HermesApp());

    // Açılışta splash (animasyonlu) gösterilir → ~1.7s sonra Home'a geçer.
    await tester.pump(const Duration(seconds: 2)); // splash timer → navigasyon
    await tester.pump(const Duration(milliseconds: 500)); // geçiş animasyonu

    // Mercury home (liquid-glass): serif marka + tagline + 4 mod.
    expect(find.text('Hermes'), findsOneWidget);
    expect(find.text('Sözü taşıyan haberci. Bir mod seç.'), findsOneWidget);
    expect(find.text('Konferans Modu'), findsOneWidget);
    expect(find.text('SmallTalk'), findsOneWidget);
    expect(find.text('Manuel Çeviri'), findsOneWidget);
    expect(find.text('Görsel Çeviri'), findsOneWidget);

    // Home'u dispose et → _OnlineBadge periyodik timer'ları iptal olsun
    // (yoksa "Timer still pending" ile test patlar).
    await tester.pumpWidget(const SizedBox());
  });
}
