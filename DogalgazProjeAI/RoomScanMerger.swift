import Foundation

/// AI'nin semantik tespitini RoomPlan'ın metre cinsinden geometrisiyle birleştirir.
/// v0.4: gerçek duvar segmentleri çizilir, AI cihazları duvara yapıştırılır ve boru metrajı yeniden hesaplanır.
enum RoomScanMerger {
    static func merge(_ scan: RoomScanSnapshot, into analysis: ProjectAnalysis?) -> ProjectAnalysis {
        var result = analysis ?? ProjectAnalysis(
            confidence: 1,
            notes: [],
            rooms: [],
            pipes: [],
            devices: [],
            dimensions: [],
            materialSummary: .init(totalPipeMeters: 0, valves: 0, elbows: 0, tees: 0, vents: 0)
        )

        // RoomPlan duvar uçlarını doğrudan 2B proje geometrisine dönüştür.
        let boundary = scan.boundaryMeters.map { scan.normalizedPoint(x: $0.x, z: $0.y) }
        if boundary.count >= 3 {
            result.rooms = [RoomShape(id: UUID(), name: "RoomPlan • Taranan Alan", polygon: boundary)]
        }

        // Duvara montajlı cihazları en yakın gerçek duvar segmentine yaklaştır.
        result.devices = result.devices.map { device in
            var updated = device
            if [.meter, .boiler, .vent, .valve].contains(device.type), !scan.walls.isEmpty {
                updated.position = snapToNearestWall(device.position, scan: scan)
            }
            return updated
        }

        // Boru noktalarını gerçek ölçeğe göre metre cinsinden yeniden hesapla.
        result.pipes = result.pipes.map { pipe in
            var updated = pipe
            updated.lengthMeters = metricDistance(pipe.start, pipe.end, scan: scan)
            return updated
        }

        result.dimensions = makeDimensions(scan: scan)

        result.materialSummary = HydraulicCalculator.estimateMaterialSummary(result)

        result.notes.removeAll { $0.hasPrefix("RoomPlan:") || $0.hasPrefix("Eşleştirme:") }
        result.notes.insert(
            String(format: "RoomPlan: %.2f × %.2f m, yükseklik %.2f m, yaklaşık alan %.2f m²; %d duvar ve %d açıklık.", scan.widthMeters, scan.depthMeters, scan.heightMeters, scan.floorArea, scan.walls.count, scan.openings.count),
            at: 0
        )
        result.notes.insert(
            "Eşleştirme: Kombi/sayaç/vana/menfez AI konumları en yakın RoomPlan duvarına oturtuldu; boru metrajı tarama ölçeğinden yeniden hesaplandı.",
            at: min(1, result.notes.count)
        )
        return result
    }

    private static func makeDimensions(scan: RoomScanSnapshot) -> [DimensionLine] {
        var lines: [DimensionLine] = [
            DimensionLine(id: UUID(), start: .init(x: 0.08, y: 0.95), end: .init(x: 0.92, y: 0.95), meters: scan.widthMeters),
            DimensionLine(id: UUID(), start: .init(x: 0.035, y: 0.08), end: .init(x: 0.035, y: 0.92), meters: scan.depthMeters)
        ]

        // Her gerçek duvar için kendi uzunluğunu da ölçü etiketi olarak ekle.
        for wall in scan.walls {
            lines.append(DimensionLine(
                id: UUID(),
                start: scan.normalizedPoint(x: wall.startX, z: wall.startZ),
                end: scan.normalizedPoint(x: wall.endX, z: wall.endZ),
                meters: wall.lengthMeters
            ))
        }
        return lines
    }

    private static func metricDistance(_ a: Point2D, _ b: Point2D, scan: RoomScanSnapshot) -> Double {
        // normalizedPoint inset=0.08 kullandığı için 0.84 çizim aralığı gerçek oda boyutuna karşılık gelir.
        let usable = 0.84
        let dxMeters = ((b.x - a.x) / usable) * scan.widthMeters
        let dzMeters = ((b.y - a.y) / usable) * scan.depthMeters
        return (dxMeters * dxMeters + dzMeters * dzMeters).squareRoot()
    }

    private static func snapToNearestWall(_ p: Point2D, scan: RoomScanSnapshot) -> Point2D {
        let normalizedWalls = scan.walls.map { wall in
            (
                scan.normalizedPoint(x: wall.startX, z: wall.startZ),
                scan.normalizedPoint(x: wall.endX, z: wall.endZ)
            )
        }
        guard let nearest = normalizedWalls
            .map({ segment in (point: closestPoint(p, segment.0, segment.1), distance: distance(p, closestPoint(p, segment.0, segment.1))) })
            .min(by: { $0.distance < $1.distance }) else { return p }
        return nearest.point
    }

    private static func closestPoint(_ p: Point2D, _ a: Point2D, _ b: Point2D) -> Point2D {
        let vx = b.x - a.x, vy = b.y - a.y
        let wx = p.x - a.x, wy = p.y - a.y
        let vv = vx * vx + vy * vy
        guard vv > 0 else { return a }
        let t = min(1, max(0, (wx * vx + wy * vy) / vv))
        return Point2D(x: a.x + t * vx, y: a.y + t * vy)
    }

    private static func distance(_ a: Point2D, _ b: Point2D) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

}
