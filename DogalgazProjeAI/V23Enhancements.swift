import SwiftUI
import Foundation
import CryptoKit

struct ARRoomControlPoint: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var ar: WorldPoint3D
    var room: WorldPoint3D
}

extension ARRoomAlignment {
    var effectiveControlPoints: [ARRoomControlPoint] {
        if let controlPoints, controlPoints.count >= 2 { return controlPoints }
        return [
            .init(ar: arPointA, room: roomPointA),
            .init(ar: arPointB, room: roomPointB)
        ]
    }

    var leastSquaresSolution: (scale: Double, rotation: Double, tx: Double, tz: Double, verticalOffset: Double, rms: Double)? {
        let points = effectiveControlPoints
        guard points.count >= 2 else { return nil }

        let n = Double(points.count)
        let arCX = points.reduce(0) { $0 + $1.ar.x } / n
        let arCZ = points.reduce(0) { $0 + $1.ar.z } / n
        let roomCX = points.reduce(0) { $0 + $1.room.x } / n
        let roomCZ = points.reduce(0) { $0 + $1.room.z } / n

        var a = 0.0
        var b = 0.0
        var denom = 0.0
        for p in points {
            let ax = p.ar.x - arCX
            let az = p.ar.z - arCZ
            let rx = p.room.x - roomCX
            let rz = p.room.z - roomCZ
            a += ax * rx + az * rz
            b += ax * rz - az * rx
            denom += ax * ax + az * az
        }
        guard denom > 1e-8 else { return nil }
        let magnitude = hypot(a, b)
        let scale = magnitude / denom
        let rotation = atan2(b, a)
        let c = cos(rotation), s = sin(rotation)
        let tx = roomCX - scale * (arCX * c - arCZ * s)
        let tz = roomCZ - scale * (arCX * s + arCZ * c)
        let verticalOffset = points.reduce(0) { $0 + ($1.room.y - $1.ar.y) } / n

        var squared = 0.0
        for p in points {
            let px = scale * (p.ar.x * c - p.ar.z * s) + tx
            let pz = scale * (p.ar.x * s + p.ar.z * c) + tz
            squared += pow(px - p.room.x, 2) + pow(pz - p.room.z, 2)
        }
        let rms = sqrt(squared / n)
        return (scale, rotation, tx, tz, verticalOffset, rms)
    }

    var calibrationRMSErrorM: Double? { leastSquaresSolution?.rms }

    var calibrationVerticalRMSErrorM: Double? {
        let points = effectiveControlPoints
        guard points.count >= 2, let solution = leastSquaresSolution else { return nil }
        let mse = points.reduce(0.0) { partial, p in
            let predicted = p.ar.y + solution.verticalOffset
            return partial + pow(predicted - p.room.y, 2)
        } / Double(points.count)
        return sqrt(mse)
    }

    var minimumControlPointSeparationM: Double {
        let points = effectiveControlPoints
        guard points.count >= 2 else { return 0 }
        var best = Double.infinity
        for i in 0..<(points.count-1) {
            for j in (i+1)..<points.count {
                best = min(best, hypot(points[i].room.x-points[j].room.x, points[i].room.z-points[j].room.z))
            }
        }
        return best.isFinite ? best : 0
    }

    var controlPointSpreadAreaM2: Double {
        let points = effectiveControlPoints
        guard points.count >= 3 else { return 0 }
        let cx = points.map(\.room.x).reduce(0,+) / Double(points.count)
        let cz = points.map(\.room.z).reduce(0,+) / Double(points.count)
        let xx = points.reduce(0.0) { $0 + pow($1.room.x-cx,2) }
        let zz = points.reduce(0.0) { $0 + pow($1.room.z-cz,2) }
        let xz = points.reduce(0.0) { $0 + ($1.room.x-cx)*($1.room.z-cz) }
        return max(0, (xx*zz - xz*xz) / pow(Double(points.count),2))
    }

    var calibrationIsAcceptable: Bool {
        guard effectiveControlPoints.count >= 3,
              let h = calibrationRMSErrorM,
              let v = calibrationVerticalRMSErrorM else { return false }
        return h <= 0.10 && v <= 0.10 && minimumControlPointSeparationM >= 0.25 && controlPointSpreadAreaM2 >= 0.01
    }

    func leastSquaresRoomPoint(from ar: WorldPoint3D) -> WorldPoint3D {
        guard let solution = leastSquaresSolution else { return roomPoint(from: ar) }
        let c = cos(solution.rotation), s = sin(solution.rotation)
        let x = solution.scale * (ar.x * c - ar.z * s) + solution.tx
        let z = solution.scale * (ar.x * s + ar.z * c) + solution.tz
        return .init(x: x, y: ar.y + solution.verticalOffset, z: z)
    }
}

struct MultiPointARRoomAlignmentView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var points: [ARRoomControlPoint] = []

    var body: some View {
        Form {
            Section {
                Text("En az 3, tercihen 4 fiziksel referans noktası girin. Dikey eksen ölçeklenmez; yalnız kat datum farkı uygulanır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(points.indices, id: \.self) { index in
                Section("Referans \(index + 1)") {
                    HStack {
                        number("AR X", binding(index, \.ar.x))
                        number("AR Y", binding(index, \.ar.y))
                        number("AR Z", binding(index, \.ar.z))
                    }
                    HStack {
                        number("Plan X", binding(index, \.room.x))
                        number("Plan Y", binding(index, \.room.y))
                        number("Plan Z", binding(index, \.room.z))
                    }
                }
            }
            Section {
                Button("Referans Noktası Ekle") {
                    if points.count < 8 {
                        points.append(.init(ar: .init(x: 0, y: 0, z: 0), room: .init(x: 0, y: 0, z: 0)))
                    }
                }.disabled(points.count >= 8)
                if points.count > 3 {
                    Button("Son Noktayı Sil", role: .destructive) { points.removeLast() }
                }
            }
            Section("Kalibrasyon Kalitesi") {
                if let alignment = previewAlignment(), let rms = alignment.calibrationRMSErrorM {
                    LabeledContent("Yatay RMS", value: String(format: "%.1f cm", rms * 100))
                    LabeledContent("Dikey RMS", value: String(format: "%.1f cm", (alignment.calibrationVerticalRMSErrorM ?? .infinity) * 100))
                    LabeledContent("En yakın referans", value: String(format: "%.2f m", alignment.minimumControlPointSeparationM))
                    LabeledContent("Nokta yayılımı", value: String(format: "%.3f m²", alignment.controlPointSpreadAreaM2))
                    LabeledContent("Kalite", value: alignment.calibrationIsAcceptable ? quality(rms) : "Yetersiz")
                    if let s = alignment.leastSquaresSolution {
                        LabeledContent("Ölçek", value: String(format: "%.5f", s.scale))
                        LabeledContent("Dönme", value: String(format: "%.2f°", s.rotation * 180 / .pi))
                        LabeledContent("Dikey offset", value: String(format: "%.3f m", s.verticalOffset))
                    }
                } else {
                    Text("Kalibrasyon için en az iki farklı nokta gerekir.")
                }
            }
            Section {
                Button("Çok Noktalı Kalibrasyonu Kaydet") {
                    guard let alignment = previewAlignment(), points.count >= 3 else { return }
                    project.arRoomAlignment = alignment
                    onSave(project)
                }.disabled(points.count < 3 || previewAlignment()?.calibrationIsAcceptable != true)
            }
        }
        .navigationTitle("Çok Noktalı AR ↔ Plan")
        .onAppear {
            if let current = project.arRoomAlignment {
                points = current.effectiveControlPoints
            }
            while points.count < 4 {
                points.append(.init(ar: .init(x: Double(points.count), y: 0, z: 0), room: .init(x: Double(points.count), y: 0, z: 0)))
            }
        }
    }

    private func previewAlignment() -> ARRoomAlignment? {
        guard points.count >= 2 else { return nil }
        return ARRoomAlignment(
            arPointA: points[0].ar, roomPointA: points[0].room,
            arPointB: points[1].ar, roomPointB: points[1].room,
            calibratedAt: .now,
            controlPoints: points
        )
    }

    private func quality(_ rms: Double) -> String {
        if rms <= 0.02 { return "Çok iyi" }
        if rms <= 0.05 { return "İyi" }
        if rms <= 0.10 { return "Orta" }
        return "Zayıf"
    }

    private func binding(_ index: Int, _ kp: WritableKeyPath<ARRoomControlPoint, Double>) -> Binding<Double> {
        Binding(get: { points.indices.contains(index) ? points[index][keyPath: kp] : 0 },
                set: { if points.indices.contains(index) { points[index][keyPath: kp] = $0 } })
    }

    private func number(_ title: String, _ value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(3)))
            .keyboardType(.decimalPad)
    }
}

struct RoutePoint3D: Codable, Hashable {
    var x: Double
    var elevationM: Double
    var z: Double
}

struct Route3DResult: Hashable {
    var points: [RoutePoint3D]
    var lengthMeters: Double
    var verticalChangeMeters: Double
}

enum ObstacleAwareRouter3D {
    private struct Cell: Hashable { let x: Int; let z: Int; let y: Int }
    private struct Candidate { let cell: Cell; let score: Double }

    static func route(from start: RoutePoint3D, to goal: RoutePoint3D, project: GasProject) -> Route3DResult? {
        guard let scan = project.roomScan else { return nil }
        let xyStep = max(0.15, min(0.25, min(scan.widthMeters, scan.depthMeters) / 30))
        let yStep = 0.20
        let cols = max(3, Int(ceil(scan.widthMeters / xyStep)) + 1)
        let rows = max(3, Int(ceil(scan.depthMeters / xyStep)) + 1)
        let maxY = max(scan.heightMeters, max(start.elevationM, goal.elevationM) + 0.4)
        let levels = max(2, Int(ceil(maxY / yStep)) + 1)

        func cell(_ p: RoutePoint3D) -> Cell {
            .init(
                x: min(max(Int(round((p.x - scan.minX) / xyStep)), 0), cols - 1),
                z: min(max(Int(round((p.z - scan.minZ) / xyStep)), 0), rows - 1),
                y: min(max(Int(round(p.elevationM / yStep)), 0), levels - 1)
            )
        }
        func point(_ c: Cell) -> RoutePoint3D {
            .init(x: scan.minX + Double(c.x) * xyStep, elevationM: Double(c.y) * yStep, z: scan.minZ + Double(c.z) * xyStep)
        }
        func h(_ a: Cell, _ b: Cell) -> Double {
            Double(abs(a.x-b.x) + abs(a.z-b.z)) + Double(abs(a.y-b.y)) * 1.5
        }
        let boundary = scan.boundaryMeters
        func pointInPolygon(_ p: Point2D, _ polygon: [Point2D]) -> Bool {
            guard polygon.count >= 3 else { return false }
            var inside = false
            var j = polygon.count - 1
            for i in polygon.indices {
                let pi = polygon[i], pj = polygon[j]
                let denom = abs(pj.y-pi.y) < 1e-12 ? 1e-12 : (pj.y-pi.y)
                if ((pi.y > p.y) != (pj.y > p.y)) &&
                    (p.x < (pj.x-pi.x)*(p.y-pi.y)/denom + pi.x) { inside.toggle() }
                j = i
            }
            return inside
        }
        func inside(_ p: RoutePoint3D) -> Bool {
            let horizontal: Bool
            if boundary.count >= 3 {
                horizontal = pointInPolygon(.init(x:p.x,y:p.z), boundary)
            } else {
                horizontal = p.x >= scan.minX && p.x <= scan.maxX && p.z >= scan.minZ && p.z <= scan.maxZ
            }
            return horizontal && p.elevationM >= 0.1 && p.elevationM <= maxY
        }
        func distanceToWall(_ p: RoutePoint3D) -> Double {
            guard !scan.walls.isEmpty else { return 0.25 }
            func segDistance(_ x:Double,_ z:Double,_ ax:Double,_ az:Double,_ bx:Double,_ bz:Double)->Double {
                let vx=bx-ax, vz=bz-az, wx=x-ax, wz=z-az
                let l2=vx*vx+vz*vz
                if l2 < 1e-10 { return hypot(x-ax,z-az) }
                let t=max(0,min(1,(wx*vx+wz*vz)/l2))
                return hypot(x-(ax+t*vx),z-(az+t*vz))
            }
            return scan.walls.map { segDistance(p.x,p.z,$0.startX,$0.startZ,$0.endX,$0.endZ) }.min() ?? 0.25
        }
        func blocked(_ c: Cell, startCell: Cell, goalCell: Cell) -> Bool {
            if c == startCell || c == goalCell { return false }
            let p = point(c)
            guard inside(p) else { return true }
            for obstacle in project.spatialObstacles ?? [] {
                let margin = 0.12
                let horizontal = abs(p.x-obstacle.centerX) <= obstacle.widthMeters/2 + margin &&
                                 abs(p.z-obstacle.centerZ) <= obstacle.depthMeters/2 + margin
                let vertical = p.elevationM >= (obstacle.minElevationM ?? 0) - 0.05 &&
                               p.elevationM <= (obstacle.maxElevationM ?? scan.heightMeters) + 0.05
                if horizontal && vertical { return true }
            }
            // Kapı/pencere çevresinde yatay boru yerine üst/alt geçişe izin ver.
            for opening in scan.openings {
                let horizontal = hypot(p.x-opening.centerX, p.z-opening.centerZ) <= max(0.12, opening.widthMeters/2 + 0.10)
                if horizontal && p.elevationM <= opening.heightMeters + 0.12 { return true }
            }
            return false
        }

        let startCell = cell(start), goalCell = cell(goal)
        var open = [Candidate(cell: startCell, score: h(startCell, goalCell))]
        var came: [Cell: Cell] = [:]
        var cost: [Cell: Double] = [startCell: 0]
        var closed = Set<Cell>()
        let moves = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
        var iterations = 0

        while !open.isEmpty && iterations < 120_000 {
            iterations += 1
            open.sort { $0.score < $1.score }
            let current = open.removeFirst().cell
            if current == goalCell {
                var cells = [current], cursor = current
                while let prev = came[cursor] { cells.append(prev); cursor = prev }
                cells.reverse()
                var points = cells.map(point)
                if !points.isEmpty { points[0] = start; points[points.count-1] = goal }
                points = simplify(points)
                var length = 0.0, vertical = 0.0
                for pair in zip(points, points.dropFirst()) {
                    length += sqrt(pow(pair.1.x-pair.0.x,2)+pow(pair.1.z-pair.0.z,2)+pow(pair.1.elevationM-pair.0.elevationM,2))
                    vertical += abs(pair.1.elevationM-pair.0.elevationM)
                }
                return .init(points: points, lengthMeters: length, verticalChangeMeters: vertical)
            }
            if closed.contains(current) { continue }
            closed.insert(current)
            for m in moves {
                let next = Cell(x: current.x+m.0, z: current.z+m.1, y: current.y+m.2)
                guard next.x>=0,next.z>=0,next.y>=0,next.x<cols,next.z<rows,next.y<levels,
                      !closed.contains(next), !blocked(next,startCell:startCell,goalCell:goalCell) else { continue }
                let verticalMove = m.2 != 0
                let np = point(next)
                let wallDistance = distanceToWall(np)
                let wallPenalty = min(2.0, max(0, wallDistance - 0.18) * 2.5)
                let verticalPenalty = verticalMove ? 3.5 : 0.0
                let ceilingPenalty = np.elevationM > maxY - 0.15 ? 0.8 : 0.0
                let stepCost = 1.0 + wallPenalty + verticalPenalty + ceilingPenalty
                let tentative = (cost[current] ?? .infinity) + stepCost
                if tentative < (cost[next] ?? .infinity) {
                    cost[next] = tentative
                    came[next] = current
                    open.append(.init(cell: next, score: tentative + h(next,goalCell)))
                }
            }
        }
        return nil
    }

    private static func simplify(_ points: [RoutePoint3D]) -> [RoutePoint3D] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        for i in 1..<(points.count-1) {
            let a=result.last!, b=points[i], c=points[i+1]
            let v1=(b.x-a.x,b.z-a.z,b.elevationM-a.elevationM)
            let v2=(c.x-b.x,c.z-b.z,c.elevationM-b.elevationM)
            let same = abs(v1.0-v2.0)<1e-9 && abs(v1.1-v2.1)<1e-9 && abs(v1.2-v2.2)<1e-9
            if !same { result.append(b) }
        }
        result.append(points.last!)
        return result
    }
}

struct Route3DPlannerView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var startDeviceID: UUID?
    @State private var endDeviceID: UUID?
    @State private var result: Route3DResult?
    @State private var message = ""

    var body: some View {
        Form {
            if let analysis = project.resolvedAnalysis, let scan = project.roomScan {
                Section("Bağlantı") {
                    Picker("Başlangıç", selection: $startDeviceID) {
                        Text("Seç").tag(UUID?.none)
                        ForEach(analysis.devices) { Text($0.label).tag(Optional($0.id)) }
                    }
                    Picker("Bitiş", selection: $endDeviceID) {
                        Text("Seç").tag(UUID?.none)
                        ForEach(analysis.devices) { Text($0.label).tag(Optional($0.id)) }
                    }
                    Button("3B Güzergâh Hesapla") {
                        guard let aID=startDeviceID,let bID=endDeviceID,
                              let a=analysis.devices.first(where:{$0.id==aID}),
                              let b=analysis.devices.first(where:{$0.id==bID}) else { return }
                        let map=MetricProjectMapper(scan:scan)
                        let am=map.meters(a.position), bm=map.meters(b.position)
                        result=ObstacleAwareRouter3D.route(
                            from:.init(x:am.x,elevationM:a.elevationM ?? 1.7,z:am.y),
                            to:.init(x:bm.x,elevationM:b.elevationM ?? 1.7,z:bm.y),
                            project:project)
                        message=result == nil ? "Uygun 3B güzergâh bulunamadı." : "3B güzergâh hazır."
                    }
                }
                if let result {
                    Section("Sonuç") {
                        LabeledContent("Uzunluk",value:String(format:"%.2f m",result.lengthMeters))
                        LabeledContent("Düşey hareket",value:String(format:"%.2f m",result.verticalChangeMeters))
                        LabeledContent("Kırılma noktası",value:"\(result.points.count)")
                        Button("Taslak Boru Olarak Uygula") {
                            guard var raw=project.analysis,let scan=project.roomScan else{return}
                            let map=MetricProjectMapper(scan:scan)
                            project.addRevision(note:"3B güzergâh uygulanmadan önce")
                            for pair in zip(result.points,result.points.dropFirst()) {
                                raw.pipes.append(PipeSegment(
                                    id:UUID(),
                                    start:map.normalized(x:pair.0.x,y:pair.0.z),
                                    end:map.normalized(x:pair.1.x,y:pair.1.z),
                                    diameterMM:22,
                                    internalDiameterMM:nil,
                                    lengthMeters:sqrt(pow(pair.1.x-pair.0.x,2)+pow(pair.1.z-pair.0.z,2)+pow(pair.1.elevationM-pair.0.elevationM,2)),
                                    minorLossK:nil,
                                    elevationDeltaM:pair.1.elevationM-pair.0.elevationM,
                                    aiConfidence:nil,
                                    requiresReview:true,
                                    floorID:project.activeFloorID,
                                    startElevationM:pair.0.elevationM,
                                    endElevationM:pair.1.elevationM
                                ))
                            }
                            raw.materialSummary=HydraulicCalculator.estimateMaterialSummary(raw)
                            project.analysis=raw
                            if project.ruleProfile?.engineerVerified == true {
                                let sizing = PipeDiameterAdvisor.suggestions(for: project)
                                if !sizing.isEmpty {
                                    project = PipeDiameterAdvisor.applying(sizing, to: project)
                                    message = "3B güzergâh eklendi; hidrolik ağ yeniden hesaplandı ve çap önerileri uygulandı. Mühendis kontrolü bekliyor."
                                } else {
                                    message = "3B güzergâh eklendi; mevcut mühendislik limitlerinde ek çap değişikliği gerekmedi."
                                }
                            } else {
                                message="3B güzergâh taslak boru olarak eklendi; doğrulanmış kural profili olmadığı için otomatik çap uygulanmadı."
                            }
                            onSave(project)
                        }
                    }
                }
                if !message.isEmpty { Section { Text(message) } }
            } else {
                ContentUnavailableView("RoomPlan ve proje analizi gerekli",systemImage:"cube.transparent")
            }
        }.navigationTitle("3B Akıllı Güzergâh")
    }
}

extension GasProject {
    var approvalEvidenceBlockingReasons: [String] {
        var reasons: [String] = []
        let cloud = cloudArtifacts ?? []
        for record in fieldChecklist?.records ?? [] {
            guard let fileName = record.evidenceFileName else { continue }
            let localURL = FieldEvidenceStore.url(projectID: id, fileName: fileName)
            let localExists = localURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            if localExists {
                if let expected = record.evidenceSHA256,
                   FieldEvidenceStore.verify(projectID: id, fileName: fileName, expectedSHA256: expected) == false {
                    reasons.append("saha kanıtı SHA-256 doğrulaması başarısız: \(record.kind.title)")
                }
            } else if let expected = record.evidenceSHA256 {
                let verifiedCloudMatch = cloud.contains { artifact in
                    let sameHash = artifact.sha256.caseInsensitiveCompare(expected) == ComparisonResult.orderedSame
                    return sameHash && artifact.recentlyVerified
                }
                if !verifiedCloudMatch {
                    reasons.append("saha kanıtı yerelde yok; bulut kopyası son 24 saatte doğrulanmadı: \(record.kind.title)")
                }
            } else {
                reasons.append("saha kanıtı dosyası bulunamadı: \(record.kind.title)")
            }
        }
        if let ar = arCaptureArtifact {
            let dir = arCaptureDirectory
            let names = [ar.videoFileName, ar.trajectoryFileName] + (ar.depthFileName.map { [$0] } ?? [])
            for name in names {
                let local = dir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: local.path) &&
                    !cloud.contains(where: { $0.fileName == name && $0.recentlyVerified }) {
                    reasons.append("AR kanıtı yerelde yok; bulut kopyası son 24 saatte doğrulanmadı: \(name)")
                }
            }
        }
        if let alignment = arRoomAlignment, !alignment.calibrationIsAcceptable {
            reasons.append("AR ↔ RoomPlan kalibrasyon kalitesi yetersiz")
        }
        return reasons
    }

    var evidenceManifestForApproval: [String] {
        var hashes = Set<String>()
        for record in fieldChecklist?.records ?? [] {
            if let hash = record.evidenceSHA256 { hashes.insert(hash.lowercased()) }
        }
        for artifact in cloudArtifacts ?? [] {
            hashes.insert(artifact.sha256.lowercased())
        }
        if let artifact = arCaptureArtifact {
            let dir = arCaptureDirectory
            let urls = [
                dir.appendingPathComponent(artifact.videoFileName),
                dir.appendingPathComponent(artifact.trajectoryFileName)
            ] + (artifact.depthFileName.map { [dir.appendingPathComponent($0)] } ?? [])
            for url in urls {
                if let hash = Self.streamingSHA256(url) { hashes.insert(hash.lowercased()) }
            }
        }
        return hashes.sorted()
    }

    private static func streamingSHA256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while true {
                guard let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
