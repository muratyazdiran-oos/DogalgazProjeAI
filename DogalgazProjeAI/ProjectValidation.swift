import Foundation

enum ValidationSeverity: String, Codable, Hashable { case error, warning, info }

struct ValidationIssue: Identifiable, Codable, Hashable {
    var id = UUID()
    var severity: ValidationSeverity
    var title: String
    var detail: String
}

enum ProjectValidator {
    static func validate(_ project: GasProject) -> [ValidationIssue] {
        guard let analysis = project.resolvedAnalysis else {
            return [.init(severity: .error, title: "Analiz yok", detail: "Video analizi veya manuel proje çizimi tamamlanmalı.")]
        }

        let settings = project.resolvedEngineeringSettings
        let engineering = EngineeringCalculator.summarize(analysis, settings: settings)
        let hydraulic = HydraulicCalculator.calculate(analysis, settings: settings)
        var issues: [ValidationIssue] = []

        if project.roomScan == nil {
            issues.append(.init(severity: .warning, title: "Ölçek doğrulanmadı", detail: "LiDAR taraması veya manuel gerçek ölçü girilmedi."))
        }

        let meters = analysis.devices.filter { $0.type == .meter }
        if meters.isEmpty {
            issues.append(.init(severity: .error, title: "Sayaç eksik", detail: "Projede doğalgaz sayacı bulunmuyor."))
        } else if meters.count > 1 {
            issues.append(.init(severity: .warning, title: "Birden fazla sayaç", detail: "Bu proje tek sayaç ağı varsayımıyla hesaplanıyor; sayaç ayrımları elle doğrulanmalı."))
        }

        let loadDevices = analysis.devices.filter { $0.type == .boiler || $0.type == .stove }
        if loadDevices.isEmpty {
            issues.append(.init(severity: .error, title: "Gaz cihazı eksik", detail: "Kombi veya ocak eklenmeli."))
        }
        if engineering.unknownCapacityCount > 0 {
            issues.append(.init(severity: .warning, title: "Cihaz gücü eksik", detail: "\(engineering.unknownCapacityCount) gaz cihazında kW değeri yok; debi ve hidrolik hesap tamamlanamaz."))
        }
        let unverifiedModels = loadDevices.filter { ($0.brand != nil || $0.model != nil) && $0.modelVerifiedByUser != true }
        if !unverifiedModels.isEmpty {
            issues.append(.init(severity: .warning, title: "AI cihaz modeli doğrulanmadı", detail: "\(unverifiedModels.count) cihazın marka/model önerisi kullanıcı veya mühendis tarafından doğrulanmalı."))
        }

        if !analysis.devices.contains(where: { $0.type == .valve }) {
            issues.append(.init(severity: .warning, title: "Vana tespit edilmedi", detail: "Kesme vanaları saha ve proje üzerinden kontrol edilmeli."))
        }
        if !analysis.devices.contains(where: { $0.type == .vent }) {
            issues.append(.init(severity: .warning, title: "Menfez tespit edilmedi", detail: "Havalandırma şartları cihaz tipi ve yürürlükteki teknik esaslara göre yetkili mühendis tarafından kontrol edilmeli."))
        }

        if analysis.pipes.isEmpty {
            issues.append(.init(severity: .error, title: "Boru hattı yok", detail: "Sayaç ile cihazlar arasındaki boru güzergâhı çizilmeli."))
        }
        if analysis.pipes.contains(where: { $0.lengthMeters <= 0 }) {
            issues.append(.init(severity: .error, title: "Geçersiz metraj", detail: "Sıfır veya negatif uzunluklu boru bölümü var. Gerçek ölçüyle yeniden hesaplayın."))
        }
        if engineering.unknownDiameterCount > 0 {
            issues.append(.init(severity: .warning, title: "Boru çapı doğrulanmadı", detail: "\(engineering.unknownDiameterCount) boru bölümünde çap bilinmiyor."))
        }

        if analysis.pipes.contains(where: { !pointIsValid($0.start) || !pointIsValid($0.end) }) ||
            analysis.devices.contains(where: { !pointIsValid($0.position) }) {
            issues.append(.init(severity: .error, title: "Çizim sınırı hatası", detail: "Bir veya daha fazla öğe 0…1 proje koordinat alanının dışında."))
        }

        if hydraulic.hasCycle {
            issues.append(.init(severity: .warning, title: "Boru ağında döngü", detail: "Otomatik kritik hat hesabı durduruldu. Güzergâhı veya bağlantıları kontrol edin."))
        }
        if hydraulic.disconnectedPipeCount > 0 {
            issues.append(.init(severity: .error, title: "Kopuk boru ağı", detail: "\(hydraulic.disconnectedPipeCount) boru bölümü sayaçtan erişilebilir değil."))
        }
        if hydraulic.unattachedDeviceCount > 0 {
            issues.append(.init(severity: .error, title: "Bağlı olmayan cihaz", detail: "\(hydraulic.unattachedDeviceCount) gaz cihazı boru ağının ucuna/bağlantı noktasına yakın değil."))
        }

        if let limit = settings.maxPressureDropMbar,
           let drop = hydraulic.criticalPressureDropMbar,
           drop > limit {
            issues.append(.init(
                severity: .warning,
                title: "Basınç kaybı profil limitini aşıyor",
                detail: String(format: "Ön hesap %.3f mbar, proje profilindeki limit %.3f mbar. Boru çapı ve kritik hat hesabını yetkili mühendis doğrulamalı.", drop, limit)
            ))
        }
        if let limit = settings.maxVelocityMS,
           let velocity = hydraulic.maximumVelocityMS,
           velocity > limit {
            issues.append(.init(
                severity: .warning,
                title: "Gaz hızı profil limitini aşıyor",
                detail: String(format: "Ön hesap %.2f m/s, proje profilindeki limit %.2f m/s.", velocity, limit)
            ))
        }

        if !settings.isRuleProfileConfigured {
            issues.append(.init(severity: .warning, title: "Şartname profili seçilmedi", detail: "Dağıtım şirketi/doküman revizyonu proje mühendislik ayarlarında belirtilmeli."))
        } else if !settings.verifiedByEngineer {
            issues.append(.init(severity: .warning, title: "Şartname profili doğrulanmadı", detail: "Seçilen profil ve limitler yetkili mühendis tarafından doğrulanmış olarak işaretlenmedi."))
        }
        if let profile = project.ruleProfile, profile.sourceDocumentHashSHA256 == nil {
            issues.append(.init(severity: .warning, title: "Kural kaynağı hash'i yok", detail: "Kullanılan resmî şartname dosyasının SHA-256 değeri kaydedilerek revizyon kaynağı sabitlenmeli."))
        }

        if analysis.confidence < 0.75 {
            issues.append(.init(severity: .warning, title: "Düşük AI güveni", detail: "Tüm cihazlar, boru hattı ve ölçüler elle kontrol edilmeli."))
        }
        if analysis.rooms.isEmpty {
            issues.append(.init(severity: .warning, title: "Oda geometrisi yok", detail: "Plan paftasında oda sınırları doğrulanmalı veya ölçü taraması yapılmalı."))
        }

        if issues.isEmpty {
            issues.append(.init(severity: .info, title: "Ön kontroller tamam", detail: "Bu sonuç resmî uygunluk/onay yerine geçmez."))
        }
        return issues
    }

    private static func pointIsValid(_ p: Point2D) -> Bool {
        p.x.isFinite && p.y.isFinite && (0...1).contains(p.x) && (0...1).contains(p.y)
    }
}

struct ValidationSummary {
    let issues: [ValidationIssue]
    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }
}
