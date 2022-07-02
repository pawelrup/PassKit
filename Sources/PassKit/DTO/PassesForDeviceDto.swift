import Vapor

public struct PassesForDeviceDto: Content {
    let lastUpdated: String
    let serialNumbers: [String]
    
    init(with serialNumbers: [String], maxDate: Date) {
        lastUpdated = String(maxDate.timeIntervalSince1970)
        self.serialNumbers = serialNumbers
    }
}
