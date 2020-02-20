//
//  PassKitRegistration.swift
//
//
//  Created by Pawel Rup on 20/02/2020.
//

import Vapor
import Fluent

/// Represents the `Model` that stores PassKit registrations.
public protocol PassKitRegistration: Model where IDValue == UUID {
    associatedtype PassType: PassKitPass
    associatedtype DeviceType: PassKitDevice

    /// The device for this registration.
    var device: DeviceType { get set }
    
    /// The pass for this registration.
    var pass: PassType { get set }
}

internal extension PassKitRegistration {
    var _$device: Parent<DeviceType> {
        guard let mirror = Mirror(reflecting: self).descendant("_device"),
            let device = mirror as? Parent<DeviceType> else {
                fatalError("device property must be declared using @Parent")
        }
        
        return device
    }
    
    var _$pass: Parent<PassType> {
        guard let mirror = Mirror(reflecting: self).descendant("_pass"),
            let pass = mirror as? Parent<PassType> else {
                fatalError("pass property must be declared using @Parent")
        }
        
        return pass
    }
    
    static func `for`(deviceLibraryIdentifier: String, passTypeIdentifier: String, on db: Database) -> QueryBuilder<Self> {
        Self.query(on: db)
            .join(\._$pass)
            .join(\._$device)
            .with(\._$pass)
            .with(\._$device)
            .filter(PassType.self, \._$type == passTypeIdentifier)
            .filter(DeviceType.self, \._$deviceLibraryIdentifier == deviceLibraryIdentifier)
    }
}

