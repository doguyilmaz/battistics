# Third party licenses

Battistics bundles the components below. MCP dependency license texts and
notices are included in `Contents/Resources/MCP-Third-Party-Licenses.txt`.

## Sparkle

Software update framework for macOS.
https://github.com/sparkle-project/Sparkle

Licensed under the MIT License, with portions under compatible permissive
licenses as documented in the Sparkle repository:
https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE

## MCP Swift SDK and dependencies

The bundled `battistics-mcp` executable links:

- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk), MIT
- [Swift System](https://github.com/apple/swift-system), Apache 2.0 with Swift Runtime Library Exception
- [Swift Log](https://github.com/apple/swift-log), Apache 2.0
- [EventSource](https://github.com/mattt/eventsource), MIT

Versions are recorded in `Package.resolved`. SwiftNIO and its dependencies are
resolved by the SDK package for its separate conformance tools; Battistics does
not link those tools.
