//
//  PassKitDevice.swift
//
//
//  Created by Pawel Rup on 20/02/2020.
//

import Vapor
import Fluent

/// Represents the `Model` that stores PassKit devices.
public protocol PassKitDevice: Model where IDValue == UUID {
    /// The push token used for sending updates to the device.
    var pushToken: String { get set }
    
    /// The identifier PassKit provides for the device.
    var deviceLibraryIdentifier: String { get set }
    
    /// The designated initializer.
    /// - Parameters:
    ///   - deviceLibraryIdentifier: The device identifier as provided during registration.
    ///   - pushToken: The push token to use when sending updates via push notifications.
    init(deviceLibraryIdentifier: String, pushToken: String)
}

internal extension PassKitDevice {
    var _$id: ID<UUID> {
        guard let mirror = Mirror(reflecting: self).descendant("_id"),
            let id = mirror as? ID<UUID> else {
                fatalError("id property must be declared using @ID")
        }
        
        return id
    }
    
    var _$pushToken: Field<String> {
        guard let mirror = Mirror(reflecting: self).descendant("_pushToken"),
            let pushToken = mirror as? Field<String> else {
                fatalError("pushToken property must be declared using @Field")
        }
        
        return pushToken
    }
    
    var _$deviceLibraryIdentifier: Field<String> {
        guard let mirror = Mirror(reflecting: self).descendant("_deviceLibraryIdentifier"),
            let deviceLibraryIdentifier = mirror as? Field<String> else {
                fatalError("deviceLibraryIdentifier property must be declared using @Field")
        }
        
        return deviceLibraryIdentifier
    }
}

