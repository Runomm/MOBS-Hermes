// Hermes — temel smoke test.
// Asıl test kapsamı Faz 5'te (özet, DB) yazılacak.

import 'package:flutter_test/flutter_test.dart';

import 'package:hermes/main.dart';

void main() {
  testWidgets('HermesApp düzgün başlar ve test ekranı görünür',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HermesApp());

    expect(find.text('Hermes — Çeviri + STT Testi'), findsOneWidget);
    expect(find.text('Çevir'), findsOneWidget);
  });
}
