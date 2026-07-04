import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_playground_flutter_example/main.dart';

void main() {
  testWidgets('Playground widget smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const McpPlaygroundExampleApp());

    // Verify that the playground widget compiles and builds.
    expect(find.byType(McpPlaygroundExampleApp), findsOneWidget);
  });
}
