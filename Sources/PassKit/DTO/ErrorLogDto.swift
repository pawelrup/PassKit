import Vapor

struct ErrorLogDto: Content {
    let logs: [String]
}
