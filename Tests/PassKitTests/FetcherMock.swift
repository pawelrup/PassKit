import Vapor
import Fluent
import PassGenerator
@testable import PassKit

class PassKitPassMock: PassKitPass {
    var id: UUID? = nil
    var modified: Date?
    var pass: Pass
    static var schema: String = ""
    
    required init() {
        pass = .init(description: [:],
                     formatVersion: 1,
                     organizationName: "",
                     passTypeIdentifier: "",
                     serialNumber: "",
                     teamIdentifier: "")
    }
}

class PassKitDeviceMock: PassKitDevice {
    var id: UUID? = nil
    var pushToken: String
    var deviceLibraryIdentifier: String
    static var schema: String = ""
    
    required init(deviceLibraryIdentifier: String, pushToken: String) {
        self.deviceLibraryIdentifier = deviceLibraryIdentifier
        self.pushToken = pushToken
    }
    
    required init() {
        deviceLibraryIdentifier = ""
        pushToken = ""
    }
}

class PassKitRegistrationMock: PassKitRegistration {
    var id: UUID?
    var device: PassKitDeviceMock
    var pass: PassKitPassMock
    static var schema: String = ""
    
    required init() {
        device = .init()
        pass = .init()
    }
}

class ErrorLogMock: PassKitErrorLog {
    var id: UUID?
    var message: String
    static var schema: String = ""
    
    required init(message: String) {
        self.message = message
    }
    
    required init() {
        message = ""
    }
}

class FetcherMock: PassKitDatabaseFetcher {
    typealias Registration = PassKitRegistrationMock
    typealias Pass = PassKitPassMock
    typealias Device = PassKitDeviceMock
    typealias ErrorLog = ErrorLogMock
    
    let logger: Logger
    var directoryConfiguration: DirectoryConfiguration {
        .init(workingDirectory: "")
    }
    
    var wwdrURL: URL {
        URL(fileURLWithPath: "/")
    }
    var templateURL: URL {
        URL(fileURLWithPath: "/")
    }
    var certificateURL: URL {
        URL(fileURLWithPath: "/")
    }
    var certificatePassword: String {
        ""
    }
    var registrationsCallCount: Int = 0
    var registrationsClosure: () -> PassesForDeviceDto = { .init(with: [], maxDate: Date()) }
    var saveLogsCallCount: Int = 0
    var getAllLogsCallCount: Int = 0
    var getAllLogsClosure: () -> [String] = { [] }
    var deleteAllLogsCallCount: Int = 0
    var deleteAllLogsClosure: () -> HTTPStatus = { .ok }
    var registerDeviceCallCount: Int = 0
    var registerDeviceClosure: () -> HTTPStatus = { .ok }
    var unregisterDeviceCallCount: Int = 0
    var unregisterDeviceClosure: () -> HTTPStatus = { .ok }
    var latestVersionOfPassCallCount: Int = 0
    var latestVersionOfPassClosure: () -> Response = { .init() }
    var tokensForPassCallCount: Int = 0
    var tokensForPassClosure: () -> [String] = { [] }
    var sendPushNotificationsForPassCallCount: Int = 0
    
    init(logger: Logger) {
        self.logger = logger
    }
    
    func registrations(forDeviceLibraryIdentifier deviceLibraryIdentifier: String, passesUpdatedSince: TimeInterval?, on db: Database) async throws -> PassesForDeviceDto {
        registrationsCallCount += 1
        return registrationsClosure()
    }
    func saveLogs(_ logs: [String], on db: Database) async throws {
        saveLogsCallCount += 1
    }
    func getAllLogs(on db: Database) async throws -> [String] {
        getAllLogsCallCount += 1
        return getAllLogsClosure()
    }
    func deleteAllLogs(on db: Database) async throws -> HTTPStatus {
        deleteAllLogsCallCount += 1
        return deleteAllLogsClosure()
    }
    func registerDevice(deviceLibraryIdentifier: String, serialNumber: UUID, pushToken: String, on db: Database) async throws -> HTTPStatus {
        registerDeviceCallCount += 1
        return registerDeviceClosure()
    }
    func unregisterDevice(deviceLibraryIdentifier: String, serialNumber: UUID, on db: Database) async throws -> HTTPStatus {
        unregisterDeviceCallCount += 1
        return unregisterDeviceClosure()
    }
    func latestVersionOfPass(serialNumber: UUID, ifModifiedSince: TimeInterval, on db: Database) async throws -> Response {
        latestVersionOfPassCallCount += 1
        return latestVersionOfPassClosure()
    }
    func tokensForPass(id: UUID, on db: Database) async throws -> [String] {
        tokensForPassCallCount += 1
        return tokensForPassClosure()
    }
    func sendPushNotificationsForPass(id: UUID, type: String, on db: Database, using apns: Application.APNS) async throws {
        sendPushNotificationsForPassCallCount += 1
    }
}
