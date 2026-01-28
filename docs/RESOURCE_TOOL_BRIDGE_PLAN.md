# MCP LLM Resource Tool Bridge Implementation Plan

## Overview

This document outlines the implementation plan to fix the resource accessibility gap in `mcp_llm` package. Currently, MCP resources are advertised to the LLM in the system prompt but cannot be accessed because there are no corresponding tools for the LLM to call.

---

## 1. Problem Statement

### 1.1 Current Behavior

When using `llmClient.streamChat()` with MCP resources:

1. Resources are collected via `_collectAvailableResources()`
2. Resources are listed in the system prompt as "Available resources"
3. LLM sees the resource list and tries to access them
4. **LLM invents non-existent tool names** like `list_resource_entities`
5. Tool execution fails with "tool not exists" error

### 1.2 Root Cause

```
┌─────────────────────────────────────────────────────────────────┐
│                    Current Architecture                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  _collectAvailableTools()     →  Tools sent to LLM as callable  │
│  _collectAvailableResources() →  Listed in prompt text ONLY     │
│                                                                  │
│  Gap: Resources are VISIBLE but NOT CALLABLE                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 Evidence from Issue Report

```json
// LLM Response - Hallucinated tool call
{
  "tool_calls": [{
    "function": {
      "name": "list_resource_entities",  // This tool doesn't exist!
      "arguments": "{\"resourceName\":\"people\"}"
    }
  }]
}
```

---

## 2. Analysis Summary

### 2.1 Existing Infrastructure (Already Working)

| Component | Location | Status |
|-----------|----------|--------|
| `_collectAvailableResources()` | llm_client.dart:458-487 | Working |
| `LlmClient.readResource()` | llm_client.dart:1326-1340 | Working |
| `McpClientManager.readResource()` | mcp_client_manager.dart:618-698 | Working |
| `McpClientManager.getResources()` | mcp_client_manager.dart:291-328 | Working |

### 2.2 Missing Components

| Component | Description | Impact |
|-----------|-------------|--------|
| Resource-to-Tool Bridge | Synthetic tools for resource access | Critical |
| Resource Tool Handler | Route synthetic tools to readResource() | Critical |

---

## 3. Proposed Solution

### 3.1 Solution Overview

Create **synthetic tools** that wrap resource operations, allowing the LLM to access resources through the standard tool calling mechanism.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Proposed Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  _collectAvailableTools()                                        │
│    ├── MCP Tools (existing)                                      │
│    ├── Plugin Tools (existing)                                   │
│    └── Synthetic Resource Tools (NEW)                            │
│          ├── mcp_read_resource                                   │
│          └── mcp_list_resources                                  │
│                                                                  │
│  executeTool()                                                   │
│    ├── MCP Tool Execution (existing)                             │
│    ├── Plugin Tool Execution (existing)                          │
│    └── Synthetic Tool Routing (NEW)                              │
│          ├── mcp_read_resource → readResource()                  │
│          └── mcp_list_resources → _collectAvailableResources()   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Synthetic Tools Definition

#### Tool 1: `mcp_read_resource`

```dart
{
  'name': 'mcp_read_resource',
  'description': 'Read content from an MCP resource. Use this tool to fetch data from available resources.',
  'inputSchema': {
    'type': 'object',
    'properties': {
      'uri': {
        'type': 'string',
        'description': 'The resource URI to read (e.g., "resource://people", "resource://todos/1")'
      },
      'resourceName': {
        'type': 'string',
        'description': 'Alternative: resource name from the available resources list'
      }
    },
    'required': []  // Either uri or resourceName should be provided
  }
}
```

#### Tool 2: `mcp_list_resources`

```dart
{
  'name': 'mcp_list_resources',
  'description': 'List all available MCP resources with their URIs and descriptions.',
  'inputSchema': {
    'type': 'object',
    'properties': {},
    'required': []
  }
}
```

---

## 4. Implementation Details

### 4.1 File to Modify

**Only one file needs modification:**
- `lib/src/core/llm_client.dart`

### 4.2 Modification 1: `_collectAvailableTools()` (Line ~1030)

```dart
/// Collect available tools from MCP clients and plugins
Future<List<Map<String, dynamic>>> _collectAvailableTools({
  bool enableMcpTools = true,
  bool enablePlugins = true,
  bool enableResourceTools = true,  // NEW PARAMETER
  String? mcpClientId,
}) async {
  final tools = <Map<String, dynamic>>[];

  // ... existing MCP tools collection ...
  // ... existing plugin tools collection ...

  // NEW: Add synthetic resource tools
  if (enableResourceTools) {
    final availableResources = await _collectAvailableResources(
      enableMcpResources: true,
    );

    if (availableResources.isNotEmpty) {
      // Add mcp_read_resource tool
      tools.add({
        'name': 'mcp_read_resource',
        'description': 'Read content from an MCP resource. Available resources: ${availableResources.map((r) => r['name']).join(', ')}',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'uri': {
              'type': 'string',
              'description': 'The resource URI to read'
            },
            'resourceName': {
              'type': 'string',
              'description': 'Resource name from available list: ${availableResources.map((r) => r['name']).join(', ')}'
            }
          },
          'required': []
        }
      });

      // Add mcp_list_resources tool
      tools.add({
        'name': 'mcp_list_resources',
        'description': 'List all available MCP resources with details',
        'inputSchema': {
          'type': 'object',
          'properties': {},
          'required': []
        }
      });

      _logger.info('Added ${2} synthetic resource tools');
    }
  }

  return tools;
}
```

### 4.3 Modification 2: `executeTool()` (Line ~1190)

```dart
/// Execute tool using MCP clients or plugins
Future<dynamic> executeTool(String toolName, Map<String, dynamic> args, {
  bool enableMcpTools = true,
  bool enablePlugins = true,
  String? mcpClientId,
  bool tryAllMcpClients = true,
}) async {

  // NEW: Handle synthetic resource tools first
  if (toolName == 'mcp_read_resource') {
    return await _executeReadResourceTool(args);
  }

  if (toolName == 'mcp_list_resources') {
    return await _executeListResourcesTool();
  }

  // ... existing MCP tool execution ...
  // ... existing plugin tool execution ...
}

/// NEW: Execute mcp_read_resource synthetic tool
Future<dynamic> _executeReadResourceTool(Map<String, dynamic> args) async {
  String? uri = args['uri'] as String?;
  final resourceName = args['resourceName'] as String?;

  // If resourceName provided but not uri, find the URI
  if (uri == null && resourceName != null) {
    final resources = await _collectAvailableResources(enableMcpResources: true);
    final resource = resources.firstWhere(
      (r) => r['name'] == resourceName,
      orElse: () => <String, dynamic>{},
    );
    uri = resource['uri'] as String?;
  }

  if (uri == null || uri.isEmpty) {
    return {
      'error': 'Resource URI or valid resourceName is required',
      'availableResources': await _collectAvailableResources(enableMcpResources: true),
    };
  }

  try {
    final result = await readResource(uri, tryAllClients: true);
    _logger.debug('Successfully read resource: $uri');
    return result;
  } catch (e) {
    _logger.error('Error reading resource $uri: $e');
    return {'error': 'Failed to read resource: $e'};
  }
}

/// NEW: Execute mcp_list_resources synthetic tool
Future<dynamic> _executeListResourcesTool() async {
  try {
    final resources = await _collectAvailableResources(enableMcpResources: true);
    return {
      'resources': resources,
      'count': resources.length,
      'message': 'Found ${resources.length} available resources',
    };
  } catch (e) {
    _logger.error('Error listing resources: $e');
    return {'error': 'Failed to list resources: $e'};
  }
}
```

### 4.4 Optional Enhancement: Update System Prompt

Update `createEnhancedSystemPrompt()` to provide clearer guidance:

```dart
// In createEnhancedSystemPrompt(), update the resource section:
if (includeSystemPrompt && availableResources.isNotEmpty) {
  enhancedPrompt.write('\nResource Access Guidelines:\n');
  enhancedPrompt.write('1. Use the "mcp_read_resource" tool to fetch resource content.\n');
  enhancedPrompt.write('2. Use the "mcp_list_resources" tool to see all available resources.\n');
  enhancedPrompt.write('3. Provide either "uri" or "resourceName" parameter.\n');

  enhancedPrompt.write('\n\nAvailable resources:\n');
  for (int i = 0; i < availableResources.length; i++) {
    final resource = availableResources[i];
    enhancedPrompt.write('${i+1}. ${resource['name']} - ${resource['description']}\n');
    enhancedPrompt.write('   URI: ${resource['uri']}\n');
    if (resource['mimeType'] != null) {
      enhancedPrompt.write('   Type: ${resource['mimeType']}\n');
    }
    enhancedPrompt.write('\n');
  }
}
```

---

## 5. Testing Plan

### 5.1 Unit Tests

```dart
// test/resource_tool_bridge_test.dart

void main() {
  group('Resource Tool Bridge', () {
    test('mcp_list_resources returns available resources', () async {
      // Setup
      final client = LlmClient(...);

      // Execute
      final result = await client.executeTool('mcp_list_resources', {});

      // Verify
      expect(result['resources'], isNotEmpty);
      expect(result['count'], greaterThan(0));
    });

    test('mcp_read_resource reads resource by URI', () async {
      final client = LlmClient(...);

      final result = await client.executeTool('mcp_read_resource', {
        'uri': 'resource://people'
      });

      expect(result, isNotNull);
      expect(result.containsKey('error'), isFalse);
    });

    test('mcp_read_resource reads resource by name', () async {
      final client = LlmClient(...);

      final result = await client.executeTool('mcp_read_resource', {
        'resourceName': 'people'
      });

      expect(result, isNotNull);
      expect(result.containsKey('error'), isFalse);
    });

    test('synthetic tools are included in available tools', () async {
      final client = LlmClient(...);

      final tools = await client._collectAvailableTools(
        enableMcpTools: true,
        enablePlugins: true,
        enableResourceTools: true,
      );

      final toolNames = tools.map((t) => t['name']).toList();
      expect(toolNames, contains('mcp_read_resource'));
      expect(toolNames, contains('mcp_list_resources'));
    });
  });
}
```

### 5.2 Integration Test

```dart
// test/integration/resource_access_integration_test.dart

void main() {
  test('LLM can access resources through tool calls', () async {
    final llmClient = LlmClient(
      llmProvider: provider,
      mcpClient: mcpClient,
    );

    // Chat requesting resource data
    final response = await llmClient.chat(
      'Show me the list of people',
      enableTools: true,
    );

    // Verify tool was called and resource data returned
    expect(response.metadata?['tools_used'], contains('mcp_read_resource'));
    expect(response.text, contains('people')); // Resource content
  });
}
```

---

## 6. Migration Notes

### 6.1 Backward Compatibility

- All existing functionality remains unchanged
- New `enableResourceTools` parameter defaults to `true`
- No breaking changes to public API

### 6.2 Version Bump

```yaml
# pubspec.yaml
version: X.Y.Z+1  # Patch version bump for bug fix
```

### 6.3 Changelog Entry

```markdown
## [X.Y.Z+1] - YYYY-MM-DD

### Fixed
- Fixed resource accessibility gap where MCP resources were listed in system prompt
  but could not be accessed by LLM
- Added synthetic tools `mcp_read_resource` and `mcp_list_resources` for resource access

### Added
- `enableResourceTools` parameter in `_collectAvailableTools()` (default: true)
- `_executeReadResourceTool()` helper method
- `_executeListResourcesTool()` helper method
```

---

## 7. Summary

| Item | Details |
|------|---------|
| **Files to Modify** | `lib/src/core/llm_client.dart` (1 file) |
| **Methods to Modify** | `_collectAvailableTools()`, `executeTool()` |
| **New Methods** | `_executeReadResourceTool()`, `_executeListResourcesTool()` |
| **New Tools** | `mcp_read_resource`, `mcp_list_resources` |
| **Breaking Changes** | None |
| **Estimated LOC** | ~80 lines added |

---

## 8. References

- GitHub Issue: MCP Resources not accessible via LLM tool calls
- MCP Specification: Resource handling
- Related Files:
  - [llm_client.dart](../lib/src/core/llm_client.dart)
  - [mcp_client_manager.dart](../lib/src/adapter/mcp_client_manager.dart)
