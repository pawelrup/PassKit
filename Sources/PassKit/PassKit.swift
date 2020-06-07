//
//  PassKit.swift
//
//
//  Created by Pawel Rup on 20/02/2020.
//

import Vapor
import Fluent
import APNS

public struct PassKitConfiguration {
    let pushAuthMiddleware: Middleware?
    let fetchers: [String: AnyDatabaseFetcher]
    
    public init(pushAuthMiddleware: Middleware? = nil, fetchers: [String: AnyDatabaseFetcher]) {
        self.pushAuthMiddleware = pushAuthMiddleware
        self.fetchers = fetchers
    }
}

extension Application {
    public var passKit: PassKit {
        .init(application: self)
    }
    
    public struct PassKit {
        struct ConfigurationKey: StorageKey {
            typealias Value = PassKitConfiguration
        }
        private let application: Application

        public var configuration: PassKitConfiguration? {
            get {
                self.application.storage[ConfigurationKey.self]
            }
            nonmutating set {
                self.application.storage[ConfigurationKey.self] = newValue
            }
        }
        var fetchers: [String: AnyDatabaseFetcher] {
            guard let configuration = self.configuration else {
                fatalError("PassKit not configured. Use app.passKit.configuration = ...")
            }
            return configuration.fetchers
        }
        
        public init(application: Application) {
            self.application = application
        }
    }
}

// MARK: - Public functions
public extension Application.PassKit {
    
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
extension Application.PassKit {
    
    func passesForDevice(_ req: Request) throws -> EventLoopFuture<PassesForDeviceDto> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called passesForDevice")
        
        guard let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier"),
            let passTypeIdentifier = req.parameters.get("passTypeIdentifier") else {
                throw Abort(.badRequest)
        }
        let passesUpdatedSince = req.parameters.get("passesUpdatedSince", as: TimeInterval.self)
        
        return try fetchers.get(for: passTypeIdentifier)
            .registrations(forDeviceLibraryIdentifier: deviceLibraryIdentifier, passesUpdatedSince: passesUpdatedSince, on: req.db)
    }
    
    func logError(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called logError")
        
        let body: ErrorLogDto
        
        do {
            body = try req.content.decode(ErrorLogDto.self)
        } catch {
            throw Abort(.badRequest)
        }
        
        guard body.logs.isEmpty == false else {
            throw Abort(.badRequest)
        }
        
        return req.eventLoop.future()
            .map { self.fetchers.first?.value }
            .unwrap(or: Abort(.notFound, reason: "Fetcher not found. Weird…"))
            .flatMap { $0.saveLogs(body.logs, on: req.db) }
            .map { .ok }
    }
    
    func getAllErrors(_ req: Request) throws -> EventLoopFuture<[String]> {
        return req.eventLoop.future()
            .map { self.fetchers.first?.value }
            .unwrap(or: Abort(.notFound, reason: "Detcher not found. Weird…"))
            .flatMap { $0.getAllLogs(on: req.db) }
    }
    
    func deleteAllErrors(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        return req.eventLoop.future()
            .map { self.fetchers.first?.value }
            .unwrap(or: Abort(.notFound, reason: "Detcher not found. Weird…"))
            .flatMap { $0.deleteAllLogs(on: req.db, with: req.eventLoop) }
    }
    
    func registerDevice(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called registerDevice")
        
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
        
        return try fetchers.get(for: passTypeIdentifier)
            .registerDevice(deviceLibraryIdentifier: deviceLibraryIdentifier, serialNumber: serialNumber, pushToken: pushToken, on: req.db, with: req.eventLoop)
    }
    
    func latestVersionOfPass(_ req: Request) throws -> EventLoopFuture<Response> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called latestVersionOfPass")
        let ifModifiedSince = req.headers[.ifModifiedSince].first.flatMap({ TimeInterval($0) }) ?? 0
        guard let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        return try fetchers.get(for: passTypeIdentifier)
            .latestVersionOfPass(serialNumber: serialNumber, ifModifiedSince: ifModifiedSince, on: req.db, with: req.eventLoop)
    }
    
    func unregisterDevice(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called unregisterDevice")
        
        guard let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier"),
            let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        
        return try fetchers.get(for: passTypeIdentifier)
            .unregisterDevice(deviceLibraryIdentifier: deviceLibraryIdentifier, serialNumber: serialNumber, on: req.db)
    }
    
    func pushUpdatesForPass(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called pushUpdatesForPass")
        
        guard let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        
        return try sendPushNotificationsForPass(id: serialNumber, of: passTypeIdentifier, on: req.db)
            .map { _ in .noContent }
    }
    
    func tokensForPassUpdate(_ req: Request) throws -> EventLoopFuture<[String]> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called tokensForPassUpdate")
        
        guard let passTypeIdentifier = req.parameters.get("passTypeIdentifier"),
            let serialNumber = req.parameters.get("serialNumber", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        
        return try fetchers.get(for: passTypeIdentifier)
            .tokensForPass(id: serialNumber, on: req.db)
    }
}

// MARK: - Push Notifications
extension Application.PassKit {
    
    public func sendPushNotificationsForPass(id: UUID, of type: String, on db: Database) throws -> EventLoopFuture<Void> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called sendPushNotificationsForPass")
        
        return try fetchers.get(for: type)
            .sendPushNotificationsForPass(id: id, type: type, on: db, using: application.apns)
    }
    
    public func sendPushNotifications<Pass: PassKitPass>(for pass: Pass, of type: String, on db: Database) throws -> EventLoopFuture<Void> {
        application.logger.info("[ PassKit ] 👨‍🔧 Called sendPushNotifications")
        guard let id = pass.id else {
            return db.eventLoop.makeFailedFuture(FluentError.idRequired)
        }
        return try sendPushNotificationsForPass(id: id, of: type, on: db)
    }
}
