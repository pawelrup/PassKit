import Vapor
import Fluent
import APNS

public struct PassKitConfiguration {
    let pushAuthMiddleware: Middleware?
    let fetchers: [String: any PassKitDatabaseFetcher]
    
    public init(pushAuthMiddleware: Middleware? = nil, fetchers: [String: any PassKitDatabaseFetcher]) {
        self.pushAuthMiddleware = pushAuthMiddleware
        self.fetchers = fetchers
    }
}

extension Dictionary where Value == any PassKitDatabaseFetcher {
    func get(for key: Key) throws -> Value {
        guard let value = self[key] else {
            throw Abort(.notFound)
        }
        return value
    }
}

public protocol PassKitType {
    var configuration: PassKitConfiguration? { get nonmutating set }
    var fetchers: [String: any PassKitDatabaseFetcher] { get }
    var logger: Logger { get }
    var apns: Application.APNS { get }
    
    func registerRoutes(_ routes: RoutesBuilder, authorizationCode: String?)
}

extension Application {
    public var passKit: PassKitType {
        PassKit(application: self)
    }
    
    public struct PassKit: PassKitType {
        struct ConfigurationKey: StorageKey {
            typealias Value = PassKitConfiguration
        }
        private let application: Application

        public var configuration: PassKitConfiguration? {
            get {
                application.storage[ConfigurationKey.self]
            }
            nonmutating set {
                application.storage[ConfigurationKey.self] = newValue
            }
        }
        public var fetchers: [String: any PassKitDatabaseFetcher] {
            guard let configuration = self.configuration else {
                fatalError("PassKit not configured. Use app.passKit.configuration = ...")
            }
            return configuration.fetchers
        }
        public var logger: Logger {
            application.logger
        }
        public var apns: Application.APNS {
            application.apns
        }
        
        public init(application: Application) {
            self.application = application
        }
    }
}

// MARK: - Public functions
public extension PassKitType {
    func registerRoutes(_ routes: RoutesBuilder, authorizationCode: String? = nil) {
        let v1 = routes.grouped("v1")
        v1.get("devices", ":deviceLibraryIdentifier", "registrations", ":passTypeIdentifier", use: passesForDevice)
        v1.post("log", use: logError)
        v1.get("log", use: getAllErrors)
        v1.delete("log", use: deleteAllErrors)
        
        guard let code = authorizationCode ?? Environment.get("PASS_KIT_AUTHORIZATION") else {
            fatalError("Must pass in an authorization code")
        }
        
        let v1auth = v1.grouped(ApplePassMiddleware(authorizationCode: code))
        v1auth.post("devices", ":deviceLibraryIdentifier", "registrations", ":passTypeIdentifier", ":serialNumber", use: registerDevice)
        v1auth.get("passes", ":passTypeIdentifier", ":serialNumber", use: latestVersionOfPass)
        v1auth.delete("devices", ":deviceLibraryIdentifier", "registrations", ":passTypeIdentifier", ":serialNumber", use: unregisterDevice)
        
        var pushAuth = v1
        if let pushAuthMiddleware = configuration?.pushAuthMiddleware {
            pushAuth = v1.grouped(pushAuthMiddleware)
        }
        pushAuth.post("push", ":passTypeIdentifier", ":serialNumber", use: pushUpdatesForPass)
        pushAuth.get("push", ":passTypeIdentifier", ":serialNumber", use: tokensForPassUpdate)
    }
}

// MARK: - Api routes
extension PassKitType {
    
    func passesForDevice(_ req: Request) async throws -> PassesForDeviceDto {
        logger.info("[ PassKit ] 👨‍🔧 Called passesForDevice")
        guard let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier"),
            let passTypeIdentifier = req.parameters.get("passTypeIdentifier") else {
                throw Abort(.badRequest)
        }
        let passesUpdatedSince = req.parameters.get("passesUpdatedSince", as: TimeInterval.self)
        return try await fetchers.get(for: passTypeIdentifier)
            .registrations(forDeviceLibraryIdentifier: deviceLibraryIdentifier, passesUpdatedSince: passesUpdatedSince, on: req.db)
    }
    
    func logError(_ req: Request) async throws -> HTTPStatus {
        logger.info("[ PassKit ] 👨‍🔧 Called logError")
        let body: ErrorLogDto
        
        do {
            body = try req.content.decode(ErrorLogDto.self)
        } catch {
            throw Abort(.badRequest)
        }
        
        guard body.logs.isEmpty == false else {
            throw Abort(.badRequest)
        }
        guard let fetcher = fetchers.first?.value else {
            throw Abort(.notFound, reason: "Fetcher not found. Weird…")
        }
        try await fetcher.saveLogs(body.logs, on: req.db)
        return .ok
    }
    
    func getAllErrors(_ req: Request) async throws -> [String] {
        guard let fetcher = fetchers.first?.value else {
            throw Abort(.notFound, reason: "Fetcher not found. Weird…")
        }
        return try await fetcher.getAllLogs(on: req.db)
    }
    
    func deleteAllErrors(_ req: Request) async throws -> HTTPStatus {
        guard let fetcher = fetchers.first?.value else {
            throw Abort(.notFound, reason: "Fetcher not found. Weird…")
        }
        return try await fetcher.deleteAllLogs(on: req.db)
    }
    
    func registerDevice(_ req: Request) async throws -> HTTPStatus {
        logger.info("[ PassKit ] 👨‍🔧 Called registerDevice")
        
        guard let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier"),
            let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        
        let pushToken: String
        do {
            let content = try req.content.decode(RegistrationDto.self)
            pushToken = content.pushToken
        } catch {
            throw Abort(.badRequest)
        }
        
        return try await fetchers.get(for: passTypeIdentifier)
            .registerDevice(deviceLibraryIdentifier: deviceLibraryIdentifier, serialNumber: serialNumber, pushToken: pushToken, on: req.db)
    }
    
    func latestVersionOfPass(_ req: Request) async throws -> Response {
        logger.info("[ PassKit ] 👨‍🔧 Called latestVersionOfPass")
        let ifModifiedSince = req.headers[.ifModifiedSince].first.flatMap({ TimeInterval($0) }) ?? 0
        guard let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        return try await fetchers.get(for: passTypeIdentifier)
            .latestVersionOfPass(serialNumber: serialNumber, ifModifiedSince: ifModifiedSince, on: req.db)
    }
    
    func unregisterDevice(_ req: Request) async throws -> HTTPStatus {
        logger.info("[ PassKit ] 👨‍🔧 Called unregisterDevice")
        
        guard let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier"),
            let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        
        return try await fetchers.get(for: passTypeIdentifier)
            .unregisterDevice(deviceLibraryIdentifier: deviceLibraryIdentifier, serialNumber: serialNumber, on: req.db)
    }
    
    func pushUpdatesForPass(_ req: Request) async throws -> HTTPStatus {
        logger.info("[ PassKit ] 👨‍🔧 Called pushUpdatesForPass")
        
        guard let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        
        try await sendPushNotificationsForPass(id: serialNumber, of: passTypeIdentifier, on: req.db)
        return .noContent
    }
    
    func tokensForPassUpdate(_ req: Request) async throws -> [String] {
        logger.info("[ PassKit ] 👨‍🔧 Called tokensForPassUpdate")
        
        guard let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        
        return try await fetchers.get(for: passTypeIdentifier)
            .tokensForPass(id: serialNumber, on: req.db)
    }
}

// MARK: - Push Notifications
extension PassKitType {
    
    public func sendPushNotificationsForPass(id: UUID, of type: String, on db: Database) async throws {
        logger.info("[ PassKit ] 👨‍🔧 Called sendPushNotificationsForPass")
        
        return try await fetchers.get(for: type)
            .sendPushNotificationsForPass(id: id, type: type, on: db, using: apns)
    }
    
    public func sendPushNotifications<Pass: PassKitPass>(for pass: Pass, of type: String, on db: Database) async throws {
        logger.info("[ PassKit ] 👨‍🔧 Called sendPushNotifications")
        guard let id = pass.id else {
            throw FluentError.idRequired
        }
        return try await sendPushNotificationsForPass(id: id, of: type, on: db)
    }
}
