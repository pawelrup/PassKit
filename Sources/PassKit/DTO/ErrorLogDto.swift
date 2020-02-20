//
//  ErrorLogDto.swift
//
//
//  Created by Pawel Rup on 20/02/2020.
//

import Vapor

struct ErrorLogDto: Content {
    let logs: [String]
}
