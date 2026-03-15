import CoreLocation

/// Decodes HERE Maps Flexible Polyline strings into arrays of CLLocationCoordinate2D.
///
/// Spec: https://github.com/heremaps/flexible-polyline
/// - Header: 2 characters. char[0] = version (must be 1 = 'B'), char[1] encodes
///   precision in the lower 4 bits and optional 3rd-dimension info in bits 4–6.
/// - Body: variable-length zigzag-encoded delta integers, one pair (lat, lng) per point.
struct FlexiblePolylineDecoder {

    private static let encodingTable =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    // Map each character to its 0-63 index at startup.
    private static let decodingTable: [Character: Int] = {
        var table = [Character: Int]()
        table.reserveCapacity(64)
        for (i, c) in encodingTable.enumerated() { table[c] = i }
        return table
    }()

    /// Returns decoded coordinates, or an empty array if the string is malformed.
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        let chars = Array(encoded)
        // Minimum valid string: 2-char header + at least one coordinate pair
        guard chars.count >= 4 else { return [] }

        // char[0] = version; char[1] lower-4-bits = decimal precision
        let headerByte = decodingTable[chars[1]] ?? 5
        let precision = headerByte & 0x0F
        let thirdDim  = (headerByte >> 4) & 0x07
        let hasDim3   = thirdDim != 0

        let factor = pow(10.0, Double(precision))
        var index = 2   // start past the 2-char header
        var lastLat = 0
        var lastLng = 0
        var result: [CLLocationCoordinate2D] = []

        while index < chars.count {
            let (latDelta, i1) = decodeValue(chars, from: index)
            guard i1 <= chars.count else { break }
            let (lngDelta, i2) = decodeValue(chars, from: i1)
            var next = i2

            if hasDim3 && next < chars.count {
                let (_, i3) = decodeValue(chars, from: next)
                next = i3
            }

            lastLat += latDelta
            lastLng += lngDelta
            result.append(CLLocationCoordinate2D(
                latitude:  Double(lastLat) / factor,
                longitude: Double(lastLng) / factor
            ))
            index = next
        }

        return result
    }

    // MARK: - Private

    /// Reads one variable-length zigzag-encoded integer from `chars` starting at `start`.
    /// Returns (decoded value, next index).
    private static func decodeValue(_ chars: [Character], from start: Int) -> (Int, Int) {
        var result = 0
        var shift  = 0
        var index  = start

        while index < chars.count {
            let charVal = decodingTable[chars[index]] ?? 0
            index += 1
            result |= (charVal & 0x1F) << shift
            shift  += 5
            if (charVal & 0x20) == 0 { break }  // no continuation bit → done
        }

        // Zigzag decode: LSB encodes sign
        let decoded = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        return (decoded, index)
    }
}
