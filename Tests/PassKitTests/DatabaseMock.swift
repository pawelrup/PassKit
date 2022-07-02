import FluentKit
import Foundation
import NIOEmbedded

public struct DatabaseMock: Database {
    public var context: DatabaseContext
    
    public init(context: DatabaseContext? = nil) {
        self.context = context ?? .init(
            configuration: DatabaseMockConfiguration(middleware: []),
            logger: .init(label: "codes.vapor.test"),
            eventLoop: EmbeddedEventLoop()
        )
    }

    public var inTransaction: Bool {
        false
    }
    
    public func execute(query: DatabaseQuery, onOutput: @escaping (DatabaseOutput) -> ()) -> EventLoopFuture<Void> {
        for _ in 0..<Int.random(in: 1..<42) {
            onOutput(RowMock())
        }
        return eventLoop.makeSucceededFuture(())
    }

    public func transaction<T>(_ closure: @escaping (Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        closure(self)
    }
    
    public func withConnection<T>(_ closure: (Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        closure(self)
    }
    
    public func execute(schema: DatabaseSchema) -> EventLoopFuture<Void> {
        eventLoop.makeSucceededFuture(())
    }

    public func execute(enum: DatabaseEnum) -> EventLoopFuture<Void> {
        eventLoop.makeSucceededFuture(())
    }
}

public struct DatabaseMockConfiguration: DatabaseConfiguration {
    public var middleware: [AnyModelMiddleware]

    public func makeDriver(for databases: Databases) -> DatabaseDriver {
        DatabaseMockDriver(on: databases.eventLoopGroup)
    }
}

public final class DatabaseMockDriver: DatabaseDriver {
    public let eventLoopGroup: EventLoopGroup
    var didShutdown: Bool
    
    public var fieldDecoder: Decoder {
        DummyDecoder()
    }

    public init(on eventLoopGroup: EventLoopGroup) {
        self.eventLoopGroup = eventLoopGroup
        didShutdown = false
    }
    
    public func makeDatabase(with context: DatabaseContext) -> Database {
        DatabaseMock(context: context)
    }

    public func shutdown() {
        didShutdown = true
    }
    deinit {
        assert(self.didShutdown, "DatabaseMock did not shutdown before deinit.")
    }
}

// MARK: Private

public struct RowMock: DatabaseOutput {
    public init() { }

    public func schema(_ schema: String) -> DatabaseOutput {
        self
    }

    public func nested(_ key: FieldKey) throws -> DatabaseOutput {
        self
    }

    public func decodeNil(_ key: FieldKey) throws -> Bool {
        false
    }
    
    public func decode<T>(_ key: FieldKey, as type: T.Type) throws -> T where T: Decodable {
        if T.self is UUID.Type {
            return UUID() as! T
        } else {
            return try T(from: DummyDecoder())
        }
    }

    public func contains(_ key: FieldKey) -> Bool {
        true
    }
    
    public var description: String {
        "<dummy>"
    }
}

private struct DummyDecoder: Decoder {
    var codingPath: [CodingKey] {
        []
    }
    
    var userInfo: [CodingUserInfoKey : Any] {
        [:]
    }
    
    init() {
        
    }
    
    struct KeyedDecoder<Key>: KeyedDecodingContainerProtocol
        where Key: CodingKey
    {
        var codingPath: [CodingKey] {
            []
        }
        var allKeys: [Key] {
            [
                Key(stringValue: "test")!
            ]
        }
        
        init() { }
        
        func contains(_ key: Key) -> Bool {
            false
        }
        
        func decodeNil(forKey key: Key) throws -> Bool {
            false
        }
        
        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
            if T.self is UUID.Type {
                return UUID() as! T
            } else {
                return try T.init(from: DummyDecoder())
            }
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            KeyedDecodingContainer<NestedKey>(KeyedDecoder<NestedKey>())
        }
        
        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            UnkeyedDecoder()
        }
        
        func superDecoder() throws -> Decoder {
            DummyDecoder()
        }
        
        func superDecoder(forKey key: Key) throws -> Decoder {
            DummyDecoder()
        }
    }
    
    struct UnkeyedDecoder: UnkeyedDecodingContainer {
        var codingPath: [CodingKey]
        var count: Int?
        var isAtEnd: Bool {
            guard let count = self.count else {
                return true
            }
            return self.currentIndex >= count
        }
        var currentIndex: Int
        
        init() {
            codingPath = []
            count = 1
            currentIndex = 0
        }
        
        mutating func decodeNil() throws -> Bool {
            true
        }
        
        mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            try T.init(from: DummyDecoder())
        }
        
        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            KeyedDecodingContainer<NestedKey>(KeyedDecoder())
        }
        
        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            UnkeyedDecoder()
        }
        
        mutating func superDecoder() throws -> Decoder {
            DummyDecoder()
        }
    }
    
    struct SingleValueDecoder: SingleValueDecodingContainer {
        var codingPath: [CodingKey] {
            []
        }
        
        init() { }
        
        func decodeNil() -> Bool {
            false
        }
        
        func decode(_ type: Bool.Type) throws -> Bool {
            false
        }
        
        func decode(_ type: String.Type) throws -> String {
            "foo"
        }
        
        func decode(_ type: Double.Type) throws -> Double {
            3.14
        }
        
        func decode(_ type: Float.Type) throws -> Float {
            1.59
        }
        
        func decode(_ type: Int.Type) throws -> Int {
            -42
        }
        
        func decode(_ type: Int8.Type) throws -> Int8 {
            -8
        }
        
        func decode(_ type: Int16.Type) throws -> Int16 {
            -16
        }
        
        func decode(_ type: Int32.Type) throws -> Int32 {
            -32
        }
        
        func decode(_ type: Int64.Type) throws -> Int64 {
            -64
        }
        
        func decode(_ type: UInt.Type) throws -> UInt {
            42
        }
        
        func decode(_ type: UInt8.Type) throws -> UInt8 {
            8
        }
        
        func decode(_ type: UInt16.Type) throws -> UInt16 {
            16
        }
        
        func decode(_ type: UInt32.Type) throws -> UInt32 {
            32
        }
        
        func decode(_ type: UInt64.Type) throws -> UInt64 {
            64
        }
        
        func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            if T.self is UUID.Type {
                return UUID() as! T
            } else {
                return try T(from: DummyDecoder())
            }
        }
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        .init(KeyedDecoder())
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        UnkeyedDecoder()
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleValueDecoder()
    }
}
