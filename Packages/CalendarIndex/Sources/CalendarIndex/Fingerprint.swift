import Foundation

/// Stable content hash of a snapshot's canonical encoding: FNV-1a 64-bit.
/// Never Swift's `Hasher` — it's seeded per process, so every row would
/// look changed on every launch.
enum Fingerprint {
    static func of(_ data: Data) -> Int64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int64(bitPattern: hash)
    }
}

/// The canonical encoding: sorted keys, so equal snapshots are equal bytes.
enum SnapshotCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    /// The stored form of an occurrence: LZFSE-compressed canonical JSON
    /// (repeating meetings carry the same long invite notes and attendee
    /// lists in every occurrence), fingerprinted before compression.
    static func payload<T: Encodable>(_ value: T) throws -> (data: Data, fingerprint: Int64) {
        let json = try encode(value)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        return (compressed, Fingerprint.of(json))
    }

    /// Accepts compressed payloads and plain JSON (calendar rows, and any
    /// row written before compression).
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let json = data.first == UInt8(ascii: "{") ? data : try (data as NSData).decompressed(using: .lzfse) as Data
        return try JSONDecoder().decode(type, from: json)
    }
}
