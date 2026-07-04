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

  test('McpServerConfig json serialization test', () {
    const config = McpServerConfig(
      id: 'test-id',
      name: 'Test Server',
      url: 'https://test.mcp.io',
      isOnline: true,
      description: 'A test server description',
    );

    final json = config.toJson();
    expect(json['id'], equals('test-id'));
    expect(json['name'], equals('Test Server'));
    expect(json['url'], equals('https://test.mcp.io'));
    expect(json['isOnline'], isTrue);
    expect(json['description'], equals('A test server description'));

    final deserialized = McpServerConfig.fromJson(json);
    expect(deserialized.id, equals('test-id'));
    expect(deserialized.name, equals('Test Server'));
    expect(deserialized.url, equals('https://test.mcp.io'));
    expect(deserialized.isOnline, isTrue);
    expect(deserialized.description, equals('A test server description'));
  });
}
