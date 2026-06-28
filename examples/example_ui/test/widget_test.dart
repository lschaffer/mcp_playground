import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_playground_example/main.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';

void main() {
  testWidgets('Playground widget smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const McpPlaygroundExampleApp());

    // Verify that McpPlayground is rendered.
    expect(find.byType(McpPlayground), findsOneWidget);
  });
}
