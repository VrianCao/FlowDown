//
//  ModelContextServer.swift
//  Storage
//
//  Created by LiBr on 6/29/25.
//
import Foundation
import WCDBSwift

public struct StringArrayCodable: ColumnCodable {
    public let array: [String]

    public init(_ array: [String]) {
        self.array = array
    }

    public init?(with value: WCDBSwift.Value) {
        let data = value.stringValue.data(using: .utf8) ?? Data()
        guard let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        self.array = array
    }

    public func archivedValue() -> WCDBSwift.Value {
        let data = (try? JSONEncoder().encode(array)) ?? Data()
        return .init(String(data: data, encoding: .utf8) ?? "[]")
    }

    public static var columnType: WCDBSwift.ColumnType {
        .text
    }
}

public final class ModelContextServer: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "ModelContextServer"

    public var id: String {
        objectId
    }

    public var objectId: String = UUID().uuidString
    public var deviceId: String = ""
    public var name: String = ""
    public var comment: String = ""
    public var type: ServerType = .http
    public var endpoint: String = ""
    public var header: String = ""
    public var timeout: Int = 60
    public var isEnabled: Bool = true
    public var toolsEnabled: EnableCodable = .init()
    public var resourcesEnabled: EnableCodable = .init()
    public var templateEnabled: EnableCodable = .init()
    public var lastConnected: Date?
    public var connectionStatus: ConnectionStatus = .disconnected
    public var capabilities: StringArrayCodable = .init([])

    public var removed: Bool = false
    public var creation: Date = .now
    public var modified: Date = .now

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ModelContextServer
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(comment, isNotNull: true, defaultTo: "")
            BindColumnConstraint(type, isNotNull: true, defaultTo: ServerType.http.rawValue)
            BindColumnConstraint(endpoint, isNotNull: true, defaultTo: "")
            BindColumnConstraint(header, isNotNull: true, defaultTo: "")
            BindColumnConstraint(timeout, isNotNull: true, defaultTo: 60)
            BindColumnConstraint(isEnabled, isNotNull: true, defaultTo: true)
            BindColumnConstraint(toolsEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(resourcesEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(templateEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(lastConnected, isNotNull: false)
            BindColumnConstraint(connectionStatus, isNotNull: true, defaultTo: ConnectionStatus.disconnected.rawValue)
            BindColumnConstraint(capabilities, isNotNull: true, defaultTo: StringArrayCodable([]))

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
        }

        case objectId
        case deviceId
        case name
        case comment
        case type
        case endpoint
        case header
        case timeout
        case isEnabled
        case toolsEnabled
        case templateEnabled
        case resourcesEnabled
        case lastConnected
        case connectionStatus
        case capabilities

        case removed
        case creation
        case modified
    }

    public init(
        deviceId: String,
        objectId: String = Storage.deviceId,
        name: String = "",
        comment: String = "",
        type: ServerType = .http,
        endpoint: String = "",
        header: String = "",
        timeout: Int = 60,
        isEnabled: Bool = true,
        toolsEnabled: EnableCodable = .init(),
        resourcesEnabled: EnableCodable = .init(),
        templateEnabled: EnableCodable = .init(),
        lastConnected: Date? = nil,
        connectionStatus: ConnectionStatus = .disconnected,
        capabilities: StringArrayCodable = StringArrayCodable([])
    ) {
        self.deviceId = deviceId
        self.objectId = objectId
        self.name = name
        self.comment = comment
        self.type = type
        self.endpoint = endpoint
        self.header = header
        self.timeout = timeout
        self.isEnabled = isEnabled
        self.toolsEnabled = toolsEnabled
        self.resourcesEnabled = resourcesEnabled
        self.templateEnabled = templateEnabled
        self.lastConnected = lastConnected
        self.connectionStatus = connectionStatus
        self.capabilities = capabilities
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectId = try container.decodeIfPresent(String.self, forKey: .objectId) ?? UUID().uuidString
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? Storage.deviceId
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        type = try container.decodeIfPresent(ServerType.self, forKey: .type) ?? .http
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        header = try container.decodeIfPresent(String.self, forKey: .header) ?? ""
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout) ?? 60
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        toolsEnabled = try container.decodeIfPresent(EnableCodable.self, forKey: .toolsEnabled) ?? .init()
        resourcesEnabled = try container.decodeIfPresent(EnableCodable.self, forKey: .resourcesEnabled) ?? .init()
        templateEnabled = try container.decodeIfPresent(EnableCodable.self, forKey: .templateEnabled) ?? .init()
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        connectionStatus = try container.decodeIfPresent(ConnectionStatus.self, forKey: .connectionStatus) ?? .disconnected
        capabilities = try container.decodeIfPresent(StringArrayCodable.self, forKey: .capabilities) ?? .init([])

        removed = try container.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        creation = try container.decodeIfPresent(Date.self, forKey: .creation) ?? Date()
        modified = try container.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
    }

    func markModified(_ date: Date = .now) {
        modified = date
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public extension ModelContextServer {
    static func decodeCompatible(from data: Data) throws -> ModelContextServer {
        let decoder = PropertyListDecoder()

        // 尝试旧结构
        if let old = try? decoder.decode(ModelContextServerV1.self, from: data) {
            let new = ModelContextServer(deviceId: Storage.deviceId)
            new.objectId = old.id
            new.name = old.name
            new.comment = old.comment
            new.type = old.type
            new.endpoint = old.endpoint
            new.header = old.header
            new.timeout = old.timeout
            new.isEnabled = old.isEnabled
            new.toolsEnabled = old.toolsEnabled
            new.resourcesEnabled = old.resourcesEnabled
            new.templateEnabled = old.templateEnabled
            new.lastConnected = old.lastConnected
            new.connectionStatus = old.connectionStatus
            new.capabilities = old.capabilities
            return new
        }

        let new = try decoder.decode(ModelContextServer.self, from: data)
        return new
    }
}

extension ModelContextServer: Equatable {
    public static func == (lhs: ModelContextServer, rhs: ModelContextServer) -> Bool {
        lhs.objectId == rhs.objectId
    }
}

extension ModelContextServer: Hashable {}

public extension ModelContextServer {
    enum ServerType: String, Codable, ColumnCodable {
        case http

        public init?(with value: WCDBSwift.Value) {
            let rawValue = value.stringValue
            self.init(rawValue: rawValue)
        }

        public func archivedValue() -> WCDBSwift.Value {
            .init(rawValue)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .text
        }
    }

    enum ConnectionStatus: String, Codable, ColumnCodable {
        case disconnected
        case connecting
        case connected
        case failed

        public init?(with value: WCDBSwift.Value) {
            let rawValue = value.stringValue
            self.init(rawValue: rawValue)
        }

        public func archivedValue() -> WCDBSwift.Value {
            .init(rawValue)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .text
        }
    }
}

public extension ModelContextServer {
    struct EnableCodable: Codable, ColumnCodable {
        public init?(with value: WCDBSwift.Value) {
            let data = value.dataValue
            guard let object = try? JSONDecoder().decode(EnableCodable.self, from: data) else {
                return nil
            }
            self = object
        }

        public func archivedValue() -> WCDBSwift.Value {
            let data = try! JSONEncoder().encode(self)
            return .init(data)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .BLOB
        }

        public var value: [String: Bool] = [:]

        public init() {
            value = [:]
        }

        public init(value: [String: Bool]) {
            self.value = value
        }
    }
}
