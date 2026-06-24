import 'package:googleai_dart/googleai_dart.dart';

void main() {
  final client = GoogleAIClient(
    config: GoogleAIConfig.googleAI(
      authProvider: ApiKeyProvider('API_KEY'),
    ),
  );

  // Check Tool
  final tool = Tool(
    functionDeclarations: [
      FunctionDeclaration(
        name: 'test_func',
        description: 'a test function',
        parameters: Schema(
          type: SchemaType.object,
          properties: {
            'location': Schema(
              type: SchemaType.string,
              description: 'The location',
            ),
          },
          required: ['location'],
        ),
      ),
    ],
  );

  // Check Content and Part
  final content = Content(
    role: 'user',
    parts: [
      Part.text('hello'),
    ],
  );

  // Check GenerateContentRequest
  final request = GenerateContentRequest(
    contents: [content],
    tools: [tool],
    systemInstruction: Content(
      parts: [Part.text('System instruction text')],
    ),
    generationConfig: GenerationConfig(
      temperature: 0.2,
      maxOutputTokens: 200,
    ),
  );

  // Check generateContent call
  client.models.generateContent(
    model: 'gemini-1.5-flash',
    request: request,
  );
}
