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
    /// The pass type
    var type: String { get set }
public protocol PassKitPass: Model, PassConvertible where IDValue == UUID {
    
    /// The last time the pass was modified.
    var modified: Date { get set }
    
    
    
    static func `for`(passTypeIdentifier: String, serialNumber: Self.IDValue, on db: Database) -> EventLoopFuture<Self>
}

internal extension PassKitPass {
    var _$id: ID<UUID> {
        guard let mirror = Mirror(reflecting: self).descendant("_id"),
            let id = mirror as? ID<UUID> else {
                fatalError("id property must be declared using @ID")
        }
        
        return id
    }
    
    var _$type: Field<String> {
        guard let mirror = Mirror(reflecting: self).descendant("_type"),
            let type = mirror as? Field<String> else {
                fatalError("type property must be declared using @Field")
        }
        
        return type
    }
    
    var _$modified: Field<Date> {
        guard let mirror = Mirror(reflecting: self).descendant("_modified"),
            let modified = mirror as? Field<Date> else {
                fatalError("modified property must be declared using @Field")
        }
        
        return modified
    }
    
    static func `for`(passTypeIdentifier: String, serialNumber: UUID, on db: Database) -> EventLoopFuture<Self> {
        Self.query(on: db)
            .filter(\._$id == serialNumber)
            .filter(\._$type == passTypeIdentifier)
            .first()
            .unwrap(or: Abort(.notFound))
    }
}
