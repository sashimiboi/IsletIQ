import Foundation
import Compression

/// Minimal in-process ZIP reader. Handles `stored` (method 0) and `deflate`
/// (method 8) entries by walking the central directory. Good enough for
/// Glooko's multi-CSV export zip; does not support ZIP64, encryption, or
/// streaming-mode entries (data descriptors).
enum MiniZip {
    struct Entry {
        let filename: String
        let data: Data
    }

    enum MiniZipError: Error {
        case notAZip
        case truncated
        case unsupportedCompression(UInt16)
        case inflateFailed
    }

    /// Human-readable stats from the last extract() call — useful for
    /// surfacing "zip had 0 entries" vs "parse error" to the user.
    struct ExtractStats {
        var totalInZip: Int = 0
        var extracted: Int = 0
        var skipped: [String] = []
    }

    static func extract(_ zip: Data) throws -> [Entry] {
        var stats = ExtractStats()
        return try extract(zip, stats: &stats)
    }

    static func extract(_ zip: Data, stats: inout ExtractStats) throws -> [Entry] {
        guard zip.count >= 22 else { throw MiniZipError.truncated }

        // Find End of Central Directory record (EOCD) — signature PK\x05\x06.
        let eocdSig: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard let eocdOffset = searchBackward(in: zip, signature: eocdSig) else {
            throw MiniZipError.notAZip
        }
        let totalEntries = Int(readUInt16(zip, at: eocdOffset + 10))
        let cdOffset = Int(readUInt32(zip, at: eocdOffset + 16))
        let cdSize = Int(readUInt32(zip, at: eocdOffset + 12))
        stats.totalInZip = totalEntries
        print("[MiniZip] size=\(zip.count) eocd=\(eocdOffset) cdOffset=\(cdOffset) cdSize=\(cdSize) entries=\(totalEntries)")

        var entries: [Entry] = []
        var cursor = cdOffset

        for entryIdx in 0..<totalEntries {
            guard cursor + 46 <= zip.count else {
                stats.skipped.append("entry[\(entryIdx)] truncated CD at \(cursor)")
                break
            }
            let sig = readUInt32(zip, at: cursor)
            guard sig == 0x02014b50 else {
                stats.skipped.append("entry[\(entryIdx)] bad CD sig \(String(format: "0x%08x", sig)) at \(cursor)")
                break
            }

            let method = readUInt16(zip, at: cursor + 10)
            var compressedSize = UInt64(readUInt32(zip, at: cursor + 20))
            var uncompressedSize = UInt64(readUInt32(zip, at: cursor + 24))
            let filenameLen = Int(readUInt16(zip, at: cursor + 28))
            let extraLen = Int(readUInt16(zip, at: cursor + 30))
            let commentLen = Int(readUInt16(zip, at: cursor + 32))
            var localHeaderOffset = UInt64(readUInt32(zip, at: cursor + 42))

            let filename: String = {
                let nameStart = cursor + 46
                let nameEnd = nameStart + filenameLen
                guard nameEnd <= zip.count else { return "" }
                return String(data: zip.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? ""
            }()

            // ZIP64 extra field: when any of the size/offset fields above are
            // 0xFFFFFFFF (the ZIP64 sentinel), the real 64-bit value lives in
            // the extra field under tag 0x0001. Fields appear in a fixed
            // order but only if their 32-bit value was the sentinel.
            let extraStart = cursor + 46 + filenameLen
            var pos = extraStart
            let extraEnd = extraStart + extraLen
            while pos + 4 <= extraEnd {
                let tag = readUInt16(zip, at: pos)
                let size = Int(readUInt16(zip, at: pos + 2))
                let payloadEnd = pos + 4 + size
                if tag == 0x0001, payloadEnd <= extraEnd {
                    var z64 = pos + 4
                    if uncompressedSize == 0xFFFFFFFF, z64 + 8 <= payloadEnd {
                        uncompressedSize = readUInt64(zip, at: z64); z64 += 8
                    }
                    if compressedSize == 0xFFFFFFFF, z64 + 8 <= payloadEnd {
                        compressedSize = readUInt64(zip, at: z64); z64 += 8
                    }
                    if localHeaderOffset == 0xFFFFFFFF, z64 + 8 <= payloadEnd {
                        localHeaderOffset = readUInt64(zip, at: z64); z64 += 8
                    }
                    break
                }
                pos = payloadEnd
            }

            cursor += 46 + filenameLen + extraLen + commentLen

            // Skip directory entries and macOS metadata clutter.
            if filename.isEmpty || filename.hasSuffix("/") {
                stats.skipped.append(filename.isEmpty ? "(empty)" : "\(filename) (dir)")
                continue
            }
            if filename.hasPrefix("__MACOSX/") || filename.contains("/.DS_Store") {
                stats.skipped.append("\(filename) (macos meta)")
                continue
            }

            // Jump to the local file header to find the actual compressed data.
            let lhOffset = Int(localHeaderOffset)
            let csize = Int(compressedSize)
            let usize = Int(uncompressedSize)
            guard lhOffset + 30 <= zip.count else {
                stats.skipped.append("\(filename) (lh_offset=\(lhOffset) out of bounds, zip=\(zip.count))")
                continue
            }
            let lhSig = readUInt32(zip, at: lhOffset)
            guard lhSig == 0x04034b50 else {
                stats.skipped.append("\(filename) (lh_sig=\(String(format: "0x%08x", lhSig)) at \(lhOffset))")
                continue
            }
            let lhFilenameLen = Int(readUInt16(zip, at: lhOffset + 26))
            let lhExtraLen = Int(readUInt16(zip, at: lhOffset + 28))
            let dataOffset = lhOffset + 30 + lhFilenameLen + lhExtraLen

            guard dataOffset + csize <= zip.count else {
                stats.skipped.append("\(filename) (data range \(dataOffset)+\(csize) > \(zip.count))")
                continue
            }
            let compressed = zip.subdata(in: dataOffset..<(dataOffset + csize))

            // Per-entry errors shouldn't kill the whole import — a Glooko zip
            // with one weird entry (e.g. a directory marker with odd flags,
            // or an unsupported compression method) can still give us all
            // the CSVs we actually care about.
            let decompressed: Data
            switch method {
            case 0:
                decompressed = compressed
            case 8:
                guard let inflated = inflate(compressed, expectedSize: usize) else {
                    print("[MiniZip] \(filename): inflate FAILED (compressed=\(csize), expected=\(usize))")
                    stats.skipped.append("\(filename) (inflate failed)")
                    continue
                }
                print("[MiniZip] \(filename): inflated \(csize) → \(inflated.count) (expected \(usize))")
                decompressed = inflated
            default:
                stats.skipped.append("\(filename) (method=\(method))")
                continue
            }

            entries.append(Entry(filename: filename, data: decompressed))
            stats.extracted += 1
        }

        return entries
    }

    // MARK: - Helpers

    private static func searchBackward(in data: Data, signature: [UInt8]) -> Int? {
        let sigLen = signature.count
        guard data.count >= sigLen else { return nil }
        // EOCD comment can be up to 65535 bytes, so search the last ~64KB + header.
        let searchStart = max(0, data.count - 65_557)
        var i = data.count - sigLen
        while i >= searchStart {
            var match = true
            for j in 0..<sigLen where data[i + j] != signature[j] {
                match = false; break
            }
            if match { return i }
            i -= 1
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(data[offset + i]) << (8 * i)
        }
        return v
    }

    /// Raw DEFLATE inflate using `Compression.framework`'s streaming API.
    /// The one-shot `compression_decode_buffer` returned partial output on
    /// Glooko's 800KB CGM CSV — it hit an internal end-of-stream marker
    /// early and returned only ~20% of the data. Streaming grows the output
    /// 64KB at a time until `COMPRESSION_STATUS_END`, which is robust at
    /// any size and the right default.
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        return streamingInflate(data)
    }

    /// Streaming DEFLATE inflate. Reads the whole input in one go but flushes
    /// output in chunks so we're not bound to a fixed destination size.
    private static func streamingInflate(_ data: Data) -> Data? {
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        guard compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPtr) }

        var output = Data()
        let chunkSize = 64 * 1024
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { outputBuffer.deallocate() }

        return data.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcRaw.baseAddress else { return nil }
            streamPtr.pointee.src_ptr = srcBase.assumingMemoryBound(to: UInt8.self)
            streamPtr.pointee.src_size = data.count

            while true {
                streamPtr.pointee.dst_ptr = outputBuffer
                streamPtr.pointee.dst_size = chunkSize
                let status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunkSize - streamPtr.pointee.dst_size
                if produced > 0 {
                    output.append(outputBuffer, count: produced)
                }
                switch status {
                case COMPRESSION_STATUS_OK:
                    continue
                case COMPRESSION_STATUS_END:
                    return output
                default:
                    return nil
                }
            }
        }
    }
}
