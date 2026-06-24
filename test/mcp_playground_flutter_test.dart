import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_playground_flutter/mcp_playground_flutter.dart';

void main() {
  test('LlmConfig default values test', () {
    const config = LlmConfig(
      provider: LlmProvider.none,
      model: '',
      apiKey: '',
    );
    expect(config.temperature, equals(0.2));
    expect(config.thinking, isFalse);
    expect(config.isConfigured, isFalse);
  });
}
