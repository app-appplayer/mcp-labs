import 'package:test/test.dart';
import 'package:mcp_client/mcp_client.dart';

void main() {
  group('Deferred Loading Support Tests', () {
    group('ToolMetadata', () {
      test('should create from constructor', () {
        const metadata = ToolMetadata(
          name: 'test_tool',
          description: 'A test tool',
        );

        expect(metadata.name, equals('test_tool'));
        expect(metadata.description, equals('A test tool'));
      });

      test('should create from Tool object', () {
        final tool = Tool(
          name: 'calculator',
          description: 'Performs calculations',
          inputSchema: {
            'type': 'object',
            'properties': {
              'expression': {'type': 'string'},
            },
            'required': ['expression'],
          },
        );

        final metadata = ToolMetadata.fromTool(tool);

        expect(metadata.name, equals('calculator'));
        expect(metadata.description, equals('Performs calculations'));
      });

      test('should create from Map', () {
        final map = {
          'name': 'search',
          'description': 'Search for information',
          'inputSchema': {'type': 'object'},
        };

        final metadata = ToolMetadata.fromMap(map);

        expect(metadata.name, equals('search'));
        expect(metadata.description, equals('Search for information'));
      });

      test('should handle missing description in Map', () {
        final map = {'name': 'no_desc_tool'};

        final metadata = ToolMetadata.fromMap(map);

        expect(metadata.name, equals('no_desc_tool'));
        expect(metadata.description, equals(''));
      });

      test('should serialize to JSON', () {
        const metadata = ToolMetadata(
          name: 'my_tool',
          description: 'My description',
        );

        final json = metadata.toJson();

        expect(json['name'], equals('my_tool'));
        expect(json['description'], equals('My description'));
        expect(json.keys.length, equals(2));
      });

      test('should support equality', () {
        const metadata1 = ToolMetadata(name: 'tool', description: 'desc');
        const metadata2 = ToolMetadata(name: 'tool', description: 'desc');
        const metadata3 = ToolMetadata(name: 'tool', description: 'different');

        expect(metadata1, equals(metadata2));
        expect(metadata1.hashCode, equals(metadata2.hashCode));
        expect(metadata1, isNot(equals(metadata3)));
      });

      test('should have meaningful toString', () {
        const metadata = ToolMetadata(name: 'test', description: 'Test tool');

        expect(metadata.toString(), contains('test'));
        expect(metadata.toString(), contains('Test tool'));
      });
    });

    group('ToolRegistry', () {
      late ToolRegistry registry;

      setUp(() {
        registry = ToolRegistry();
      });

      test('should start uninitialized', () {
        expect(registry.isInitialized, isFalse);
        expect(registry.count, equals(0));
      });

      test('should cache tools from Map list', () {
        final tools = [
          {
            'name': 'tool1',
            'description': 'First tool',
            'inputSchema': {'type': 'object'},
          },
          {
            'name': 'tool2',
            'description': 'Second tool',
            'inputSchema': {'type': 'object', 'required': ['param1']},
          },
        ];

        registry.cacheFromMaps(tools);

        expect(registry.isInitialized, isTrue);
        expect(registry.count, equals(2));
        expect(registry.hasTool('tool1'), isTrue);
        expect(registry.hasTool('tool2'), isTrue);
        expect(registry.hasTool('tool3'), isFalse);
      });

      test('should cache tools from Tool list', () {
        final tools = [
          Tool(
            name: 'calculator',
            description: 'Calculator tool',
            inputSchema: {'type': 'object'},
          ),
          Tool(
            name: 'search',
            description: 'Search tool',
            inputSchema: {'type': 'object'},
          ),
        ];

        registry.cacheFromTools(tools);

        expect(registry.isInitialized, isTrue);
        expect(registry.count, equals(2));
        expect(registry.toolNames, containsAll(['calculator', 'search']));
      });

      test('should return all metadata', () {
        final tools = [
          {'name': 'tool1', 'description': 'Desc 1', 'inputSchema': {}},
          {'name': 'tool2', 'description': 'Desc 2', 'inputSchema': {}},
        ];

        registry.cacheFromMaps(tools);
        final allMetadata = registry.getAllMetadata();

        expect(allMetadata.length, equals(2));
        expect(allMetadata.map((m) => m.name), containsAll(['tool1', 'tool2']));
      });

      test('should return metadata for specific tool', () {
        final tools = [
          {'name': 'my_tool', 'description': 'My description', 'inputSchema': {}},
        ];

        registry.cacheFromMaps(tools);
        final metadata = registry.getMetadata('my_tool');

        expect(metadata, isNotNull);
        expect(metadata!.name, equals('my_tool'));
        expect(metadata.description, equals('My description'));
      });

      test('should return null for non-existent tool metadata', () {
        registry.cacheFromMaps([
          {'name': 'existing', 'description': 'Exists', 'inputSchema': {}},
        ]);

        expect(registry.getMetadata('non_existent'), isNull);
      });

      test('should return full schema for tool', () {
        final tools = [
          {
            'name': 'complex_tool',
            'description': 'Complex tool',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'param1': {'type': 'string'},
                'param2': {'type': 'number'},
              },
              'required': ['param1'],
            },
          },
        ];

        registry.cacheFromMaps(tools);
        final schema = registry.getSchema('complex_tool');

        expect(schema, isNotNull);
        expect(schema!['name'], equals('complex_tool'));
        expect(schema['description'], equals('Complex tool'));
        expect(schema['inputSchema'], isNotNull);
        expect(schema['inputSchema']['required'], contains('param1'));
      });

      test('should return null for non-existent tool schema', () {
        registry.cacheFromMaps([
          {'name': 'existing', 'description': 'Exists', 'inputSchema': {}},
        ]);

        expect(registry.getSchema('non_existent'), isNull);
      });

      test('should invalidate all cached data', () {
        registry.cacheFromMaps([
          {'name': 'tool1', 'description': 'Tool 1', 'inputSchema': {}},
          {'name': 'tool2', 'description': 'Tool 2', 'inputSchema': {}},
        ]);

        expect(registry.isInitialized, isTrue);
        expect(registry.count, equals(2));

        registry.invalidateAll();

        expect(registry.isInitialized, isFalse);
        expect(registry.count, equals(0));
        expect(registry.getAllMetadata(), isEmpty);
      });

      test('should clear previous data when caching new tools', () {
        registry.cacheFromMaps([
          {'name': 'old_tool', 'description': 'Old', 'inputSchema': {}},
        ]);

        expect(registry.hasTool('old_tool'), isTrue);

        registry.cacheFromMaps([
          {'name': 'new_tool', 'description': 'New', 'inputSchema': {}},
        ]);

        expect(registry.hasTool('old_tool'), isFalse);
        expect(registry.hasTool('new_tool'), isTrue);
        expect(registry.count, equals(1));
      });

      test('should return correct tool names list', () {
        registry.cacheFromMaps([
          {'name': 'alpha', 'description': 'Alpha', 'inputSchema': {}},
          {'name': 'beta', 'description': 'Beta', 'inputSchema': {}},
          {'name': 'gamma', 'description': 'Gamma', 'inputSchema': {}},
        ]);

        final names = registry.toolNames;

        expect(names.length, equals(3));
        expect(names, containsAll(['alpha', 'beta', 'gamma']));
      });
    });

    group('Token Optimization Verification', () {
      test('metadata should be smaller than full tool definition', () {
        final fullTool = {
          'name': 'complex_search',
          'description': 'Searches across multiple data sources',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Search query string',
              },
              'filters': {
                'type': 'object',
                'properties': {
                  'date_from': {'type': 'string', 'format': 'date'},
                  'date_to': {'type': 'string', 'format': 'date'},
                  'categories': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                },
              },
              'limit': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 100,
                'default': 10,
              },
              'sort_by': {
                'type': 'string',
                'enum': ['relevance', 'date', 'popularity'],
              },
            },
            'required': ['query'],
          },
        };

        final metadata = ToolMetadata.fromMap(fullTool);
        final metadataJson = metadata.toJson();

        final fullToolSize = fullTool.toString().length;
        final metadataSize = metadataJson.toString().length;

        expect(
          metadataSize,
          lessThan(fullToolSize),
          reason: 'Metadata should be significantly smaller than full schema',
        );

        // Metadata should only have name and description
        expect(metadataJson.keys.length, equals(2));
        expect(metadataJson.containsKey('inputSchema'), isFalse);
      });

      test('registry should preserve full schema for execution', () {
        final registry = ToolRegistry();
        final tools = [
          {
            'name': 'api_call',
            'description': 'Makes API calls',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'endpoint': {'type': 'string'},
                'method': {'type': 'string', 'enum': ['GET', 'POST', 'PUT']},
                'body': {'type': 'object'},
              },
              'required': ['endpoint', 'method'],
            },
          },
        ];

        registry.cacheFromMaps(tools);

        // Metadata is lightweight
        final metadata = registry.getMetadata('api_call');
        expect(metadata!.toJson().containsKey('inputSchema'), isFalse);

        // Full schema is preserved
        final schema = registry.getSchema('api_call');
        expect(schema!['inputSchema'], isNotNull);
        expect(schema['inputSchema']['required'], contains('endpoint'));
        expect(schema['inputSchema']['required'], contains('method'));
      });
    });
  });
}
