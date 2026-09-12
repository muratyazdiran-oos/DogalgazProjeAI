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
                    LabeledContent("RMS hata", value: String(format: "%.1f cm", rms * 100))
                    LabeledContent("Kalite", value: quality(rms))
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
                }.disabled(points.count < 3 || previewAlignment()?.leastSquaresSolution == nil)
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
        func inside(_ p: RoutePoint3D) -> Bool {
            p.x >= scan.minX && p.x <= scan.maxX && p.z >= scan.minZ && p.z <= scan.maxZ &&
            p.elevationM >= 0.1 && p.elevationM <= maxY
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
                let stepCost = verticalMove ? 2.5 : 1.0
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
                            onSave(project)
                            message="3B güzergâh taslak boru olarak eklendi; mühendis kontrolü bekliyor."
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
    var evidenceManifestForApproval: [String] {
        var hashes: [String] = []
        for record in fieldChecklist?.records ?? [] {
            if let hash=record.evidenceSHA256 { hashes.append("field:\(record.kind.rawValue):\(hash)") }
        }
        for artifact in cloudArtifacts ?? [] {
            hashes.append("cloud:\(artifact.kind):\(artifact.fileName):\(artifact.sha256)")
        }
        if let artifact=arCaptureArtifact {
            let dir=arCaptureDirectory
            let urls=[
                ("ar-video",dir.appendingPathComponent(artifact.videoFileName)),
                ("ar-trajectory",dir.appendingPathComponent(artifact.trajectoryFileName))
            ] + (artifact.depthFileName.map{[("ar-depth",dir.appendingPathComponent($0))]} ?? [])
            for (kind,url) in urls {
                if let hash=Self.streamingSHA256(url) { hashes.append("\(kind):\(hash)") }
            }
        }
        return hashes.sorted()
    }

    private static func streamingSHA256(_ url: URL) -> String? {
        guard let handle=try? FileHandle(forReadingFrom:url) else{return nil}
        defer{try? handle.close()}
        var hasher=SHA256()
        while autoreleasepool(invoking:{
            guard let data=try? handle.read(upToCount:1024*1024),let data,!data.isEmpty else{return false}
            hasher.update(data:data);return true
        }){}
        return hasher.finalize().map{String(format:"%02x",$0)}.joined()
    }
}
