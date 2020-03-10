//
//  PassKitPass.swift
//
//
//  Created by Pawel Rup on 20/02/2020.
//

import Vapor
import Fluent
import PassGenerator

/// Represents the `Model` that stores PassKit passes.
public protocol PassKitPass: Model, PassConvertible where IDValue == UUID {
    
    /// The last time the pass was modified.
    var modified: Date { get set }
    
    static func `for`(serialNumber: UUID, on db: Database) -> EventLoopFuture<Self>
}

internal extension PassKitPass {
    var _$id: ID<UUID> {
        guard let mirror = Mirror(reflecting: self).descendant("_id"),
            let id = mirror as? ID<UUID> else {
                fatalError("id property must be declared using @ID")
        }
        
        return id
    }
    
    var _$modified: Field<Date> {
        guard let mirror = Mirror(reflecting: self).descendant("_modified"),
            let modified = mirror as? Field<Date> else {
                fatalError("modified property must be declared using @Field")
        }
        
        return modified
    }
    
    static func `for`(serialNumber: UUID, on db: Database) -> EventLoopFuture<Self> {
        Self.query(on: db)
            .filter(\._$id == serialNumber)
            .first()
            .unwrap(or: Abort(.notFound, reason: "Self: Pass for given serialNumber not found"))
    }
}
