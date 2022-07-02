import Vapor
import Fluent
import APNS
import PassGenerator

public protocol PassKitDatabaseFetcher {
    associatedtype Registration: PassKitRegistration
    associatedtype Pass where Pass == Registration.PassType
    associatedtype Device where Device == Registration.DeviceType
    associatedtype ErrorLog: PassKitErrorLog
    
    var logger: Logger { get }
    var directoryConfiguration: DirectoryConfiguration { get }
    
    var wwdrURL: URL { get }
    var templateURL: URL { get }
    var certificateURL: URL { get }
    var certificatePassword: String { get }
    
    func registrations(forDeviceLibraryIdentifier deviceLibraryIdentifier: String, passesUpdatedSince: TimeInterval?, on db: Database) async throws -> PassesForDeviceDto
    func saveLogs(_ logs: [String], on db: Database) async throws
    func getAllLogs(on db: Database) async throws -> [String]
    func deleteAllLogs(on db: Database) async throws -> HTTPStatus
    func registerDevice(deviceLibraryIdentifier: String, serialNumber: UUID, pushToken: String, on db: Database) async throws -> HTTPStatus
    func unregisterDevice(deviceLibraryIdentifier: String, serialNumber: UUID, on db: Database) async throws -> HTTPStatus
    func latestVersionOfPass(serialNumber: UUID, ifModifiedSince: TimeInterval, on db: Database) async throws -> Response
    func tokensForPass(id: UUID, on db: Database) async throws -> [String]
    func sendPushNotificationsForPass(id: UUID, type: String, on db: Database, using apns: Application.APNS) async throws
}

public extension PassKitDatabaseFetcher {
    
    private func fileExists(at path: String, isDirectory: Bool = false) -> Bool {
        var isDirectory = ObjCBool(isDirectory)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    }
    
    func registrations(forDeviceLibraryIdentifier deviceLibraryIdentifier: String, passesUpdatedSince: TimeInterval?, on db: Database) async throws -> PassesForDeviceDto {
        var query = Registration.for(deviceLibraryIdentifier: deviceLibraryIdentifier, on: db)
        
        if let since = passesUpdatedSince {
            let when = Date(timeIntervalSince1970: since)
            query = query.filter(Pass.self, \._$modified > when)
        }
        
        let registrations: [Registration] = try await query.all()
        guard !registrations.isEmpty else {
            throw Abort(.noContent)
        }
        
        var serialNumbers: [String] = []
        var maxDate = Date.distantPast
        
        registrations.forEach {
            serialNumbers.append($0.pass.id!.uuidString)
            if $0.pass.modified ?? Date.distantPast > maxDate {
                maxDate = $0.pass.modified ?? Date.distantPast
            }
        }
        
        return PassesForDeviceDto(with: serialNumbers, maxDate: maxDate)
    }
    
    func saveLogs(_ logs: [String], on db: Database) async throws {
        let errors = logs.map(ErrorLog.init)
        try await errors.create(on: db)
    }
    
    func getAllLogs(on db: Database) async throws -> [String] {
        try await ErrorLog.query(on: db).all().map(\.message)
    }
    
    func deleteAllLogs(on db: Database) async throws -> HTTPStatus {
        let logs = try await ErrorLog.query(on: db).all()
        for log in logs {
            try await log.delete(on: db)
        }
        return .noContent
    }
    
    func registerDevice(deviceLibraryIdentifier: String, serialNumber: UUID, pushToken: String, on db: Database) async throws -> HTTPStatus {
        let pass = try await Pass.query(on: db)
            .filter(\._$id == serialNumber)
            .first()
        guard let pass else {
            throw Abort(.notFound, reason: "[ PassKitDatabaseFetcher ] 👨‍🔧 registerDevice: Pass with given serial number not found.")
        }
        let device = try await Device.query(on: db)
            .filter(\._$deviceLibraryIdentifier == deviceLibraryIdentifier)
            .filter(\._$pushToken == pushToken)
            .first()
        
        if let device {
            logger.debug("[ PassKitDatabaseFetcher ] 👨‍🔧 registerDevice: Device exists, creating new registration")
            return try await Self.createRegistration(device: device, pass: pass, on: db)
        } else {
            logger.debug("[ PassKitDatabaseFetcher ] 👨‍🔧 registerDevice: Creating new device and registration")
            let newDevice = Device(deviceLibraryIdentifier: deviceLibraryIdentifier, pushToken: pushToken)
            
            try await newDevice.create(on: db)
            return try await Self.createRegistration(device: newDevice, pass: pass, on: db)
        }
    }
    
    func unregisterDevice(deviceLibraryIdentifier: String, serialNumber: UUID, on db: Database) async throws -> HTTPStatus {
        let registration = try await Registration.for(deviceLibraryIdentifier: deviceLibraryIdentifier, on: db)
            .filter(Pass.self, \._$id == serialNumber)
            .first()
        guard let registration else {
            throw Abort(.notFound, reason: "unregisterDevice: Pass with serialNumber for deviceLibraryIdentifier not found.")
        }
        try await registration.delete(on: db)
        return .ok
    }
    
    func latestVersionOfPass(serialNumber: UUID, ifModifiedSince: TimeInterval, on db: Database) async throws -> Response {
        logger.debug("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: Try return latest version of pass.")
        let workingDirectoryURL = URL(fileURLWithPath: directoryConfiguration.workingDirectory, isDirectory: true)
        guard fileExists(at: workingDirectoryURL.path, isDirectory: true) else {
            logger.error("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: Working directory does not exist.")
            throw Abort(.notFound, reason: "Working directory does not exist.")
        }
        guard fileExists(at: certificateURL.path) else {
            logger.error("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: Certificate does not exist at path \(certificateURL.path)")
            throw Abort(.notFound, reason: "Certificate does not exist.")
        }
        guard fileExists(at: wwdrURL.path) else {
            logger.error("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: WWDR does not exist at path \(wwdrURL.path)")
            throw Abort(.notFound, reason: "WWDR does not exist.")
        }
        guard fileExists(at: templateURL.path) else {
            logger.error("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: Template does not exist at path \(templateURL.path)")
            throw Abort(.notFound, reason: "Template does not exist.")
        }
        let pass = try await Pass.for(serialNumber: serialNumber, on: db)
        logger.debug("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: Successfully loaded latest version of pass from db")
        guard ifModifiedSince < (pass.modified ?? Date.distantPast).timeIntervalSince1970 else {
            logger.warning("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: Pass wasn't modified since value \"ifModifiedSince\".")
            throw Abort(.notModified, reason: "latestVersionOfPass: Pass wasn't modified since value \"ifModifiedSince\".")
        }
        logger.debug("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: Try generate pass…")
        
        let generatorConfiguration = PassGeneratorConfiguration(
            certificate: .init(url: certificateURL, password: certificatePassword),
            wwdrURL: wwdrURL,
            templateURL: templateURL)
        let generator = PassGenerator(configuration: generatorConfiguration, logger: logger)
        let data = try await generator.generatePass(pass.pass)
        logger.debug("[ PassKitDatabaseFetcher ] 👨‍🔧 latestVersionOfPass: Successfully generated pass")
        let body = Response.Body(data: data)
        
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/vnd.apple.pkpass")
        headers.add(name: .lastModified, value: String((pass.modified ?? Date.distantPast).timeIntervalSince1970))
        headers.add(name: .contentTransferEncoding, value: "binary")
        
        return Response(status: .ok, headers: headers, body: body)
    }
    
    func tokensForPass(id: UUID, on db: Database) async throws -> [String] {
        try await registrationsForPass(id: id, on: db)
            .map { $0.device.pushToken }
    }
    
    func sendPushNotificationsForPass(id: UUID, type: String, on db: Database, using apns: Application.APNS) async throws {
        let destinationURL = URL(fileURLWithPath: directoryConfiguration.workingDirectory, isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: false)
        let pemCertURL = destinationURL.appendingPathComponent("cert.pem")
        let pemKeyURL = destinationURL.appendingPathComponent("key.pem")
        var oldConfiguration: APNSwiftConfiguration?
        
        try await generatePemCertificate(from: certificateURL, with: certificatePassword, to: pemCertURL)
        try await generatePemKey(from: certificateURL, with: certificatePassword, to: pemKeyURL)
        
        defer {
            logger.debug("[ PassKitDatabaseFetcher ] 👨‍🔧 sendPushNotificationsForPass: Change back apns configuration and remove pem key and cert")
            apns.configuration = oldConfiguration
            try? FileManager.default.removeItem(at: destinationURL)
        }
        logger.debug("[ PassKitDatabaseFetcher ] 👨‍🔧 sendPushNotificationsForPass: Change apns configuration to passkit certs")
        oldConfiguration = apns.configuration
        let authenticationMethod = try APNSwiftConfiguration.AuthenticationMethod.tls(privateKeyPath: pemKeyURL.path, pemPath: pemCertURL.path, pemPassword: certificatePassword.bytes)
        let apnsConfig = APNSwiftConfiguration(authenticationMethod: authenticationMethod, topic: "", environment: .production, logger: logger)
        apns.configuration = apnsConfig
        
        let registrations = try await registrationsForPass(id: id, on: db)
        for registration in registrations {
            let payload = "{}".data(using: .utf8)!
            var rawBytes = ByteBufferAllocator().buffer(capacity: payload.count)
            rawBytes.writeBytes(payload)
            do {
                try await apns.send(rawBytes: rawBytes, pushType: .background, to: registration.device.pushToken, expiration: nil, priority: nil, collapseIdentifier: nil, topic: type, logger: logger)
            } catch {
                // Unless APNs said it was a bad device token, just ignore the error.
                if case let APNSwiftError.ResponseError.badRequest(response) = error, response == .badDeviceToken {
                    logger.warning("[ PassKitDatabaseFetcher ] 👨‍🔧 Failed to send push. Deleting registration.")
                    
                    // Be sure the device deletes before the registration is deleted.
                    // If you let them run in parallel issues might arise depending on
                    // the hooks people have set for when a registration deletes, as it
                    // might try to delete the same device again.
                    try? await registration.device.delete(on: db)
                    try? await registration.delete(on: db)
                }
            }
        }
    }
    
    /// Generate a pem key from certificate
    /// - parameters:
    ///     - certificateURL: Pass .p12 certificate url.
    ///     - pemKeyURL: Destination url of .pem key file
    ///     - password: Passowrd of certificate.
    private func generatePemKey(from certificateURL: URL, with password: String, to pemKeyURL: URL) async throws {
        logger.debug("try generate pem key", metadata: [
            "certificateURL": .stringConvertible(certificateURL),
            "pemKeyURL": .stringConvertible(pemKeyURL)
        ])
        let result = try await Process.asyncExecute(URL(fileURLWithPath: "/usr/bin/openssl"),
                                                    "pkcs12",
                                                    "-in",
                                                    certificateURL.path,
                                                    "-nocerts",
                                                    "-out",
                                                    pemKeyURL.path,
                                                    "-passin",
                                                    "pass:" + password,
                                                    "-passout",
                                                    "pass:" + password)
        guard result == 0 else {
            logger.error("failed to generate pem key", metadata: [
                "result": .stringConvertible(result)
            ])
            throw PassGeneratorError.cannotZip(terminationStatus: result)
        }
    }
    
    /// Generate a pem key from certificate
    /// - parameters:
    ///     - certificateURL: Pass .p12 certificate url.
    ///     - pemKeyURL: Destination url of .pem certificate file
    ///     - password: Passowrd of certificate.
    private func generatePemCertificate(from certificateURL: URL, with password: String, to pemCertURL: URL) async throws {
        logger.debug("try generate pem certificate", metadata: [
            "certificateURL": .stringConvertible(certificateURL),
            "pemCertURL": .stringConvertible(pemCertURL)
        ])
        let result = try await Process.asyncExecute(URL(fileURLWithPath: "/usr/bin/openssl"),
                                                    "pkcs12",
                                                    "-in",
                                                    certificateURL.path,
                                                    "-clcerts",
                                                    "-nokeys",
                                                    "-out",
                                                    pemCertURL.path,
                                                    "-passin",
                                                    "pass:" + password)
        guard result == 0 else {
            logger.error("failed to generate pem certificate", metadata: [
                "result": .stringConvertible(result)
            ])
            throw PassGeneratorError.cannotZip(terminationStatus: result)
        }
    }
}

extension PassKitDatabaseFetcher {
    
    private func registrationsForPass(id: UUID, on db: Database) async throws -> [Registration] {
        try await Registration.query(on: db)
            .join(Pass.self, on: \Registration._$pass.$id == \Pass._$id)
            .join(Device.self, on: \Registration._$device.$id == \Device._$id)
            .with(\._$pass)
            .with(\._$device)
            .filter(Pass.self, \._$id == id)
            .all()
    }
    
    private static func createRegistration(device: Device, pass: Pass, on db: Database) async throws -> HTTPStatus {
        let registration = try await Registration.for(deviceLibraryIdentifier: device.deviceLibraryIdentifier, on: db)
            .filter(Pass.self, \._$id == pass.id!)
            .first()
        if registration != nil {
            // If the registration already exists, docs say to return a 200
            return .ok
        }
        
        let newRegistration = Registration()
        newRegistration._$pass.id = pass.id!
        newRegistration._$device.id = device.id!
        
        try await newRegistration.create(on: db)
        return .created
    }
}
