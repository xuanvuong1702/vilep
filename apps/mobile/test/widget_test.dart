import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vilep_app/core/format.dart';
import 'package:vilep_app/widgets.dart';

void main() {
  test('money formats VND with separators', () {
    expect(money(45000), '45.000đ');
    expect(money(1000000), '1.000.000đ');
  });

  test('moneyShort compresses large amounts', () {
    expect(moneyShort(45000), '45k');
    expect(moneyShort(1500000), '1.5tr');
  });

  test('relativeDeadline speaks human', () {
    expect(relativeDeadline(0), 'Đã hết hạn');
    expect(relativeDeadline(1), 'Còn 1 ngày');
    expect(relativeDeadline(9), 'Còn 9 ngày');
  });

  test('state labels are Vietnamese', () {
    expect(stateLabel('funding'), 'Đang gây quỹ');
    expect(stateLabel('closed'), 'Hoàn tất');
  });

  testWidgets('wallet mascot renders and repaints with progress', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: WalletMascot(progress: 0.4, size: 120))),
    ));
    expect(find.byType(WalletMascot), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: WalletMascot(progress: 1, size: 120))),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(WalletMascot), findsOneWidget);
  });

  testWidgets('wallet progress clamps percent', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: WalletProgress(percent: 150)),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(WalletProgress), findsOneWidget);
  });
}
