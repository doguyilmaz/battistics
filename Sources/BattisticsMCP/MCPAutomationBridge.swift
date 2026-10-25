import BattisticsCore
import Foundation
import MCP

actor MCPAutomationBridge {
    private let client: LocalAutomationClient
    private var ownedID: UUID?
    private var heartbeat: Task<Void, Never>?
    private var calling = false
    private var closed = false

    init(client: LocalAutomationClient = LocalAutomationClient()) { self.client = client }

    static let tools: [Tool] = [
        Tool(name: "battistics_status", description: "Read battery level, the current Keep Awake session, and protections. Battistics must be open with local automation enabled. Does not expose history or change settings.",
             inputSchema: schema(properties: [:], required: []),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "battistics_start", description: "Start a named, finite Keep Awake task. Call battistics_stop with the returned session ID when the work finishes, fails, or is cancelled. Cannot replace an existing session or bypass battery/thermal protections. Connection loss ends the task. Closed-lid mode requires explicit permission and a preinstalled helper in Battistics.",
             inputSchema: schema(properties: [
                "name": .object(["type": "string", "minLength": 1, "maxLength": 80]),
                "duration_minutes": .object(["type": "integer", "enum": .array(KeepAwakeDuration.finite.map { .int($0.rawValue) })]),
                "mode": .object(["type": "string", "enum": .array(KeepAwakeMode.allCases.map { .string($0.rawValue) }), "default": "displayMaySleep"])
             ], required: ["name", "duration_minutes"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
        Tool(name: "battistics_stop", description: "End only the session started by this client connection. Normal macOS sleep is allowed again; a closed lid may cause immediate sleep. Does not shut down the Mac. Cannot stop manual sessions or sessions belonging to other clients.",
             inputSchema: schema(properties: ["session_id": .object(["type": "string", "format": "uuid"])], required: ["session_id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false))
    ]

    private static func schema(properties: [String: Value], required: [Value]) -> Value {
        .object(["type": "object", "properties": .object(properties), "required": .array(required), "additionalProperties": false])
    }

    func call(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        guard !closed else { return result(.init(code: .unavailable, message: "The MCP connection has closed.")) }
        guard !calling else { return result(.init(code: .busy, message: "Wait for the previous tool call to finish.")) }
        let args = parameters.arguments ?? [:]
        let request: AutomationRequest
        switch parameters.name {
        case "battistics_status":
            guard args.isEmpty else { return invalidArguments() }
            request = .init(.status)
        case "battistics_start":
            guard Set(args.keys).isSubset(of: ["name", "duration_minutes", "mode"]),
                  let name = args["name"]?.stringValue,
                  case .int(let minutes) = args["duration_minutes"],
                  args["mode"] == nil || args["mode"]?.stringValue != nil else { return invalidArguments() }
            request = .init(.start, name: name, mode: args["mode"]?.stringValue, durationMinutes: minutes)
            guard request.validatedStart() != nil else { return invalidArguments() }
        case "battistics_stop":
            guard Set(args.keys) == ["session_id"], let raw = args["session_id"]?.stringValue,
                  let id = UUID(uuidString: raw) else { return invalidArguments() }
            request = .init(.stop, sessionID: id)
        default:
            return result(.init(code: .invalidRequest, message: "Unknown tool. Use tools/list to discover supported tools."))
        }
        calling = true
        defer { calling = false }
        do {
            let reply = try await client.request(request)
            guard !closed else { return result(.init(code: .unavailable, message: "The MCP connection has closed.")) }
            if request.operation == .start, let id = reply.status?.sessionID {
                ownedID = id
                startHeartbeat(id)
            } else if reply.status?.active == false || reply.error?.code == .inactive {
                ownedID = nil
                heartbeat?.cancel()
                heartbeat = nil
            }
            // Ownership is per connection; an idle one would only hold one of
            // the app's few client slots until this MCP process exits.
            if ownedID == nil { await client.close() }
            return result(reply)
        } catch {
            ownedID = nil
            heartbeat?.cancel()
            heartbeat = nil
            return result(.init(code: .unavailable, message: "Could not reach Battistics. Open the app and enable Local automation in Power. The connection was closed; inspect status before retrying a start."))
        }
    }

    func close() async {
        closed = true
        heartbeat?.cancel()
        heartbeat = nil
        ownedID = nil
        await client.close()
    }

    private func startHeartbeat(_ id: UUID) {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(AutomationLease.heartbeatInterval)) }
                catch { return }
                guard let self, await self.renew(id) else { return }
            }
        }
    }

    private func renew(_ id: UUID) async -> Bool {
        guard !closed, ownedID == id else { return false }
        let reply = try? await client.request(.init(.heartbeat, sessionID: id))
        guard ownedID == id else { return false }
        guard reply?.status?.sessionID == id, reply?.status?.active == true else {
            ownedID = nil
            return false
        }
        return true
    }

    private func invalidArguments() -> CallTool.Result {
        result(.init(code: .invalidRequest, message: "Arguments do not match the tool schema. Use a finite supported duration and a name of 1–80 visible characters; unknown fields are rejected."))
    }

    private func result(_ reply: AutomationReply) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = (try? encoder.encode(reply)) ?? Data("{\"error\":{\"code\":\"unavailable\",\"message\":\"Could not encode the result.\"}}".utf8)
        return .init(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
                     isError: reply.error != nil)
    }
}
