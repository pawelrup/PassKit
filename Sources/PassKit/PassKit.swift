//
//  PassKit.swift
//
//
//  Created by Pawel Rup on 20/02/2020.
//

import Vapor
import APNS
import Fluent
import PassGenerator

public protocol PassKit {
    associatedtype Registration: PassKitRegistration
    associatedtype Pass: PassConvertible where Pass == Registration.PassType
    associatedtype Device where Device == Registration.DeviceType
    associatedtype ErrorLog: PassKitErrorLog
    
    var app: Application { get }
    var logger: Logger? { get }
    var pushAuthMiddleware: Middleware? { get }
    
    var wwdrURL: URL { get }
    var templateURL: URL { get }
    var certificateURL: URL { get }
    var certificatePassword: String { get }
    
    init(app: Application, logger: Logger?)
}

// MARK: - Public functions
public extension PassKit {
    
    func registerRoutes(_ routes: RoutesBuilder, authorizationCode: String? = nil) {
        let v1 = routes.grouped("v1")
        v1.get("devices", ":deviceLibraryIdentifier", "registrations", ":type", use: passesForDevice)
        v1.post("log", use: logError)
        
        guard let code = authorizationCode ?? Environment.get("PASS_KIT_AUTHORIZATION") else {
            fatalError("Must pass in an authorization code")
        }
        
        let v1auth = v1.grouped(ApplePassMiddleware(authorizationCode: code))
        v1auth.post("devices", ":deviceLibraryIdentifier", "registrations", ":type", ":passSerial", use: registerDevice)
        v1auth.get("passes", ":type", ":passSerial", use: latestVersionOfPass)
        v1auth.delete("devices", ":deviceLibraryIdentifier", "registrations", ":type", ":passSerial", use: unregisterDevice)
        
        var pushAuth = v1
        if let pushAuthMiddleware = pushAuthMiddleware {
            pushAuth = v1.grouped(pushAuthMiddleware)
        }
        pushAuth.post("push", ":type", ":passSerial", use: pushUpdatesForPass)
        pushAuth.get("push", ":type", ":passSerial", use: tokensForPassUpdate)
    }
}

// MARK: - Api routes
extension PassKit {
    
    func passesForDevice(_ req: Request) throws -> EventLoopFuture<PassesForDeviceDto> {
        logger?.debug("Called passesForDevice")
        
        let type = req.parameters.get("type")!
        let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier")!
        
        var query = Registration.for(deviceLibraryIdentifier: deviceLibraryIdentifier, passTypeIdentifier: type, on: req.db)
        
        if let since: TimeInterval = req.query["passesUpdatedSince"] {
            let when = Date(timeIntervalSince1970: since)
            query = query.filter(Pass.self, \._$modified > when)
        }
        
        return query
            .all()
            .flatMapThrowing { registrations in
                guard !registrations.isEmpty else {
                    throw Abort(.noContent)
                }
                
                var serialNumbers: [String] = []
                var maxDate = Date.distantPast
                
                registrations.forEach {
                    serialNumbers.append($0.pass.id!.uuidString)
                    if $0.pass.modified > maxDate {
                        maxDate = $0.pass.modified
                    }
                }
                
                return PassesForDeviceDto(with: serialNumbers, maxDate: maxDate)
        }
    }
    
    func logError(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        logger?.debug("Called logError")
        
        let body: ErrorLogDto
        
        do {
            body = try req.content.decode(ErrorLogDto.self)
        } catch {
            throw Abort(.badRequest)
        }
        
        guard body.logs.isEmpty == false else {
            throw Abort(.badRequest)
        }
        
        return body.logs
            .map { ErrorLog(message: $0).create(on: req.db) }
            .flatten(on: req.eventLoop)
            .map { .ok }
    }
    
    func registerDevice(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        logger?.debug("Called register device")
        
        guard let serial = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let pushToken: String
        do {
            let content = try req.content.decode(RegistrationDto.self)
            pushToken = content.pushToken
        } catch {
            throw Abort(.badRequest)
        }
        
        let type = req.parameters.get("type")!
        let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier")!
        
        return Pass.query(on: req.db)
            .filter(\._$type == type)
            .filter(\._$id == serial)
            .first()
            .unwrap(or: Abort(.notFound))
            .flatMap { pass in
                Device.query(on: req.db)
                    .filter(\._$deviceLibraryIdentifier == deviceLibraryIdentifier)
                    .filter(\._$pushToken == pushToken)
                    .first()
                    .flatMap { device in
                        if let device = device {
                            return Self.createRegistration(device: device, pass: pass, req: req)
                        } else {
                            let newDevice = Device(deviceLibraryIdentifier: deviceLibraryIdentifier, pushToken: pushToken)
                            
                            return newDevice
                                .create(on: req.db)
                                .flatMap { _ in Self.createRegistration(device: newDevice, pass: pass, req: req) }
                        }
                }
        }
    }
    
    func latestVersionOfPass(_ req: Request) throws -> EventLoopFuture<Response> {
        logger?.debug("Called latestVersionOfPass")
        
        var ifModifiedSince: TimeInterval = 0
        
        if let header = req.headers[.ifModifiedSince].first, let ims = TimeInterval(header) {
            ifModifiedSince = ims
        }
        
        guard let type = req.parameters.get("type"),
            let id = req.parameters.get("passSerial", as: UUID.self) else {
                throw Abort(.badRequest)
        }
        return Pass.for(passTypeIdentifier: type, serialNumber: id, on: req.db)
            .flatMap { pass -> EventLoopFuture<Response> in
                guard ifModifiedSince < pass.modified.timeIntervalSince1970 else {
                    return req.eventLoop.makeFailedFuture(Abort(.notModified))
                }
                return req.eventLoop.future(pass)
                    .generatePass(certificateURL: self.certificateURL, certificatePassword: self.certificatePassword, wwdrURL: self.wwdrURL, templateURL: self.templateURL)
                    .map { data in
                        let body = Response.Body(data: data)
                        
                        var headers = HTTPHeaders()
                        headers.add(name: .contentType, value: "application/vnd.apple.pkpass")
                        headers.add(name: .lastModified, value: String(pass.modified.timeIntervalSince1970))
                        headers.add(name: .contentTransferEncoding, value: "binary")
                        
                        return Response(status: .ok, headers: headers, body: body)
                }
        }
    }
    
    func unregisterDevice(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        logger?.debug("Called unregisterDevice")
        
        let type = req.parameters.get("type")!
        
        guard let passId = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier")!
        
        return Registration.for(deviceLibraryIdentifier: deviceLibraryIdentifier, passTypeIdentifier: type, on: req.db)
            .filter(Pass.self, \._$id == passId)
            .first()
            .unwrap(or: Abort(.notFound))
            .flatMap { $0.delete(on: req.db).map { .ok } }
    }
    
    func pushUpdatesForPass(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        logger?.debug("Called pushUpdatesForPass")
        
        guard let id = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let type = req.parameters.get("type")!
        
        return Self.sendPushNotificationsForPass(id: id, of: type, on: req.db, app: req.application)
            .map { _ in .noContent }
    }
    
    func tokensForPassUpdate(_ req: Request) throws -> EventLoopFuture<[String]> {
        logger?.debug("Called tokensForPassUpdate")
        
        guard let id = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let type = req.parameters.get("type")!
        
        return Self.registrationsForPass(id: id, of: type, on: req.db).map { $0.map { $0.device.pushToken } }
    }
}

// MARK: - Helpers
extension PassKit {
    
    private static func createRegistration(device: Device, pass: Pass, req: Request) -> EventLoopFuture<HTTPStatus> {
        Registration.for(deviceLibraryIdentifier: device.deviceLibraryIdentifier, passTypeIdentifier: pass.type, on: req.db)
            .filter(Pass.self, \._$id == pass.id!)
            .first()
            .flatMap { registration in
                if registration != nil {
                    // If the registration already exists, docs say to return a 200
                    return req.eventLoop.makeSucceededFuture(.ok)
                }
                
                let registration = Registration()
                registration._$pass.id = pass.id!
                registration._$device.id = device.id!
                
                return registration.create(on: req.db)
                    .map { .created }
        }
    }
}
// MARK: - Push Notifications
extension PassKit {
    
    public static func sendPushNotificationsForPass(id: UUID, of type: String, on db: Database, app: Application) -> EventLoopFuture<Void> {
        Self.registrationsForPass(id: id, of: type, on: db)
            .flatMap {
                $0.map { registration in
                    let payload = "{}".data(using: .utf8)!
                    var rawBytes = ByteBufferAllocator().buffer(capacity: payload.count)
                    rawBytes.writeBytes(payload)
                    
                    return app.apns.send(rawBytes: rawBytes, pushType: .background, to: registration.device.pushToken, topic: registration.pass.type)
                        .flatMapError {
                            // Unless APNs said it was a bad device token, just ignore the error.
                            guard case let APNSwiftError.ResponseError.badRequest(response) = $0, response == .badDeviceToken else {
                                return db.eventLoop.future()
                            }
                            
                            // Be sure the device deletes before the registration is deleted.
                            // If you let them run in parallel issues might arise depending on
                            // the hooks people have set for when a registration deletes, as it
                            // might try to delete the same device again.
                            return registration.device.delete(on: db)
                                .flatMapError { _ in db.eventLoop.future() }
                                .flatMap { registration.delete(on: db) }
                    }
                }
                .flatten(on: db.eventLoop)
        }
    }
    
    public static func sendPushNotifications(for pass: Pass, on db: Database, app: Application) -> EventLoopFuture<Void> {
        guard let id = pass.id else {
            return db.eventLoop.makeFailedFuture(FluentError.idRequired)
        }
        
        return Self.sendPushNotificationsForPass(id: id, of: pass.type, on: db, app: app)
    }
    
    private static func registrationsForPass(id: UUID, of type: String, on db: Database) -> EventLoopFuture<[Registration]> {
        // This could be done by enforcing the caller to have a Siblings property
        // wrapper, but there's not really any value to forcing that on them when
        // we can just do the query ourselves like this.
        Registration.query(on: db)
            .join(\._$pass)
            .join(\._$device)
            .with(\._$pass)
            .with(\._$device)
            .filter(Pass.self, \._$type == type)
            .filter(Pass.self, \._$id == id)
            .all()
    }
}
