import Foundation

/// Best-effort, defensive parser for the handful of Windows PE (.exe) version-info string fields
/// Playdock can use for identification/display: ProductName, FileDescription, CompanyName
/// (publisher), FileVersion. Deliberately does **not** attempt icon-resource decoding - a
/// materially harder bitmap format for comparatively little payoff, since the fallback icon path
/// already covers this. Every read here is bounds-checked against the actual file size; any
/// unexpected/malformed structure just returns `nil` rather than force-unwrapping. This only ever
/// *reads* bytes to extract plain text - it never executes anything in the file, same as every
/// other parser in this codebase (ACF, VDF, wikitext).
///
/// Format reference: the standard COFF/PE header → resource directory (type RT_VERSION = 16) →
/// VS_VERSIONINFO → StringFileInfo → StringTable → String walk, per Microsoft's documented
/// VERSIONINFO resource layout.
enum PEVersionInfoReader {
    struct Result {
        var productName: String?
        var fileDescription: String?
        var companyName: String?
        var fileVersion: String?

        var isEmpty: Bool {
            productName == nil && fileDescription == nil && companyName == nil && fileVersion == nil
        }
    }

    static func read(exePath: String) -> Result? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: exePath), options: .mappedIfSafe) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> Result? {
        guard data.count > 0x40, data[data.startIndex] == 0x4D, data[data.startIndex + 1] == 0x5A else { return nil } // "MZ"
        guard let peOffset = readUInt32LE(data, at: 0x3C) else { return nil }
        let peOffsetInt = Int(peOffset)
        guard peOffsetInt > 0, peOffsetInt + 24 <= data.count else { return nil }
        guard byte(data, peOffsetInt) == 0x50, byte(data, peOffsetInt + 1) == 0x45,
              byte(data, peOffsetInt + 2) == 0, byte(data, peOffsetInt + 3) == 0 else { return nil } // "PE\0\0"

        let coffOffset = peOffsetInt + 4
        guard let numberOfSections = readUInt16LE(data, at: coffOffset + 2),
              let sizeOfOptionalHeader = readUInt16LE(data, at: coffOffset + 16) else { return nil }
        let optionalHeaderOffset = coffOffset + 20
        guard sizeOfOptionalHeader > 0, optionalHeaderOffset + Int(sizeOfOptionalHeader) <= data.count else { return nil }

        guard let magic = readUInt16LE(data, at: optionalHeaderOffset) else { return nil }
        let isPE32Plus = magic == 0x20B
        guard magic == 0x10B || isPE32Plus else { return nil }

        let dataDirectoryOffset = optionalHeaderOffset + (isPE32Plus ? 112 : 96)
        let resourceDirEntryOffset = dataDirectoryOffset + 2 * 8 // IMAGE_DIRECTORY_ENTRY_RESOURCE
        guard let resourceRVA = readUInt32LE(data, at: resourceDirEntryOffset),
              let resourceSize = readUInt32LE(data, at: resourceDirEntryOffset + 4), resourceSize > 0 else { return nil }

        let sectionTableOffset = optionalHeaderOffset + Int(sizeOfOptionalHeader)
        guard let sections = readSections(data, offset: sectionTableOffset, count: Int(numberOfSections)) else { return nil }
        guard let resourceBase = rvaToFileOffset(Int(resourceRVA), sections: sections) else { return nil }

        // Type (RT_VERSION = 16) -> Name/ID (take whichever's first) -> Language (take whichever's
        // first) -> the actual VS_VERSIONINFO bytes.
        guard let versionEntry = findDirectoryEntry(data, directoryOffset: resourceBase, id: 16),
              let subdir1 = subdirectoryOffset(data, entryOffset: versionEntry, resourceBase: resourceBase),
              let nameEntry = firstDirectoryEntry(data, directoryOffset: subdir1),
              let subdir2 = subdirectoryOffset(data, entryOffset: nameEntry, resourceBase: resourceBase),
              let langEntry = firstDirectoryEntry(data, directoryOffset: subdir2),
              let dataEntryOffset = dataEntryOffset(data, entryOffset: langEntry, resourceBase: resourceBase) else {
            return nil
        }

        guard let rawRVA = readUInt32LE(data, at: dataEntryOffset), let rawSize = readUInt32LE(data, at: dataEntryOffset + 4), rawSize > 0,
              let rawFileOffset = rvaToFileOffset(Int(rawRVA), sections: sections),
              rawFileOffset >= 0, rawFileOffset + Int(rawSize) <= data.count else {
            return nil
        }

        let versionInfoData = data.subdata(in: (data.startIndex + rawFileOffset)..<(data.startIndex + rawFileOffset + Int(rawSize)))
        return parseVersionInfo(versionInfoData)
    }

    // MARK: - Low-level byte readers (all bounds-checked, all relative to `data`'s own start)

    private static func byte(_ data: Data, _ offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16? {
        guard let b0 = byte(data, offset), let b1 = byte(data, offset + 1) else { return nil }
        return UInt16(b0) | (UInt16(b1) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard let b0 = byte(data, offset), let b1 = byte(data, offset + 1),
              let b2 = byte(data, offset + 2), let b3 = byte(data, offset + 3) else { return nil }
        return UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
    }

    // MARK: - Section table + RVA -> file offset

    private struct Section {
        let virtualAddress: Int
        let virtualSize: Int
        let pointerToRawData: Int
        let sizeOfRawData: Int
    }

    private static func readSections(_ data: Data, offset: Int, count: Int) -> [Section]? {
        guard count > 0, count < 200 else { return nil } // sanity bound - a real PE has a handful
        var sections: [Section] = []
        for index in 0..<count {
            let entryOffset = offset + index * 40
            guard let virtualSize = readUInt32LE(data, at: entryOffset + 8),
                  let virtualAddress = readUInt32LE(data, at: entryOffset + 12),
                  let sizeOfRawData = readUInt32LE(data, at: entryOffset + 16),
                  let pointerToRawData = readUInt32LE(data, at: entryOffset + 20) else { return nil }
            sections.append(Section(
                virtualAddress: Int(virtualAddress), virtualSize: Int(virtualSize),
                pointerToRawData: Int(pointerToRawData), sizeOfRawData: Int(sizeOfRawData)
            ))
        }
        return sections
    }

    private static func rvaToFileOffset(_ rva: Int, sections: [Section]) -> Int? {
        for section in sections {
            let size = max(section.virtualSize, section.sizeOfRawData)
            if rva >= section.virtualAddress, rva < section.virtualAddress + size {
                return section.pointerToRawData + (rva - section.virtualAddress)
            }
        }
        return nil
    }

    // MARK: - Resource directory tree walking

    private static func findDirectoryEntry(_ data: Data, directoryOffset: Int, id: UInt32) -> Int? {
        guard let namedCount = readUInt16LE(data, at: directoryOffset + 12),
              let idCount = readUInt16LE(data, at: directoryOffset + 14) else { return nil }
        let totalEntries = Int(namedCount) + Int(idCount)
        guard totalEntries > 0, totalEntries < 4096 else { return nil }
        let entriesStart = directoryOffset + 16
        // RT_VERSION is always a numeric type ID, so only the ID-entry portion needs scanning.
        for index in Int(namedCount)..<totalEntries {
            let entryOffset = entriesStart + index * 8
            guard let entryID = readUInt32LE(data, at: entryOffset) else { return nil }
            if entryID == id { return entryOffset }
        }
        return nil
    }

    private static func firstDirectoryEntry(_ data: Data, directoryOffset: Int) -> Int? {
        guard let namedCount = readUInt16LE(data, at: directoryOffset + 12),
              let idCount = readUInt16LE(data, at: directoryOffset + 14),
              Int(namedCount) + Int(idCount) > 0 else { return nil }
        let entryOffset = directoryOffset + 16
        guard readUInt32LE(data, at: entryOffset) != nil else { return nil }
        return entryOffset
    }

    private static func subdirectoryOffset(_ data: Data, entryOffset: Int, resourceBase: Int) -> Int? {
        guard let offsetToData = readUInt32LE(data, at: entryOffset + 4), offsetToData & 0x8000_0000 != 0 else { return nil }
        return resourceBase + Int(offsetToData & 0x7FFF_FFFF)
    }

    private static func dataEntryOffset(_ data: Data, entryOffset: Int, resourceBase: Int) -> Int? {
        guard let offsetToData = readUInt32LE(data, at: entryOffset + 4), offsetToData & 0x8000_0000 == 0 else { return nil }
        return resourceBase + Int(offsetToData)
    }

    // MARK: - VS_VERSIONINFO / StringFileInfo / StringTable / String walk

    private static func parseVersionInfo(_ data: Data) -> Result? {
        var result = Result()
        guard let wValueLength = readUInt16LE(data, at: 2) else { return nil }
        var cursor = align4(6 + utf16ByteLength(data, from: 6)) // past wLength/wValueLength/wType/szKey
        cursor = align4(cursor + Int(wValueLength)) // past VS_FIXEDFILEINFO

        var guardCount = 0
        while cursor + 6 <= data.count, guardCount < 64 {
            guardCount += 1
            guard let childLength = readUInt16LE(data, at: cursor), childLength > 0 else { break }
            let key = readUTF16String(data, from: cursor + 6)
            if key.text == "StringFileInfo", let strings = parseStringFileInfo(data, blockStart: cursor, blockLength: Int(childLength)) {
                // Real-world exes genuinely do embed these fields with trailing padding (confirmed
                // live: UNDERTALE.exe's own ProductName/FileDescription both carry ~60 trailing
                // spaces) - trim before handing anything back so display code never has to know that.
                result.productName = strings["ProductName"]?.trimmedNonEmpty
                result.fileDescription = strings["FileDescription"]?.trimmedNonEmpty
                result.companyName = strings["CompanyName"]?.trimmedNonEmpty
                result.fileVersion = strings["FileVersion"]?.trimmedNonEmpty
                break
            }
            cursor = align4(cursor + Int(childLength))
        }

        return result.isEmpty ? nil : result
    }

    private static func parseStringFileInfo(_ data: Data, blockStart: Int, blockLength: Int) -> [String: String]? {
        let blockEnd = min(blockStart + blockLength, data.count)
        let cursor = align4(blockStart + 6 + utf16ByteLength(data, from: blockStart + 6))
        guard cursor < blockEnd else { return nil }

        // First StringTable child (real files can have more than one - keyed by language/codepage -
        // but the first is a fine, simple choice for what's just a display-name lookup).
        guard let tableLength = readUInt16LE(data, at: cursor), tableLength > 0 else { return nil }
        let tableStart = cursor
        let tableEnd = min(tableStart + Int(tableLength), blockEnd)
        var stringCursor = align4(tableStart + 6 + utf16ByteLength(data, from: tableStart + 6))

        var results: [String: String] = [:]
        var guardCount = 0
        while stringCursor + 6 <= tableEnd, guardCount < 256 {
            guardCount += 1
            guard let entryLength = readUInt16LE(data, at: stringCursor), entryLength > 0 else { break }
            guard let valueLengthWords = readUInt16LE(data, at: stringCursor + 2) else { break }
            let keyOffset = stringCursor + 6
            let key = readUTF16String(data, from: keyOffset)
            let valueOffset = align4(keyOffset + key.byteLength)
            let valueByteLength = Int(valueLengthWords) * 2
            if valueByteLength > 0, !key.text.isEmpty {
                results[key.text] = decodeUTF16(data, from: valueOffset, byteLength: valueByteLength)
            }
            stringCursor = align4(stringCursor + Int(entryLength))
        }
        return results.isEmpty ? nil : results
    }

    // MARK: - UTF-16LE helpers

    private static func align4(_ offset: Int) -> Int {
        (offset + 3) & ~3
    }

    private static func utf16ByteLength(_ data: Data, from offset: Int) -> Int {
        readUTF16String(data, from: offset).byteLength
    }

    /// Reads a UTF-16LE, null-terminated string. `byteLength` includes the terminator, so callers
    /// can add it directly to advance a cursor past the field.
    private static func readUTF16String(_ data: Data, from offset: Int) -> (text: String, byteLength: Int) {
        var units: [UInt16] = []
        var cursor = offset
        while let unit = readUInt16LE(data, at: cursor), unit != 0, units.count < 512 {
            units.append(unit)
            cursor += 2
        }
        return (String(decoding: units, as: UTF16.self), (cursor - offset) + 2)
    }

    private static func decodeUTF16(_ data: Data, from offset: Int, byteLength: Int) -> String {
        var units: [UInt16] = []
        var cursor = offset
        let end = offset + byteLength
        while cursor + 2 <= end, let unit = readUInt16LE(data, at: cursor) {
            if unit == 0 { break }
            units.append(unit)
            cursor += 2
        }
        return String(decoding: units, as: UTF16.self)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
