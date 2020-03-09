//
//  APNSwiftConfiguration+Extension.swift
//  
//
//  Created by Pawel Rup on 09/03/2020.
//

import Vapor
import APNSwift
import NIOSSL

extension APNSwiftConfiguration {
    internal init<T: Collection>(privateKeyPath: String, pemPath: String, logger: Logger? = nil, passphraseCallback: @escaping NIOSSLPassphraseCallback<T>) throws
        where T.Element == UInt8 {
            try self.init(keyIdentifier: "", teamIdentifier: "", signer: APNSwiftSigner(buffer: ByteBufferAllocator().buffer(capacity: 1024)), topic: "", environment: .production, logger: logger)
            let key = try NIOSSLPrivateKey(file: privateKeyPath, format: .pem, passphraseCallback: passphraseCallback)
            self.tlsConfiguration.privateKey = NIOSSLPrivateKeySource.privateKey(key)
            self.tlsConfiguration.certificateVerification = .noHostnameVerification
            self.tlsConfiguration.certificateChain = try [.certificate(.init(file: pemPath, format: .pem))]
    }
}
