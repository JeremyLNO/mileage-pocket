import Foundation

/// Folds a recorded trip's fixes into the small blob stored on `Trip.encodedRoute`.
///
/// Size is the whole point. A one-hour drive is ~3 600 fixes; kept as rows they would put
/// hundreds of thousands of records into the user's CloudKit database for a line on a map
/// nobody zooms into. Simplify first, then pack.
enum RouteCompactor {

    // MARK: - Simplification

    /// Ramer–Douglas–Peucker: keeps the points that carry the shape, drops the ones that lie
    /// on a line between their neighbours.
    static func simplify(_ points: [LocationSample], toleranceMeters: Double) -> [LocationSample] {
        guard points.count > 2, toleranceMeters > 0 else { return points }

        // One tangent plane for the whole route: RDP only ever compares a point against a
        // nearby chord, so the projection's drift over a long trip cancels out of the
        // comparison well below any sane tolerance.
        let originLatitude = points[0].latitude
        let originLongitude = points[0].longitude
        let projected = points.map {
            Geodesy.project(
                latitude: $0.latitude, longitude: $0.longitude,
                originLatitude: originLatitude, originLongitude: originLongitude
            )
        }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        // Explicit stack rather than recursion: a long trip is tens of thousands of points
        // and the recursive form is one pathological route away from a stack overflow.
        var pending: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = pending.popLast() {
            guard last > first + 1 else { continue }
            var worstIndex = first
            var worstDistance = 0.0
            for index in (first + 1)..<last {
                let distance = perpendicularDistance(
                    of: projected[index], from: projected[first], to: projected[last]
                )
                if distance > worstDistance {
                    worstDistance = distance
                    worstIndex = index
                }
            }
            if worstDistance > toleranceMeters {
                keep[worstIndex] = true
                pending.append((first, worstIndex))
                pending.append((worstIndex, last))
            }
        }

        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    private static func perpendicularDistance(
        of point: (x: Double, y: Double),
        from start: (x: Double, y: Double),
        to end: (x: Double, y: Double)
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return ((point.x - start.x) * (point.x - start.x)
                + (point.y - start.y) * (point.y - start.y)).squareRoot()
        }
        // Clamped projection: a route that doubles back makes the unclamped formula
        // measure against an imaginary extension of the chord.
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let closestX = start.x + t * dx
        let closestY = start.y + t * dy
        return ((point.x - closestX) * (point.x - closestX)
            + (point.y - closestY) * (point.y - closestY)).squareRoot()
    }

    // MARK: - Wire format

    /// version | count | first point absolute | zig-zag varint deltas.
    ///
    /// Coordinates are stored as degrees × 1e5 (about 1 m, finer than any fix this app will
    /// ever see) and timestamps as milliseconds, both as deltas — consecutive fixes differ
    /// by a few units, which a varint writes in a single byte. A 720-point route lands
    /// around 2.9 KB.
    private static let formatVersion: UInt8 = 1
    private static let coordinateScale = 1e5

    static func encode(_ points: [LocationSample]) -> Data {
        var data = Data()
        data.append(formatVersion)
        appendVarint(UInt64(points.count), to: &data)

        var previousLatitude: Int64 = 0
        var previousLongitude: Int64 = 0
        var previousMilliseconds: Int64 = 0
        for point in points {
            let latitude = Int64((point.latitude * coordinateScale).rounded())
            let longitude = Int64((point.longitude * coordinateScale).rounded())
            let milliseconds = Int64((point.timestamp.timeIntervalSinceReferenceDate * 1000).rounded())
            appendVarint(zigZag(latitude - previousLatitude), to: &data)
            appendVarint(zigZag(longitude - previousLongitude), to: &data)
            appendVarint(zigZag(milliseconds - previousMilliseconds), to: &data)
            previousLatitude = latitude
            previousLongitude = longitude
            previousMilliseconds = milliseconds
        }
        return data
    }

    /// Returns an empty route for anything it cannot read. A corrupt blob costs a map line;
    /// throwing here would cost the trip it is attached to.
    static func decode(_ data: Data) -> [LocationSample] {
        var cursor = data.startIndex
        guard cursor < data.endIndex, data[cursor] == formatVersion else { return [] }
        cursor += 1
        guard let count = readVarint(from: data, cursor: &cursor) else { return [] }

        var points: [LocationSample] = []
        points.reserveCapacity(Int(count))
        var latitude: Int64 = 0
        var longitude: Int64 = 0
        var milliseconds: Int64 = 0
        for _ in 0..<count {
            guard let rawLatitude = readVarint(from: data, cursor: &cursor),
                  let rawLongitude = readVarint(from: data, cursor: &cursor),
                  let rawMilliseconds = readVarint(from: data, cursor: &cursor)
            else { return [] }
            latitude += unZigZag(rawLatitude)
            longitude += unZigZag(rawLongitude)
            milliseconds += unZigZag(rawMilliseconds)
            points.append(LocationSample(
                latitude: Double(latitude) / coordinateScale,
                longitude: Double(longitude) / coordinateScale,
                // Accuracy, altitude and speed are not stored: the blob exists to draw the
                // route, and those three would double its size for nothing.
                horizontalAccuracy: 0,
                altitude: 0,
                speed: -1,
                timestamp: Date(timeIntervalSinceReferenceDate: Double(milliseconds) / 1000)
            ))
        }
        return points
    }

    // MARK: - Varints

    private static func zigZag(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: (value << 1) ^ (value >> 63))
    }

    private static func unZigZag(_ value: UInt64) -> Int64 {
        Int64(bitPattern: (value >> 1)) ^ -Int64(bitPattern: value & 1)
    }

    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }

    private static func readVarint(from data: Data, cursor: inout Data.Index) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < data.endIndex {
            let byte = data[cursor]
            cursor += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
}
