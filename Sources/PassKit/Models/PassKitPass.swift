import Vapor
import Fluent
import PassGenerator

/// Represents the `Model` that stores PassKit passes.
public protocol PassKitPass: Model, PassConvertible where IDValue == UUID {
    
    /// The last time the pass was modified.
    var modified: Date? { get set }
    
    static func `for`(serialNumber: UUID, on db: Database) async throws -> Self
}

internal extension PassKitPass {
    var _$id: ID<UUID> {
        guard let mirror = Mirror(reflecting: self).descendant("_id"),
              let id = mirror as? ID<UUID> else {
            fatalError("id property must be declared using @ID")
        }
        
        return id
    }
    
    var _$modified: Timestamp<ISO8601TimestampFormat> {
        guard let mirror = Mirror(reflecting: self).descendant("_modified"),
              let modified = mirror as? Timestamp<ISO8601TimestampFormat> else {
            fatalError("modified property must be declared using @Field")
        }
        
        return modified
    }
}

public extension PassKitPass {
    static func `for`(serialNumber: UUID, on db: Database) async throws -> Self {
        let pass = try await Self.query(on: db)
            .filter(\._$id == serialNumber)
            .first()
        guard let pass else {
            throw Abort(.notFound, reason: "Self: Pass for given serialNumber not found")
        }
        return pass
    }
}
