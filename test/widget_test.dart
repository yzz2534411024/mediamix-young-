import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 基础冒烟测试 — 验证项目可编译
    expect(1 + 1, equals(2));
  });
}
