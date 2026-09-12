import SwiftUI
import Foundation

// MARK: - v1.7 obstacle-aware routing

enum ObstacleAwareRouter {
    private struct Cell: Hashable { let x: Int; let y: Int }
    private struct Node { let cell: Cell; let score: Double }

    static func route(from start: Point2D, to goal: Point2D, project: GasProject) -> [Point2D]? {
        guard let scan = project.roomScan else { return nil }
        let mapper = MetricProjectMapper(scan: scan)
        let s = mapper.meters(start), g = mapper.meters(goal)
        let step = max(0.12, min(0.25, min(scan.widthMeters, scan.depthMeters) / 35.0))
        let cols = max(3, Int(ceil(scan.widthMeters / step)) + 1)
        let rows = max(3, Int(ceil(scan.depthMeters / step)) + 1)
        let originX = scan.minX, originY = scan.minZ

        func cell(_ p: (x: Double, y: Double)) -> Cell {
            Cell(x: min(max(Int(round((p.x-originX)/step)), 0), cols-1),
                 y: min(max(Int(round((p.y-originY)/step)), 0), rows-1))
        }
        func meters(_ c: Cell) -> (x: Double, y: Double) { (originX + Double(c.x)*step, originY + Double(c.y)*step) }
        func heuristic(_ a: Cell, _ b: Cell) -> Double { Double(abs(a.x-b.x) + abs(a.y-b.y)) }

        let startCell = cell(s), goalCell = cell(g)
        let boundary = scan.boundaryMeters
        func insideRoom(_ p: (x: Double, y: Double)) -> Bool {
            guard boundary.count >= 3 else {
                return p.x >= scan.minX && p.x <= scan.maxX && p.y >= scan.minZ && p.y <= scan.maxZ
            }
            return pointInPolygon(Point2D(x: p.x, y: p.y), boundary)
        }
        func nearOpening(_ p: (x: Double, y: Double)) -> Bool {
            scan.openings.contains { opening in
                let clearance = max(0.18, opening.widthMeters / 2 + 0.12)
                return hypot(p.x-opening.centerX, p.y-opening.centerZ) < clearance
            }
        }
        func blocked(_ c: Cell) -> Bool {
            if c == startCell || c == goalCell { return false }
            let p = meters(c)
            return !insideRoom(p) || nearOpening(p)
        }

        var open: [Node] = [Node(cell: startCell, score: heuristic(startCell, goalCell))]
        var cameFrom: [Cell: Cell] = [:]
        var gScore: [Cell: Double] = [startCell: 0]
        var closed = Set<Cell>()
        let moves = [(1,0),(-1,0),(0,1),(0,-1)]
        var iterations = 0

        while !open.isEmpty && iterations < 25_000 {
            iterations += 1
            open.sort { $0.score < $1.score }
            let current = open.removeFirst().cell
            if current == goalCell {
                var path = [current]
                var cursor = current
                while let prev = cameFrom[cursor] { path.append(prev); cursor = prev }
                path.reverse()
                let normalized = path.map { c -> Point2D in
                    let p = meters(c); return mapper.normalized(x: p.x, y: p.y)
                }
                var result = simplify(normalized)
                if !result.isEmpty { result[0] = start; result[result.count-1] = goal }
                return result.count >= 2 ? result : nil
            }
            if closed.contains(current) { continue }
            closed.insert(current)

            for move in moves {
                let next = Cell(x: current.x + move.0, y: current.y + move.1)
                guard next.x >= 0, next.y >= 0, next.x < cols, next.y < rows, !blocked(next), !closed.contains(next) else { continue }
                let tentative = (gScore[current] ?? .greatestFiniteMagnitude) + 1
                if tentative < (gScore[next] ?? .greatestFiniteMagnitude) {
                    cameFrom[next] = current
                    gScore[next] = tentative
                    open.append(Node(cell: next, score: tentative + heuristic(next, goalCell)))
                }
            }
        }
        return nil
    }

    private static func simplify(_ points: [Point2D]) -> [Point2D] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        for i in 1..<(points.count-1) {
            let a = result.last!, b = points[i], c = points[i+1]
            let abx = b.x-a.x, aby = b.y-a.y, bcx = c.x-b.x, bcy = c.y-b.y
            if abs(abx*bcy - aby*bcx) > 1e-9 { result.append(b) }
        }
        result.append(points.last!)
        return result
    }

    private static func pointInPolygon(_ p: Point2D, _ polygon: [Point2D]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false, j = polygon.count - 1
        for i in polygon.indices {
            let pi = polygon[i], pj = polygon[j]
            let denom = (pj.y-pi.y) == 0 ? 1e-12 : (pj.y-pi.y)
            if ((pi.y > p.y) != (pj.y > p.y)) && (p.x < (pj.x-pi.x)*(p.y-pi.y)/denom + pi.x) { inside.toggle() }
            j = i
        }
        return inside
    }
}

// MARK: - Project quality score

struct ProjectQualityReport {
    var score: Int
    var items: [(String, Int, String)]
}

enum ProjectQualityAnalyzer {
    static func analyze(_ project: GasProject) -> ProjectQualityReport {
        let issues = ProjectValidator.validate(project)
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        var score = 100
        var items: [(String, Int, String)] = []

        let validationPenalty = min(50, errors * 15 + warnings * 4)
        score -= validationPenalty
        items.append(("Mühendislik ön kontrol", max(0, 40-validationPenalty), "\(errors) hata, \(warnings) uyarı"))

        let aiScore: Int
        if let analysis = project.resolvedAnalysis {
            let base = Int((analysis.confidence * 20).rounded())
            let unverified = analysis.devices.filter { ($0.type == .boiler || $0.type == .stove) && $0.modelVerifiedByUser != true }.count
            aiScore = max(0, base - min(8, unverified * 2))
        } else { aiScore = 0 }
        score -= max(0, 20-aiScore)
        items.append(("AI / cihaz doğruluğu", aiScore, "20 üzerinden"))

        let measureScore = project.roomScan == nil ? 0 : 15
        score -= 15-measureScore
        items.append(("Gerçek ölçü", measureScore, project.roomScan == nil ? "LiDAR/manuel ölçü yok" : "Ölçek mevcut"))

        let ruleScore = (project.ruleProfile?.engineerVerified == true && project.ruleProfile?.sourceDocumentHashSHA256 != nil) ? 15 : 0
        score -= 15-ruleScore
        items.append(("Kural profili", ruleScore, ruleScore == 15 ? "Doğrulanmış kaynak" : "Doğrulama eksik"))

        let reviewScore: Int
        if let a = project.resolvedAnalysis, project.reviewState?.isComplete(for: a) == true { reviewScore = 10 } else { reviewScore = 0 }
        score -= 10-reviewScore
        items.append(("Manuel kalite kontrol", reviewScore, reviewScore == 10 ? "Tamam" : "Eksik"))

        return ProjectQualityReport(score: min(max(score, 0), 100), items: items)
    }
}

struct ProjectQualityView: View {
    let project: GasProject
    private var report: ProjectQualityReport { ProjectQualityAnalyzer.analyze(project) }
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("\(report.score)/100").font(.system(size: 48, weight: .bold))
                    Text(report.score >= 90 ? "Yüksek hazırlık" : report.score >= 75 ? "İyi, kontrol gerekli" : "Eksikler tamamlanmalı").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical)
            }
            Section("Bileşenler") {
                ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading) { Text(item.0); Text(item.2).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text("+\(item.1)").monospacedDigit()
                    }
                }
            }
            Section { Text("Bu puan yazılım içi kalite göstergesidir; dağıtım şirketi veya yetkili mühendis onayı değildir.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Proje Kalite Puanı")
    }
}

// MARK: - Revision comparison

struct RevisionDifference {
    let deviceDelta: Int
    let pipeDelta: Int
    let pipeMeterDelta: Double
    let diameterChanges: Int
    let calibrationChanged: Bool
    let ruleChanged: Bool
}

enum RevisionDiffEngine {
    static func compare(_ newer: ProjectRevision, _ older: ProjectRevision) -> RevisionDifference {
        let na = newer.analysis, oa = older.analysis
        let nDevices = na?.devices.count ?? 0, oDevices = oa?.devices.count ?? 0
        let nPipes = na?.pipes.count ?? 0, oPipes = oa?.pipes.count ?? 0
        let nMeters = na?.pipes.reduce(0) { $0 + $1.lengthMeters } ?? 0
        let oMeters = oa?.pipes.reduce(0) { $0 + $1.lengthMeters } ?? 0
        let oldByID = Dictionary(uniqueKeysWithValues: (oa?.pipes ?? []).map { ($0.id, $0) })
        let diameterChanges = (na?.pipes ?? []).filter { p in oldByID[p.id].map { $0.diameterMM != p.diameterMM } ?? false }.count
        return .init(deviceDelta: nDevices-oDevices, pipeDelta: nPipes-oPipes, pipeMeterDelta: nMeters-oMeters, diameterChanges: diameterChanges, calibrationChanged: newer.calibration != older.calibration, ruleChanged: newer.ruleProfile != older.ruleProfile)
    }
}

struct RevisionComparisonView: View {
    let project: GasProject
    var body: some View {
        List {
            let revisions = project.revisions ?? []
            if revisions.count >= 2 {
                let diff = RevisionDiffEngine.compare(revisions[0], revisions[1])
                Section("Son iki revizyon") {
                    LabeledContent("Cihaz değişimi", value: signed(diff.deviceDelta))
                    LabeledContent("Boru segmenti", value: signed(diff.pipeDelta))
                    LabeledContent("Boru metrajı", value: String(format: "%+.2f m", diff.pipeMeterDelta))
                    LabeledContent("Çap değişikliği", value: "\(diff.diameterChanges)")
                    LabeledContent("Kalibrasyon", value: diff.calibrationChanged ? "Değişti" : "Aynı")
                    LabeledContent("Kural profili", value: diff.ruleChanged ? "Değişti" : "Aynı")
                }
                Section("Revizyonlar") {
                    ForEach(revisions.prefix(20)) { rev in
                        VStack(alignment: .leading) { Text(rev.note); Text(rev.createdAt.formatted()).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else {
                Text("Karşılaştırma için en az iki revizyon gerekli.").foregroundStyle(.secondary)
            }
        }.navigationTitle("Revizyon Karşılaştırma")
    }
    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}
