import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('Deferred Loading Support Tests', () {
    group('ValidationResult', () {
      test('should create valid result', () {
        final result = ValidationResult.valid();

        expect(result.isValid, isTrue);
        expect(result.error, isNull);
      });

      test('should create invalid result with error', () {
        final result = ValidationResult.invalid('Missing required parameter');

        expect(result.isValid, isFalse);
        expect(result.error, equals('Missing required parameter'));
      });

      test('should have meaningful toString for valid', () {
        final result = ValidationResult.valid();

        expect(result.toString(), contains('valid'));
      });

      test('should have meaningful toString for invalid', () {
        final result = ValidationResult.invalid('Test error');

        expect(result.toString(), contains('invalid'));
        expect(result.toString(), contains('Test error'));
      });
    });

    group('LlmToolMetadata', () {
      test('should create from constructor', () {
        const metadata = LlmToolMetadata(
          name: 'test_tool',
          description: 'A test tool',
        );

        expect(metadata.name, equals('test_tool'));
        expect(metadata.description, equals('A test tool'));
      });

      test('should create from Map', () {
        final map = {
          'name': 'search',
          'description': 'Search for information',
          'inputSchema': {'type': 'object'},
        };

        final metadata = LlmToolMetadata.fromMap(map);

        expect(metadata.name, equals('search'));
        expect(metadata.description, equals('Search for information'));
      });

      test('should handle missing description in Map', () {
        final map = {'name': 'no_desc_tool'};

        final metadata = LlmToolMetadata.fromMap(map);

        expect(metadata.name, equals('no_desc_tool'));
        expect(metadata.description, equals(''));
      });

      test('should serialize to JSON without inputSchema', () {
        const metadata = LlmToolMetadata(
          name: 'my_tool',
          description: 'My description',
        );

        final json = metadata.toJson();

        expect(json['name'], equals('my_tool'));
        expect(json['description'], equals('My description'));
        expect(json.keys.length, equals(2));
        expect(json.containsKey('inputSchema'), isFalse);
      });

      test('should support equality', () {
        const metadata1 = LlmToolMetadata(name: 'tool', description: 'desc');
        const metadata2 = LlmToolMetadata(name: 'tool', description: 'desc');
        const metadata3 = LlmToolMetadata(name: 'tool', description: 'different');

        expect(metadata1, equals(metadata2));
        expect(metadata1.hashCode, equals(metadata2.hashCode));
        expect(metadata1, isNot(equals(metadata3)));
      });
    });

    group('DeferredToolManager', () {
      late DeferredToolManager manager;

      setUp(() {
        manager = DeferredToolManager();
      });

      test('should start uninitialized', () {
        expect(manager.isInitialized, isFalse);
        expect(manager.count, equals(0));
      });

      test('should validate tool call - uninitialized manager returns invalid', () {
        // When manager is not initialized, validation should fail for any tool
        manager.reset();

        // Since we cannot directly call _cacheFromMaps, we test getMetadata returns null
        expect(manager.getMetadata('test_tool'), isNull);

        // Validation should fail for uninitialized manager
        final result = manager.validateToolCall('test_tool', {'param1': 'value'});
        expect(result.isValid, isFalse);
        expect(result.error, contains('Tool not found'));
      });

      test('should return null for non-existent tool', () {
        expect(manager.getFullSchema('non_existent'), isNull);
        expect(manager.getMetadata('non_existent'), isNull);
        expect(manager.hasTool('non_existent'), isFalse);
      });

      test('should validate non-existent tool as invalid', () {
        final result = manager.validateToolCall('non_existent', {});

        expect(result.isValid, isFalse);
        expect(result.error, contains('Tool not found'));
      });

      test('should reset state correctly', () {
        manager.reset();

        expect(manager.isInitialized, isFalse);
        expect(manager.count, equals(0));
        expect(manager.getAllMetadata(), isEmpty);
      });

      test('should return empty metadata list when uninitialized', () {
        expect(manager.getMetadataForLlm(), isEmpty);
        expect(manager.getAllMetadata(), isEmpty);
        expect(manager.toolNames, isEmpty);
      });

      test('should invalidate and reset', () {
        manager.invalidate();

        expect(manager.isInitialized, isFalse);
        expect(manager.count, equals(0));
      });
    });

    group('LlmClient with Deferred Loading', () {
      test('should create client with deferred loading disabled by default', () {
        final provider = MockLlmProvider();
        final client = LlmClient(
          llmProvider: provider,
        );

        // The client should work normally without deferred loading
        expect(client, isNotNull);
      });

      test('should create client with deferred loading enabled', () {
        final provider = MockLlmProvider();
        final client = LlmClient(
          llmProvider: provider,
          useDeferredLoading: true,
        );

        // The client should be created with deferred loading enabled
        expect(client, isNotNull);
      });

      test('should not affect existing functionality when disabled', () {
        final provider = MockLlmProvider();
        final client = LlmClient(
          llmProvider: provider,
          useDeferredLoading: false,
        );

        // Standard operations should work
        expect(client.chatSession, isNotNull);
        expect(client.pluginManager, isNotNull);
      });
    });

    group('Backward Compatibility', () {
      test('should work with all existing constructor parameters', () {
        final provider = MockLlmProvider();

        // Test that all existing parameters still work
        final client = LlmClient(
          llmProvider: provider,
          enableHealthMonitoring: false,
          enableCapabilityManagement: false,
          enableLifecycleManagement: false,
          enableEnhancedErrorHandling: false,
          enableDebugLogging: false,
        );

        expect(client, isNotNull);
      });

      test('should work with new useDeferredLoading parameter', () {
        final provider = MockLlmProvider();

        // Test that new parameter works alongside existing ones
        final client = LlmClient(
          llmProvider: provider,
          enableHealthMonitoring: true,
          useDeferredLoading: true,
        );

        expect(client, isNotNull);
      });
    });

    group('Token Optimization Verification', () {
      test('LlmToolMetadata should be lightweight', () {
        final fullTool = {
          'name': 'complex_api',
          'description': 'Complex API tool',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'endpoint': {'type': 'string'},
              'method': {'type': 'string', 'enum': ['GET', 'POST']},
              'headers': {'type': 'object'},
              'body': {'type': 'object'},
            },
            'required': ['endpoint', 'method'],
          },
        };

        final metadata = LlmToolMetadata.fromMap(fullTool);
        final metadataJson = metadata.toJson();

        // Metadata should only contain name and description
        expect(metadataJson.keys.length, equals(2));
        expect(metadataJson.containsKey('inputSchema'), isFalse);

        // Metadata size should be much smaller
        final fullSize = fullTool.toString().length;
        final metadataSize = metadataJson.toString().length;
        expect(metadataSize, lessThan(fullSize / 2));
      });
    });
  });
}

/// Mock LLM Provider for testing
class MockLlmProvider implements LlmInterface {
  @override
  Future<void> initialize(LlmConfiguration config) async {}

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(text: 'Mock response');
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) {
    return Stream.fromIterable([
      LlmResponseChunk(textChunk: 'Mock', isDone: false),
      LlmResponseChunk(textChunk: ' response', isDone: true),
    ]);
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return [0.1, 0.2, 0.3];
  }

  @override
  Future<void> close() async {}

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) {
    return metadata.containsKey('tool_calls');
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    if (!hasToolCallMetadata(metadata)) return null;
    final toolCalls = metadata['tool_calls'] as List?;
    if (toolCalls == null || toolCalls.isEmpty) return null;
    final first = toolCalls.first as Map<String, dynamic>;
    return LlmToolCall(
      name: first['name'] as String,
      arguments: first['arguments'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    return Map<String, dynamic>.from(metadata);
  }
}
