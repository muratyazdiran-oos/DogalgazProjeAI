import SwiftUI
import Foundation
import UIKit

// MARK: - v1.5 advanced field workflow

struct RouteSuggestion: Identifiable, Hashable {
    let id = UUID()
    let targetDeviceID: UUID
    let targetLabel: String
    let points: [Point2D]
    let estimatedMeters: Double
}

enum SmartRoutePlanner {
    static func suggestions(for project: GasProject) -> [RouteSuggestion] {
        guard let analysis = project.analysis,
              let meter = analysis.devices.first(where: { $0.type == .meter }),
              let scan = project.roomScan else { return [] }
        let mapper = MetricProjectMapper(scan: scan)
        let targets = analysis.devices.filter { $0.type == .boiler || $0.type == .stove }
        return targets.compactMap { target in
            let chosen = ObstacleAwareRouter.route(from: meter.position, to: target.position, project: project) ?? {
                let a = meter.position, b = target.position
                let c1 = Point2D(x: b.x, y: a.y)
                let c2 = Point2D(x: a.x, y: b.y)
                let route1 = [a, c1, b], route2 = [a, c2, b]
                return routePenalty(route1, rooms: analysis.rooms, mapper: mapper) <= routePenalty(route2, rooms: analysis.rooms, mapper: mapper) ? route1 : route2
            }()
            return RouteSuggestion(targetDeviceID: target.id, targetLabel: target.label, points: chosen, estimatedMeters: metricLength(chosen, mapper: mapper))
        }
    }

    static func applying(_ suggestions: [RouteSuggestion], to project: GasProject) -> GasProject {
        guard var analysis = project.analysis, let scan = project.roomScan else { return project }
        let mapper = MetricProjectMapper(scan: scan)
        var copy = project
        copy.addRevision(note: "Akıllı güzergâh önerisi uygulanmadan önce")
        let existingPairs = Set(analysis.pipes.map { pairKey($0.start, $0.end) })
        var seen = existingPairs
        for suggestion in suggestions {
            for index in 0..<(suggestion.points.count - 1) {
                let start = suggestion.points[index], end = suggestion.points[index + 1]
                let key = pairKey(start, end)
                guard !seen.contains(key) else { continue }
                let a = mapper.meters(start), b = mapper.meters(end)
                analysis.pipes.append(PipeSegment(id: UUID(), start: start, end: end, diameterMM: 0, lengthMeters: hypot(b.x-a.x, b.y-a.y), minorLossK: nil, elevationDeltaM: nil, aiConfidence: nil, requiresReview: true, floorID: project.activeFloorID))
                seen.insert(key)
            }
        }
        analysis.materialSummary = HydraulicCalculator.estimateMaterialSummary(analysis)
        copy.analysis = analysis
        return copy
    }

    private static func pairKey(_ a: Point2D, _ b: Point2D) -> String {
        func q(_ v: Double) -> Int { Int((v * 10000).rounded()) }
        let p1 = "\(q(a.x)),\(q(a.y))", p2 = "\(q(b.x)),\(q(b.y))"
        return p1 < p2 ? p1 + ":" + p2 : p2 + ":" + p1
    }

    private static func metricLength(_ points: [Point2D], mapper: MetricProjectMapper) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { sum, pair in
            let a = mapper.meters(pair.0), b = mapper.meters(pair.1)
            return sum + hypot(b.x-a.x, b.y-a.y)
        }
    }

    private static func routePenalty(_ points: [Point2D], rooms: [RoomShape], mapper: MetricProjectMapper) -> Double {
        var penalty = metricLength(points, mapper: mapper)
        guard !rooms.isEmpty else { return penalty }
        for (a,b) in zip(points, points.dropFirst()) {
            for i in 0...12 {
                let t = Double(i)/12
                let p = Point2D(x: a.x+(b.x-a.x)*t, y: a.y+(b.y-a.y)*t)
                if !rooms.contains(where: { pointInPolygon(p, $0.polygon) }) { penalty += 50 }
            }
        }
        return penalty
    }

    private static func pointInPolygon(_ p: Point2D, _ polygon: [Point2D]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false, j = polygon.count - 1
        for i in polygon.indices {
            let pi = polygon[i], pj = polygon[j]
            let crosses = ((pi.y > p.y) != (pj.y > p.y)) && (p.x < (pj.x-pi.x) * (p.y-pi.y) / ((pj.y-pi.y) == 0 ? 1e-12 : (pj.y-pi.y)) + pi.x)
            if crosses { inside.toggle() }
            j = i
        }
        return inside
    }
}

struct SmartRoutePlannerView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var suggestions: [RouteSuggestion] = []

    var body: some View {
        List {
            Section {
                Text("Sayaçtan kombi/ocak noktalarına ölçülü L-tip güzergâh taslakları üretir. Bu öneri mevzuat, yapı elemanları ve saha engelleri için mühendis kontrolünün yerini almaz.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Güzergâh Önerilerini Hesapla") { suggestions = SmartRoutePlanner.suggestions(for: project) }
            }
            Section("Öneriler") {
                if suggestions.isEmpty { Text("Henüz öneri üretilmedi.").foregroundStyle(.secondary) }
                ForEach(suggestions) { s in
                    HStack { Text(s.targetLabel); Spacer(); Text(String(format: "%.2f m", s.estimatedMeters)).foregroundStyle(.secondary) }
                }
            }
            if !suggestions.isEmpty {
                Section { Button("Önerileri Projeye Taslak Olarak Ekle") { let p = SmartRoutePlanner.applying(suggestions, to: project); project = p; onSave(p) } }
            }
        }.navigationTitle("Akıllı Güzergâh")
    }
}

struct OfflineSyncItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var projectID: UUID
    var queuedAt: Date = .now
    var payload: GasProject
}

enum OfflineSyncQueue {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DogalgazProjeAI/OfflineSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func all() -> [OfflineSyncItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder.standard.decode(OfflineSyncItem.self, from: data)
        }.sorted { $0.queuedAt < $1.queuedAt }
    }

    static func enqueue(_ project: GasProject) {
        let item = OfflineSyncItem(projectID: project.id, payload: project)
        guard let data = try? JSONEncoder.pretty.encode(item) else { return }
        let url = directory.appendingPathComponent("\(project.id.uuidString).json")
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        trim(maximum: 50)
    }

    static func remove(projectID: UUID) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(projectID.uuidString).json"))
    }

    private static func trim(maximum: Int) {
        let items = all()
        guard items.count > maximum else { return }
        for item in items.prefix(items.count - maximum) { remove(projectID: item.projectID) }
    }
}

enum QuotePDFExporter {
    static func create(project: GasProject) throws -> URL {
        guard let summary = project.resolvedAnalysis?.materialSummary else { throw ExportError.noAnalysis }
        let quote = project.quoteSettings ?? .init()
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 42
            func draw(_ text: String, size: CGFloat = 11, bold: Bool = false) {
                let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
                text.draw(in: CGRect(x: 42, y: y, width: 511, height: 28), withAttributes: [.font: font, .foregroundColor: UIColor.black])
                y += size + 12
            }
            draw("DOĞALGAZ PROJE / METRAJ TEKLİFİ", size: 18, bold: true)
            if let company = quote.companyName, !company.isEmpty { draw(company, size: 14, bold: true) }
            if let info = quote.companyTaxInfo, !info.isEmpty { draw(info, size: 9) }
            if let number = quote.quoteNumber, !number.isEmpty { draw("Teklif No: \(number)") }
            draw("Proje: \(project.name)", bold: true)
            if !project.customerName.isEmpty { draw("Müşteri: \(project.customerName)") }
            if !project.address.isEmpty { draw("Adres: \(project.address)") }
            draw("Tarih: \(Date().formatted(date: .numeric, time: .omitted))")
            draw("Geçerlilik: \(quote.validDays ?? 7) gün")
            if let terms = quote.paymentTerms, !terms.isEmpty { draw("Ödeme: \(terms)") }
            y += 8
            draw(String(format:"Boru: %.2f m × %.2f = %.2f %@", summary.totalPipeMeters, quote.pipePerMeter, summary.totalPipeMeters*quote.pipePerMeter, quote.currency))
            draw("Vana: \(summary.valves) × \(String(format: "%.2f", quote.valveUnit))")
            draw("Dirsek: \(summary.elbows) × \(String(format: "%.2f", quote.elbowUnit))")
            draw("Tee: \(summary.tees) × \(String(format: "%.2f", quote.teeUnit))")
            draw("Menfez: \(summary.vents) × \(String(format: "%.2f", quote.ventUnit))")
            draw("İşçilik: \(String(format: "%.2f", quote.labor)) \(quote.currency)")
            draw("KDV: %\(String(format: "%.1f", quote.taxRatePercent))")
            y += 8
            draw("GENEL TOPLAM: \(String(format: "%.2f", quote.total(for: summary))) \(quote.currency)", size: 16, bold: true)
            y += 14
            if let note = quote.commercialNote, !note.isEmpty { draw("Not: \(note)", size: 9) }
            draw("Bu teklif projedeki metraj verilerinden otomatik üretilmiştir. Saha ve ürün fiyat teyidi gerektirir.", size: 9)
            if let hash = project.engineeringContentHashSHA256() { draw("Proje SHA-256: \(hash)", size: 7) }
        }
        let safe = project.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe)-Teklif-v2.1.pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
    enum ExportError: LocalizedError { case noAnalysis; var errorDescription: String? { "Teklif için proje analizi gerekli." } }
}

struct FieldAutomationView: View {
    @Binding var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Saha Otomasyonu") {
                NavigationLink("Akıllı Boru Güzergâhı") { SmartRoutePlannerView(project: project, onSave: { p in project = p; onSave(p) }) }
                LabeledContent("Bekleyen offline senkron", value: "\(OfflineSyncQueue.all().count)")
            }
            Section("Teklif") {
                Button("PDF Teklif Oluştur") {
                    do { shareURL = try QuotePDFExporter.create(project: project); showShare = true }
                    catch { self.error = error.localizedDescription }
                }
            }
            Section("GasLine / CAD") {
                Text("DXF, gerçek mm ölçeğinde AutoCAD'de açılır ve GasLine'ın DXF içe aktarma akışında kullanılabilir. Native GasLine akıllı proje formatı üretilmez.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saha Otomasyonu")
        .sheet(isPresented: $showShare) { if let shareURL { ShareSheet(items: [shareURL]) } }
        .alert("Hata", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
