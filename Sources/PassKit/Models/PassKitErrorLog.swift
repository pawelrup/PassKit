import Vapor
import Fluent

/// Represents the `Model` that stores PassKit error logs.
public protocol PassKitErrorLog: Model {
    /// The error message provided by PassKit
    var message: String { get set }
    
    /// The designated initializer
    /// - Parameter message: The error message.
    init(message: String)
}

internal extension PassKitErrorLog {
    var _$message: Field<String> {
        guard let mirror = Mirror(reflecting: self).descendant("_message"),
            let message = mirror as? Field<String> else {
                fatalError("id property must be declared using @ID")
        }
        
        return message
    }
}
