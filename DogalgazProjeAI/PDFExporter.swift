import UIKit
import SwiftUI

@MainActor
enum PDFExporter {
    static func create(project: GasProject) throws -> URL {
        guard let analysis = project.resolvedAnalysis else { throw ExportError.noAnalysis }
        let page = CGSize(width: 842, height: 595) // A4 yatay @ 72 pt/in
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page))
        let revision = project.revisions?.count ?? 0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe(project.name))-REV\(revision)-proje.pdf")

        try renderer.writePDF(to: url) { context in
            context.beginPage()
            let cg = context.cgContext
            drawFrame(cg: cg, page: page)
            drawHeader(project, cg: cg)
            drawPlan(analysis, cg: cg, rect: CGRect(x: 34, y: 82, width: 560, height: 410))
            drawRightPanel(project: project, analysis: analysis, cg: cg, rect: CGRect(x: 610, y: 82, width: 198, height: 410))
            drawTitleBlock(project: project, analysis: analysis, cg: cg, rect: CGRect(x: 34, y: 502, width: 774, height: 58))
            drawFooter(cg: cg, page: page)
        }
        return url
    }

    private static func drawFrame(cg: CGContext, page: CGSize) {
        cg.setStrokeColor(UIColor.label.cgColor)
        cg.setLineWidth(1)
        cg.stroke(CGRect(x: 24, y: 18, width: page.width - 48, height: page.height - 42))
    }

    private static func drawHeader(_ project: GasProject, cg: CGContext) {
        NSString(string: "DOĞALGAZ TESİSAT PROJESİ • AI ÖN TASLAK")
            .draw(at: CGPoint(x: 34, y: 30), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18)])
        NSString(string: "Proje: \(project.name)")
            .draw(at: CGPoint(x: 34, y: 55), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
        let rev = DateFormatter.localizedString(from: .now, dateStyle: .short, timeStyle: .short)
        let revision = project.revisions?.count ?? 0
        let hash = project.engineeringContentHashSHA256().map { String($0.prefix(12)) } ?? "—"
        NSString(string: "REV \(revision) • SHA \(hash) • \(rev)")
            .draw(at: CGPoint(x: 610, y: 55), withAttributes: [.font: UIFont.systemFont(ofSize: 8)])
    }

    private static func drawPlan(_ a: ProjectAnalysis, cg: CGContext, rect: CGRect) {
        cg.saveGState()
        cg.setStrokeColor(UIColor.separator.cgColor)
        cg.stroke(rect)

        func p(_ q: Point2D) -> CGPoint {
            CGPoint(x: rect.minX + q.x * rect.width, y: rect.minY + q.y * rect.height)
        }

        cg.setStrokeColor(UIColor.label.cgColor)
        cg.setLineWidth(1.4)
        for room in a.rooms where room.polygon.count > 2 {
            cg.beginPath()
            cg.move(to: p(room.polygon[0]))
            for q in room.polygon.dropFirst() { cg.addLine(to: p(q)) }
            cg.closePath(); cg.strokePath()
            let center = polygonCenter(room.polygon)
            NSString(string: room.name).draw(at: CGPoint(x: p(center).x - 24, y: p(center).y - 6), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 8)])
        }

        cg.setStrokeColor(UIColor.systemOrange.cgColor)
        cg.setLineWidth(3)
        for pipe in a.pipes {
            let s = p(pipe.start), e = p(pipe.end)
            cg.move(to: s); cg.addLine(to: e); cg.strokePath()
            let diameter = pipe.diameterMM > 0 ? "Ø\(pipe.diameterMM)" : "Ø?"
            NSString(string: "\(diameter) • \(String(format: "%.2f", pipe.lengthMeters)) m")
                .draw(at: CGPoint(x: (s.x + e.x) / 2 + 3, y: (s.y + e.y) / 2 - 13), withAttributes: [.font: UIFont.systemFont(ofSize: 7.5)])
        }

        for d in a.devices {
            let q = p(d.position)
            let box = CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)
            cg.setFillColor(UIColor.systemBlue.cgColor)
            cg.fillEllipse(in: box)
            var label = d.label
            if let kw = d.capacityKW { label += " (\(String(format: "%.1f", kw)) kW)" }
            NSString(string: label).draw(at: CGPoint(x: q.x + 7, y: q.y - 5), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 7.5)])
        }

        cg.setStrokeColor(UIColor.systemGray.cgColor)
        cg.setLineWidth(0.8)
        for dim in a.dimensions {
            let s = p(dim.start), e = p(dim.end)
            cg.move(to: s); cg.addLine(to: e); cg.strokePath()
            NSString(string: String(format: "%.2f m", dim.meters))
                .draw(at: CGPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2 + 4), withAttributes: [.font: UIFont.systemFont(ofSize: 7)])
        }
        cg.restoreGState()
    }

    private static func drawRightPanel(project: GasProject, analysis: ProjectAnalysis, cg: CGContext, rect: CGRect) {
        cg.setStrokeColor(UIColor.separator.cgColor)
        cg.stroke(rect)
        let settings = project.resolvedEngineeringSettings
        let eng = EngineeringCalculator.summarize(analysis, settings: settings)
        let hydraulic = HydraulicCalculator.calculate(analysis, settings: settings)
        let validation = ProjectValidator.validate(project)
        let errors = validation.filter { $0.severity == .error }.count
        let warnings = validation.filter { $0.severity == .warning }.count

        var lines = [
            "HESAP / KEŞİF ÖZETİ",
            "AI güveni: %\(Int(analysis.confidence * 100))",
            String(format: "Toplam güç: %.1f kW", eng.totalLoadKW),
            String(format: "Yakl. debi: %.2f m³/h", eng.estimatedGasFlowM3h),
            String(format: "Toplam boru: %.2f m", eng.totalPipeMeters),
            "Gaz cihazı: \(eng.gasDeviceCount)",
            "Ön kontrol: \(errors) hata / \(warnings) uyarı",
            "",
            "HİDROLİK ÖN KONTROL",
            hydraulic.message,
            hydraulic.criticalPressureDropMbar.map { String(format: "Kritik Δp: %.3f mbar", $0) } ?? "Kritik Δp: —",
            hydraulic.maximumVelocityMS.map { String(format: "Maks. hız: %.2f m/s", $0) } ?? "Maks. hız: —",
            "Profil: \(settings.profileName)",
            "Revizyon: \(settings.profileRevision)",
            project.ruleProfile.map { "Kural kaynağı: \($0.authority)" } ?? "Kural kaynağı: —",
            project.reviewState.map { "AI kalite kontrolü: \($0.isComplete(for: analysis) ? "tamam" : "eksik")" } ?? "AI kalite kontrolü: yapılmadı",
            "",
            "MALZEME ÖZETİ",
            "Vana: \(analysis.materialSummary.valves)",
            "Dirsek (tahmini): \(analysis.materialSummary.elbows)",
            "Tee (tahmini): \(analysis.materialSummary.tees)",
            "Menfez: \(analysis.materialSummary.vents)",
            project.quoteSettings.map { String(format: "Teklif toplamı: %.2f %@", $0.total(for: analysis.materialSummary), $0.currency) } ?? "Teklif toplamı: —",
            "",
            "LEJANT",
            "Mavi nokta: cihaz",
            "Turuncu çizgi: gaz borusu",
            "Gri çizgi: ölçü",
            "",
            "AI NOTLARI"
        ]
        lines.append(contentsOf: analysis.notes.prefix(4).map { "• \($0)" })
        NSString(string: lines.joined(separator: "\n"))
            .draw(in: rect.insetBy(dx: 8, dy: 8), withAttributes: [.font: UIFont.systemFont(ofSize: 7.5)])
    }

    private static func drawTitleBlock(project: GasProject, analysis: ProjectAnalysis, cg: CGContext, rect: CGRect) {
        cg.setStrokeColor(UIColor.label.cgColor)
        cg.setLineWidth(0.8)
        cg.stroke(rect)
        let c1 = rect.minX + 250, c2 = rect.minX + 510, c3 = rect.minX + 650
        for x in [c1, c2, c3] { cg.move(to: CGPoint(x: x, y: rect.minY)); cg.addLine(to: CGPoint(x: x, y: rect.maxY)); cg.strokePath() }

        drawSmall("MÜŞTERİ / ADRES", at: CGPoint(x: rect.minX + 6, y: rect.minY + 5), bold: true)
        drawSmall(project.customerName.isEmpty ? "—" : project.customerName, at: CGPoint(x: rect.minX + 6, y: rect.minY + 20))
        drawSmall(project.address.isEmpty ? "—" : project.address, in: CGRect(x: rect.minX + 6, y: rect.minY + 33, width: 238, height: 20))

        drawSmall("PROJE", at: CGPoint(x: c1 + 6, y: rect.minY + 5), bold: true)
        drawSmall(project.name, at: CGPoint(x: c1 + 6, y: rect.minY + 20))
        drawSmall("AI ön taslak • Ölçek: şematik", at: CGPoint(x: c1 + 6, y: rect.minY + 34))
        drawSmall(project.resolvedEngineeringSettings.profileRevision, at: CGPoint(x: c1 + 6, y: rect.minY + 45))

        drawSmall("REVİZYON", at: CGPoint(x: c2 + 6, y: rect.minY + 5), bold: true)
        drawSmall(DateFormatter.localizedString(from: .now, dateStyle: .short, timeStyle: .none), at: CGPoint(x: c2 + 6, y: rect.minY + 22))

        drawSmall("ONAY", at: CGPoint(x: c3 + 6, y: rect.minY + 5), bold: true)
        let approval = project.approvalWorkflow
        drawSmall(approval?.engineerName.isEmpty == false ? approval!.engineerName : "Yetkili mühendis", at: CGPoint(x: c3 + 6, y: rect.minY + 18))
        drawSmall(approval?.engineerRegistration.isEmpty == false ? approval!.engineerRegistration : "sicil / oda no", at: CGPoint(x: c3 + 6, y: rect.minY + 30))
        if let base64 = approval?.engineerSignaturePNGBase64, let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
            image.draw(in: CGRect(x: c3 + 78, y: rect.minY + 6, width: 54, height: 26))
        }
        if let base64 = approval?.stampImagePNGBase64, let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
            image.draw(in: CGRect(x: c3 + 78, y: rect.minY + 31, width: 54, height: 22))
        } else {
            drawSmall(approval?.stampText.isEmpty == false ? approval!.stampText : "imza / kaşe", at: CGPoint(x: c3 + 6, y: rect.minY + 43))
        }
    }

    private static func drawFooter(cg: CGContext, page: CGSize) {
        NSString(string: "Bu pafta saha keşfi ve AI yardımıyla oluşturulan ön taslaktır; resmî proje/onay değildir. Kritik hat, basınç kaybı, boru çapları, havalandırma, baca ve dağıtım şirketi şartları yetkili mühendis tarafından doğrulanmalıdır.")
            .draw(in: CGRect(x: 34, y: 568, width: page.width - 68, height: 16), withAttributes: [.font: UIFont.systemFont(ofSize: 6.8), .foregroundColor: UIColor.secondaryLabel])
    }

    private static func drawSmall(_ text: String, at point: CGPoint, bold: Bool = false) {
        NSString(string: text).draw(at: point, withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: 7.5) : UIFont.systemFont(ofSize: 7.5)])
    }

    private static func drawSmall(_ text: String, in rect: CGRect) {
        NSString(string: text).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: 6.8)])
    }

    private static func polygonCenter(_ points: [Point2D]) -> Point2D {
        guard !points.isEmpty else { return .init(x: 0.5, y: 0.5) }
        return .init(x: points.map(\.x).reduce(0, +) / Double(points.count), y: points.map(\.y).reduce(0, +) / Double(points.count))
    }

    private static func safe(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
    }

    enum ExportError: Error { case noAnalysis }
}
