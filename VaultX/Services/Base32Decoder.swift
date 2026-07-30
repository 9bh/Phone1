import Foundation

enum Base32DecodingError: Error, Equatable {
    case emptyInput
    case invalidCharacter(Character)
    case invalidLength
}

struct Base32Decoder {
    private static let alphabet: [Character: UInt8] = {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        return Dictionary(uniqueKeysWithValues: characters.enumerated().map { index, character in
            (character, UInt8(index))
        })
    }()

    static func decode(_ value: String) throws -> Data {
        let compact = value.filter { !$0.isWhitespace && $0 != "-" }
        guard !compact.isEmpty else {
            throw Base32DecodingError.emptyInput
        }

        let uppercased = compact.uppercased()
        let characters = Array(uppercased)

        let firstPaddingIndex = characters.firstIndex(of: "=")
        let dataCharacters: ArraySlice<Character>
        let paddingCount: Int

        if let firstPaddingIndex {
            dataCharacters = characters[..<firstPaddingIndex]
            let padding = characters[firstPaddingIndex...]
            guard padding.allSatisfy({ $0 == "=" }) else {
                throw Base32DecodingError.invalidLength
            }
            paddingCount = padding.count
        } else {
            dataCharacters = characters[...]
            paddingCount = 0
        }

        guard !dataCharacters.isEmpty else {
            throw Base32DecodingError.emptyInput
        }

        let remainder = dataCharacters.count % 8
        let expectedPadding: Int
        switch remainder {
        case 0: expectedPadding = 0
        case 2: expectedPadding = 6
        case 4: expectedPadding = 4
        case 5: expectedPadding = 3
        case 7: expectedPadding = 1
        default:
            throw Base32DecodingError.invalidLength
        }

        if paddingCount > 0 {
            guard characters.count.isMultiple(of: 8), paddingCount == expectedPadding else {
                throw Base32DecodingError.invalidLength
            }
        }

        var result = Data()
        result.reserveCapacity((dataCharacters.count * 5) / 8)

        var buffer: UInt64 = 0
        var bitCount = 0

        for character in dataCharacters {
            guard let value = alphabet[character] else {
                throw Base32DecodingError.invalidCharacter(character)
            }

            buffer = (buffer << 5) | UInt64(value)
            bitCount += 5

            while bitCount >= 8 {
                let shift = bitCount - 8
                result.append(UInt8((buffer >> UInt64(shift)) & 0xFF))
                bitCount -= 8

                if bitCount == 0 {
                    buffer = 0
                } else {
                    buffer &= (UInt64(1) << UInt64(bitCount)) - 1
                }
            }
        }

        // RFC 4648 requires unused trailing bits to be zero.
        if bitCount > 0, buffer != 0 {
            throw Base32DecodingError.invalidLength
        }

        return result
    }
}
