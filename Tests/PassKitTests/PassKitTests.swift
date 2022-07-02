import XCTest
import Vapor
import XCTVapor
import Logging
@testable import PassKit

final class PassKitTests: XCTestCase {
    let app = Application(.testing)
    lazy var fetcherMock = FetcherMock(logger: app.logger)
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        app.logger.logLevel = .debug
        app.passKit.configuration = .init(fetchers: [
            "pass.com.example.pass": fetcherMock
        ])
        app.passKit.registerRoutes(app, authorizationCode: "test")
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
        
        app.shutdown()
    }
    
    func testRoutesRegisteredCorrectly() async throws {
        let availableRoutes = app.routes.all
            .map { (route: Route) -> (method: HTTPMethod, path: String) in
                let path = route.path.map { "\($0)" }.joined(separator: "/")
                return (route.method, path)
            }
        let containsPassesForDevice = availableRoutes.contains {
            $0.method == .GET && $0.path == "v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier"
        }
        XCTAssertTrue(containsPassesForDevice, "Should have registrations route")
        let containsPostLog = availableRoutes.contains {
            $0.method == .POST && $0.path == "v1/log"
        }
        XCTAssertTrue(containsPostLog, "Should have log route")
        let containsGetLog = availableRoutes.contains {
            $0.method == .GET && $0.path == "v1/log"
        }
        XCTAssertTrue(containsGetLog, "Should have log route")
        let containsDeleteLog = availableRoutes.contains {
            $0.method == .DELETE && $0.path == "v1/log"
        }
        XCTAssertTrue(containsDeleteLog, "Should have log route")
        let containsRegisterDevice = availableRoutes.contains {
            $0.method == .POST && $0.path == "v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier/:serialNumber"
        }
        XCTAssertTrue(containsRegisterDevice, "Should have registerDevice route")
        let containsLatestVersionOfPass = availableRoutes.contains {
            $0.method == .GET && $0.path == "v1/passes/:passTypeIdentifier/:serialNumber"
        }
        XCTAssertTrue(containsLatestVersionOfPass, "Should have latestVersionOfPass route")
        let containsUnregisterDevice = availableRoutes.contains {
            $0.method == .DELETE && $0.path == "v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier/:serialNumber"
        }
        XCTAssertTrue(containsUnregisterDevice, "Should have unregisterDevice route")
        let containsPushUpdatesForPass = availableRoutes.contains {
            $0.method == .POST && $0.path == "v1/push/:passTypeIdentifier/:serialNumber"
        }
        XCTAssertTrue(containsPushUpdatesForPass, "Should have pushUpdatesForPass route")
        let containsTokensForPassUpdate = availableRoutes.contains {
            $0.method == .GET && $0.path == "v1/push/:passTypeIdentifier/:serialNumber"
        }
        XCTAssertTrue(containsTokensForPassUpdate, "Should have tokensForPassUpdate route")
    }

    static var allTests = [
        ("testRoutesRegisteredCorrectly", testRoutesRegisteredCorrectly),
    ]
}
