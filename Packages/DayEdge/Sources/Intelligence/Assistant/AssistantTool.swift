import Foundation

/// Something the assistant can do or look up, described once and bridged to
/// every backend (Tachikoma's `AgentTool`, FoundationModels' `Tool`). Tools
/// answer in plain text — what the model reads back.
package struct AssistantTool: Sendable {
    package struct Parameter: Sendable, Equatable {
        package let name: String
        package let kind: AssistantToolParameterKind
        package var description: String
        package var isRequired = true
        /// Allowed values, for a string parameter.
        package var enumValues: [String]?
    }

    package let name: String
    package let description: String
    package let parameters: [Parameter]
    package let call: @Sendable (AssistantToolArguments) async throws -> String
}

/// The arguments a model passed to a tool, already parsed.
package struct AssistantToolArguments: Sendable, Equatable {
    package let values: [String: JSONValue]

    package init(_ values: [String: JSONValue] = [:]) {
        self.values = values
    }

    /// From a JSON object's text (`{"city": "Oslo"}`).
    package init(json: String) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard case .object(let object) = value else { throw AssistantToolArgumentError.notAnObject }
        self.init(object)
    }

    package func string(_ name: String) throws -> String {
        guard case .string(let value)? = values[name] else { throw AssistantToolArgumentError.missing(name) }
        return value
    }

    package func optionalString(_ name: String) -> String? {
        if case .string(let value)? = values[name] { return value }
        return nil
    }

    package func number(_ name: String) throws -> Double {
        switch values[name] {
        case .number(let value)?: return value
        default: throw AssistantToolArgumentError.missing(name)
        }
    }

    /// A whole number the model sent, rounded and clamped into `range`;
    /// nil when it's missing or not a finite number. Never `Int(_:)` on the
    /// raw value — `1e300` or NaN would trap.
    package func integer(_ name: String, in range: ClosedRange<Int>) -> Int? {
        guard case .number(let value)? = values[name], value.isFinite else { return nil }
        let clamped = min(max(value.rounded(), Double(range.lowerBound)), Double(range.upperBound))
        return Int(clamped)
    }

    package func bool(_ name: String) throws -> Bool {
        guard case .bool(let value)? = values[name] else { throw AssistantToolArgumentError.missing(name) }
        return value
    }
}

package enum AssistantToolArgumentError: Error, Equatable {
    case notAnObject
    case missing(String)
}

/// The JSON a tool's arguments can hold.
package enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// What a tool parameter takes.
package enum AssistantToolParameterKind: String, Sendable {
    case string, number, integer, boolean
}
