//
//  ApplePassMiddleware.swift
//
//
//  Created by Pawel Rup on 20/02/2020.
//

import Vapor

/// Checks request has proper authorization header.
struct ApplePassMiddleware: Middleware {
    let authorizationCode: String

    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        let auth = request.headers["Authorization"]
        guard auth.first == "ApplePass \(authorizationCode)" else {
            return request.eventLoop.makeFailedFuture(Abort(.unauthorized))
        }

        return next.respond(to: request)
    }
}

