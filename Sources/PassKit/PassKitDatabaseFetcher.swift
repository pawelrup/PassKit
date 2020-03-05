//
//  PassKitDatabaseFetcher.swift
//  
//
//  Created by Pawel Rup on 27/02/2020.
//

import Vapor
import Fluent
import APNS
import PassGenerator

public protocol PassKitDatabaseFetcher {
    associatedtype Registration: PassKitRegistration
    associatedtype Pass where Pass == Registration.PassType
    associatedtype Device where Device == Registration.DeviceType
    associatedtype ErrorLog: PassKitErrorLog
    
    var wwdrURL: URL { get }
    var templateURL: URL { get }
    var certificateURL: URL { get }
    var certificatePassword: String { get }
}

extension PassKitDatabaseFetcher {
    
    func registrations(forDeviceLibraryIdentifier deviceLibraryIdentifier: String, passesUpdatedSince: TimeInterval?, on db: Database) -> EventLoopFuture<PassesForDeviceDto> {
        var query = Registration.for(deviceLibraryIdentifier: deviceLibraryIdentifier, on: db)
        
        if let since = passesUpdatedSince {
            let when = Date(timeIntervalSince1970: since)
            query = query.filter(Pass.self, \._$modified > when)
        }
        
        return query.all()
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
    
    func saveLogs(_ logs: [String], on db: Database) -> EventLoopFuture<Void> {
        return logs
            .map { ErrorLog(message: $0).create(on: db) }
            .flatten(on: db.eventLoop)
    }
    
    func getAllLogs(on db: Database) -> EventLoopFuture<[String]> {
        return ErrorLog.query(on: db)
            .all()
            .mapEach { $0.message }
    }
    
    func registerDevice(deviceLibraryIdentifier: String, serialNumber: UUID, pushToken: String, on db: Database, with eventLoop: EventLoop) throws -> EventLoopFuture<HTTPStatus> {
        Pass.query(on: db)
            .filter(\._$id == serialNumber)
            .first()
            .unwrap(or: Abort(.notFound))
            .flatMap { pass in
                Device.query(on: db)
                    .filter(\._$deviceLibraryIdentifier == deviceLibraryIdentifier)
                    .filter(\._$pushToken == pushToken)
                    .first()
                    .flatMap { device in
                        if let device = device {
                            return Self.createRegistration(device: device, pass: pass, on: db, with: eventLoop)
                        } else {
                            let newDevice = Device(deviceLibraryIdentifier: deviceLibraryIdentifier, pushToken: pushToken)
                            
                            return newDevice
                                .create(on: db)
                                .flatMap { _ in Self.createRegistration(device: newDevice, pass: pass, on: db, with: eventLoop) }
                        }
                }
        }
    }
    
    func unregisterDevice(deviceLibraryIdentifier: String, serialNumber: UUID, on db: Database) -> EventLoopFuture<HTTPStatus> {
        return Registration.for(deviceLibraryIdentifier: deviceLibraryIdentifier, on: db)
            .filter(Pass.self, \._$id == serialNumber)
            .first()
            .unwrap(or: Abort(.notFound, reason: "Pass for given serial not found."))
            .flatMap { $0.delete(on: db).map { .ok } }
    }
    
    func latestVersionOfPass(serialNumber: UUID, ifModifiedSince: TimeInterval, on db: Database, with eventLoop: EventLoop) -> EventLoopFuture<Response> {
        return Pass.for(serialNumber: serialNumber, on: db)
            .flatMap { pass -> EventLoopFuture<Response> in
                guard ifModifiedSince < pass.modified.timeIntervalSince1970 else {
                    return eventLoop.makeFailedFuture(Abort(.notModified))
                }
                return eventLoop.future(pass)
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
    
    func tokensForPass(id: UUID, on db: Database) -> EventLoopFuture<[String]> {
        registrationsForPass(id: id, on: db)
            .map { $0.map { $0.device.pushToken } }
    }
    
    func sendPushNotificationsForPass(id: UUID, type: String, on db: Database, using apns: Application.APNS) throws -> EventLoopFuture<Void> {
        registrationsForPass(id: id, on: db)
            .flatMap {
                $0.map { registration in
                    let payload = "{}".data(using: .utf8)!
                    var rawBytes = ByteBufferAllocator().buffer(capacity: payload.count)
                    rawBytes.writeBytes(payload)
                    
                    return apns.send(rawBytes: rawBytes, pushType: .background, to: registration.device.pushToken, topic: type)
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
}

extension PassKitDatabaseFetcher {
    
    private func registrationsForPass(id: UUID, on db: Database) -> EventLoopFuture<[Registration]> {
        Registration.query(on: db)
            .join(Pass.self, on: \Registration._$pass.$id == \Pass._$id)
            .join(Device.self, on: \Registration._$device.$id == \Device._$id)
            .with(\._$pass)
            .with(\._$device)
            .filter(Pass.self, \._$id == id)
            .all()
    }
    
    private static func createRegistration(device: Device, pass: Pass, on db: Database, with eventLoop: EventLoop) -> EventLoopFuture<HTTPStatus> {
        Registration.for(deviceLibraryIdentifier: device.deviceLibraryIdentifier, on: db)
            .filter(Pass.self, \._$id == pass.id!)
            .first()
            .flatMap { registration in
                if registration != nil {
                    // If the registration already exists, docs say to return a 200
                    return eventLoop.makeSucceededFuture(.ok)
                }
                
                let registration = Registration()
                registration._$pass.id = pass.id!
                registration._$device.id = device.id!
                
                return registration.create(on: db)
                    .map { .created }
        }
    }
}

extension Dictionary where Value == AnyDatabaseFetcher {
    
    func get(for key: Key) throws-> Value {
        guard let value = self[key] else {
            throw Abort(.notFound)
        }
        return value
    }
}

// Type erasure wrapper class
public struct AnyDatabaseFetcher {
    public let wwdrURL: URL
    public let templateURL: URL
    public let certificateURL: URL
    public let certificatePassword: String
    
    private let _registrations: (_ deviceLibraryIdentifier: String, _ passesUpdatedSince: TimeInterval?, _ db: Database) -> EventLoopFuture<PassesForDeviceDto>
    private let _saveLogs: (_ logs: [String], _ db: Database) -> EventLoopFuture<Void>
    private let _getAllLogs: (_ db: Database) -> EventLoopFuture<[String]>
    private let _registerDevice: (_ deviceLibraryIdentifier: String, _ serialNumber: UUID, _ pushToken: String, _ db: Database, _ eventLoop: EventLoop) throws -> EventLoopFuture<HTTPStatus>
    private let _unregisterDevice: (_ deviceLibraryIdentifier: String, _ serialNumber: UUID, _ db: Database) -> EventLoopFuture<HTTPStatus>
    private let _latestVersionOfPass: (_ serialNumber: UUID, _ ifModifiedSince: TimeInterval, _ db: Database, _ eventLoop: EventLoop) -> EventLoopFuture<Response>
    private let _tokensForPass: (_ id: UUID, _ db: Database) -> EventLoopFuture<[String]>
    private let _sendPushNotificationsForPass: (_ id: UUID, _ type: String, _ db: Database, _ apns: Application.APNS) throws -> EventLoopFuture<Void>
    
    public init<DatabaseFetcher: PassKitDatabaseFetcher>(_ databaseFetcher: DatabaseFetcher) {
        self.wwdrURL = databaseFetcher.wwdrURL
        self.templateURL = databaseFetcher.templateURL
        self.certificateURL = databaseFetcher.certificateURL
        self.certificatePassword = databaseFetcher.certificatePassword
        
        _registrations = databaseFetcher.registrations
        _saveLogs = databaseFetcher.saveLogs
        _getAllLogs = databaseFetcher.getAllLogs
        _registerDevice = databaseFetcher.registerDevice
        _unregisterDevice = databaseFetcher.unregisterDevice
        _latestVersionOfPass = databaseFetcher.latestVersionOfPass
        _tokensForPass = databaseFetcher.tokensForPass
        _sendPushNotificationsForPass = databaseFetcher.sendPushNotificationsForPass
    }
    
    func registrations(forDeviceLibraryIdentifier deviceLibraryIdentifier: String, passesUpdatedSince: TimeInterval?, on db: Database) -> EventLoopFuture<PassesForDeviceDto> {
        _registrations(deviceLibraryIdentifier, passesUpdatedSince, db)
    }
    
    func saveLogs(_ logs: [String], on db: Database) -> EventLoopFuture<Void> {
        _saveLogs(logs, db)
    }
    
    func getAllLogs(on db: Database) -> EventLoopFuture<[String]> {
        _getAllLogs(db)
    }
    
    func registerDevice(deviceLibraryIdentifier: String, serialNumber: UUID, pushToken: String, on db: Database, with eventLoop: EventLoop) throws -> EventLoopFuture<HTTPStatus> {
        try _registerDevice(deviceLibraryIdentifier, serialNumber, pushToken, db, eventLoop)
    }
    
    func unregisterDevice(deviceLibraryIdentifier: String, serialNumber: UUID, on db: Database) -> EventLoopFuture<HTTPStatus> {
        _unregisterDevice(deviceLibraryIdentifier, serialNumber, db)
    }
    
    func latestVersionOfPass(serialNumber: UUID, ifModifiedSince: TimeInterval, on db: Database, with eventLoop: EventLoop) -> EventLoopFuture<Response> {
        _latestVersionOfPass(serialNumber, ifModifiedSince, db, eventLoop)
    }
    
    func tokensForPass(id: UUID, on db: Database) -> EventLoopFuture<[String]> {
        _tokensForPass(id, db)
    }
    
    func sendPushNotificationsForPass(id: UUID, type: String, on db: Database, using apns: Application.APNS) throws -> EventLoopFuture<Void> {
        try _sendPushNotificationsForPass(id, type, db, apns)
    }
}
