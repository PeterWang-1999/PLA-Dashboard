import Foundation
import zlib

/// 从 ZIP（含 `.xlsx`）中按条目名解压单个文件到目标路径。
enum ZipEntryExtractor {
    enum ExtractorError: Error, LocalizedError {
        case notAZip
        case entryNotFound(String)
        case unsupportedCompression(UInt16)
        case truncated
        case inflateFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .notAZip:
                "不是有效的 ZIP / XLSX 文件"
            case .entryNotFound(let name):
                "压缩包中缺少文件：\(name)"
            case .unsupportedCompression(let method):
                "不支持的 ZIP 压缩方式（\(method)）"
            case .truncated:
                "ZIP 文件不完整或已损坏"
            case .inflateFailed(let code):
                "ZIP 解压失败（zlib \(code)）"
            }
        }
    }

    /// 将 `entryPath`（如 `xl/worksheets/sheet1.xml`）解压到 `destinationURL`（流式写入，避免整表进内存）。
    static func extractEntry(
        named entryPath: String,
        from zipURL: URL,
        to destinationURL: URL
    ) throws {
        let data = try Data(contentsOf: zipURL, options: [.mappedIfSafe])
        guard data.count >= 22 else { throw ExtractorError.notAZip }

        let normalizedTarget = entryPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let central = try findCentralDirectoryEntry(in: data, named: normalizedTarget) else {
            throw ExtractorError.entryNotFound(entryPath)
        }

        let localOffset = Int(central.localHeaderOffset)
        guard localOffset + 30 <= data.count else { throw ExtractorError.truncated }

        let signature = readUInt32(data, at: localOffset)
        guard signature == 0x0403_4b50 else { throw ExtractorError.truncated }

        let compressionMethod = readUInt16(data, at: localOffset + 8)
        let fileNameLength = Int(readUInt16(data, at: localOffset + 26))
        let extraLength = Int(readUInt16(data, at: localOffset + 28))
        let payloadStart = localOffset + 30 + fileNameLength + extraLength

        let compressedSize = Int(central.compressedSize)
        guard payloadStart >= 0, payloadStart + compressedSize <= data.count else {
            throw ExtractorError.truncated
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }

        let payloadRange = payloadStart..<(payloadStart + compressedSize)
        switch compressionMethod {
        case 0:
            try output.write(contentsOf: data.subdata(in: payloadRange))
        case 8:
            try inflateRawDeflate(data: data, range: payloadRange, to: output)
        default:
            throw ExtractorError.unsupportedCompression(compressionMethod)
        }
    }

    // MARK: - Central directory

    private struct CentralDirectoryEntry {
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
    }

    private static func findCentralDirectoryEntry(
        in data: Data,
        named target: String
    ) throws -> CentralDirectoryEntry? {
        guard let eocdOffset = findEndOfCentralDirectory(in: data) else {
            throw ExtractorError.notAZip
        }

        let centralSize = Int(readUInt32(data, at: eocdOffset + 12))
        let centralOffset = Int(readUInt32(data, at: eocdOffset + 16))
        guard centralOffset >= 0, centralOffset + centralSize <= data.count else {
            throw ExtractorError.truncated
        }

        var cursor = centralOffset
        let end = centralOffset + centralSize
        while cursor + 46 <= end {
            let sig = readUInt32(data, at: cursor)
            guard sig == 0x0201_4b50 else { break }

            let compressedSize = UInt64(readUInt32(data, at: cursor + 20))
            let uncompressedSize = UInt64(readUInt32(data, at: cursor + 24))
            let fileNameLength = Int(readUInt16(data, at: cursor + 28))
            let extraLength = Int(readUInt16(data, at: cursor + 30))
            let commentLength = Int(readUInt16(data, at: cursor + 32))
            let localHeaderOffset = UInt64(readUInt32(data, at: cursor + 42))

            let nameStart = cursor + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count else { throw ExtractorError.truncated }

            let name = String(decoding: data.subdata(in: nameStart..<nameEnd), as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if name.caseInsensitiveCompare(target) == .orderedSame {
                return CentralDirectoryEntry(
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            }
            cursor = nameEnd + extraLength + commentLength
        }
        return nil
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        let maxScan = min(data.count, 65_535 + 22)
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        let lower = data.count - maxScan
        while i >= lower {
            if readUInt32(data, at: i) == 0x0605_4b50 {
                return i
            }
            if i == 0 { break }
            i -= 1
        }
        return nil
    }

    // MARK: - Raw DEFLATE → file

    private static func inflateRawDeflate(
        data: Data,
        range: Range<Int>,
        to output: FileHandle
    ) throws {
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else { throw ExtractorError.inflateFailed(initStatus) }
        defer { inflateEnd(&stream) }

        var outBuffer = [UInt8](repeating: 0, count: 64 * 1024)
        let chunkSize = 64 * 1024
        var offset = range.lowerBound

        try data.withUnsafeBytes { srcRaw in
            guard let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else {
                throw ExtractorError.inflateFailed(Z_DATA_ERROR)
            }

            while offset < range.upperBound {
                let remaining = range.upperBound - offset
                let inCount = min(chunkSize, remaining)
                stream.next_in = UnsafeMutablePointer(mutating: srcBase.advanced(by: offset))
                stream.avail_in = uInt(inCount)
                offset += inCount

                repeat {
                    let status: Int32 = outBuffer.withUnsafeMutableBufferPointer { dest in
                        stream.next_out = dest.baseAddress
                        stream.avail_out = uInt(dest.count)
                        return inflate(&stream, Z_NO_FLUSH)
                    }

                    let produced = outBuffer.count - Int(stream.avail_out)
                    if produced > 0 {
                        try output.write(contentsOf: Data(outBuffer[0..<produced]))
                    }

                    if status == Z_STREAM_END {
                        return
                    }
                    if status != Z_OK {
                        throw ExtractorError.inflateFailed(status)
                    }
                } while stream.avail_out == 0
            }

            // Finalize in case trailing bytes remain in inflater.
            repeat {
                let status: Int32 = outBuffer.withUnsafeMutableBufferPointer { dest in
                    stream.next_in = nil
                    stream.avail_in = 0
                    stream.next_out = dest.baseAddress
                    stream.avail_out = uInt(dest.count)
                    return inflate(&stream, Z_FINISH)
                }
                let produced = outBuffer.count - Int(stream.avail_out)
                if produced > 0 {
                    try output.write(contentsOf: Data(outBuffer[0..<produced]))
                }
                if status == Z_STREAM_END {
                    return
                }
                if status != Z_OK && status != Z_BUF_ERROR {
                    throw ExtractorError.inflateFailed(status)
                }
                if produced == 0 { break }
            } while true
        }
    }

    // MARK: - Binary helpers

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
