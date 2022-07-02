import Vapor

/// Checks request has proper authorization header.
struct ApplePassMiddleware: AsyncMiddleware {
    let authorizationCode: String
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let auth = request.headers["Authorization"]
        guard auth.first == "ApplePass \(authorizationCode)" else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: request)
    }
}

