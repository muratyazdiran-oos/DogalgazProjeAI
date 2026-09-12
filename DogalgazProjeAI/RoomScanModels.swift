import Foundation

struct RoomScanSnapshot: Codable, Hashable {
    var widthMeters: Double
    var depthMeters: Double
    var heightMeters: Double
    var minX: Double
    var maxX: Double
    var minZ: Double
    var maxZ: Double
    var walls: [MeasuredWall]
    var openings: [MeasuredOpening]
    var capturedAt: Date

    var boundaryMeters: [Point2D] {
        guard !walls.isEmpty else { return [] }
        let tolerance = 0.12
        var remaining = walls
        var points: [Point2D] = [Point2D(x: remaining[0].startX, y: remaining[0].startZ), Point2D(x: remaining[0].endX, y: remaining[0].endZ)]
        remaining.removeFirst()
        while !remaining.isEmpty {
            let last = points.last!
            if let idx = remaining.indices.min(by: { hypot(remaining[$0].startX-last.x, remaining[$0].startZ-last.y) < hypot(remaining[$1].startX-last.x, remaining[$1].startZ-last.y) }),
               hypot(remaining[idx].startX-last.x, remaining[idx].startZ-last.y) <= tolerance {
                let w = remaining.remove(at: idx); points.append(Point2D(x: w.endX, y: w.endZ)); continue
            }
            if let idx = remaining.indices.min(by: { hypot(remaining[$0].endX-last.x, remaining[$0].endZ-last.y) < hypot(remaining[$1].endX-last.x, remaining[$1].endZ-last.y) }),
               hypot(remaining[idx].endX-last.x, remaining[idx].endZ-last.y) <= tolerance {
                let w = remaining.remove(at: idx); points.append(Point2D(x: w.startX, y: w.startZ)); continue
            }
            break
        }
        return points
    }

    var floorArea: Double {
        let p = boundaryMeters
        guard p.count >= 3 else { return widthMeters * depthMeters }
        var sum = 0.0
        for i in p.indices { let j = (i + 1) % p.count; sum += p[i].x * p[j].y - p[j].x * p[i].y }
        return abs(sum) / 2
    }

    /// RoomPlan metre koordinatını çizim için 0...1 uzayına çevirir.
    func normalizedPoint(x: Double, z: Double, inset: Double = 0.08) -> Point2D {
        let usable = 1 - (inset * 2)
        let nx = widthMeters > 0 ? (x - minX) / widthMeters : 0.5
        let nz = depthMeters > 0 ? (z - minZ) / depthMeters : 0.5
        return Point2D(
            x: inset + min(max(nx, 0), 1) * usable,
            y: inset + min(max(nz, 0), 1) * usable
        )
    }
}

extension RoomScanSnapshot {
    /// LiDAR bulunmayan cihazlar için metreyle girilen dikdörtgen oda geometrisi.
    static func rectangular(widthMeters: Double, depthMeters: Double, heightMeters: Double) -> Self {
        let walls = [
            MeasuredWall(centerX: widthMeters / 2, centerZ: 0, lengthMeters: widthMeters, heightMeters: heightMeters, yawRadians: 0),
            MeasuredWall(centerX: widthMeters, centerZ: depthMeters / 2, lengthMeters: depthMeters, heightMeters: heightMeters, yawRadians: .pi / 2),
            MeasuredWall(centerX: widthMeters / 2, centerZ: depthMeters, lengthMeters: widthMeters, heightMeters: heightMeters, yawRadians: 0),
            MeasuredWall(centerX: 0, centerZ: depthMeters / 2, lengthMeters: depthMeters, heightMeters: heightMeters, yawRadians: .pi / 2)
        ]
        return Self(widthMeters: widthMeters, depthMeters: depthMeters, heightMeters: heightMeters,
                    minX: 0, maxX: widthMeters, minZ: 0, maxZ: depthMeters,
                    walls: walls, openings: [], capturedAt: .now)
    }
}

struct MeasuredWall: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var centerX: Double
    var centerZ: Double
    var lengthMeters: Double
    var heightMeters: Double
    var yawRadians: Double

    var startX: Double { centerX - cos(yawRadians) * lengthMeters / 2 }
    var startZ: Double { centerZ - sin(yawRadians) * lengthMeters / 2 }
    var endX: Double { centerX + cos(yawRadians) * lengthMeters / 2 }
    var endZ: Double { centerZ + sin(yawRadians) * lengthMeters / 2 }
}

struct MeasuredOpening: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable { case door, window, opening }
    var id: UUID = UUID()
    var kind: Kind
    var centerX: Double
    var centerZ: Double
    var widthMeters: Double
    var heightMeters: Double
    var yawRadians: Double
}
