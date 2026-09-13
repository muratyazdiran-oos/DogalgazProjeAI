import SwiftUI

struct ProductionReadinessView: View {
    let project: GasProject

    private var rows: [ReadinessRow] {
        let issues = ProjectValidator.validate(project)
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        let backendHTTPS = APIConfig.baseURL?.scheme?.lowercased() == "https"
        let analyzed = project.resolvedAnalysis != nil
        let hasRealScale = project.roomScan != nil
        let hasEngineeringProfile = project.engineeringSettings != nil
        let ruleVerified = project.ruleProfile?.engineerVerified == true
        let qualityReviewed = project.resolvedAnalysis.map { project.reviewState?.isComplete(for: $0) == true } ?? false
        let approvalReady = project.approvalWorkflow?.status == .engineerReviewed || project.approvalWorkflow?.status == .approved
        let legacyCalibrationReady = project.calibration?.calibratedAt != nil
        let arCalibrationReady = project.arRoomAlignment?.calibrationIsAcceptable == true
        let calibrationReady = arCalibrationReady || legacyCalibrationReady
        let evidenceReady = project.approvalEvidenceBlockingReasons.isEmpty
        let cloudRefs = project.cloudArtifacts ?? []
        let cloudHealthy = cloudRefs.isEmpty || cloudRefs.allSatisfy(\.recentlyVerified)
        let hydraulic = project.resolvedAnalysis.map { HydraulicCalculator.calculate($0, settings: project.resolvedEngineeringSettings) }
        let hydraulicReady = hydraulic?.available == true && hydraulic?.hasCycle == false && hydraulic?.disconnectedPipeCount == 0 && hydraulic?.unattachedDeviceCount == 0
        let pipes = project.resolvedAnalysis?.pipes ?? []
        let elevatedPipeCount = pipes.filter { $0.startElevationM != nil && $0.endElevationM != nil }.count
        let elevationCoverage = pipes.isEmpty ? 0 : Double(elevatedPipeCount) / Double(pipes.count)
        let threeDReady = pipes.isEmpty ? false : elevationCoverage >= 0.95

        return [
            .init(title: "Demo modu kapalı", detail: APIConfig.useMockAI ? "Gerçek AI analizi için demo modunu kapat." : "Gerçek backend kullanılacak.", ok: !APIConfig.useMockAI),
            .init(title: "HTTPS backend", detail: backendHTTPS ? (APIConfig.baseURL?.host ?? "Yapılandırıldı") : "Üretimde HTTPS backend adresi gerekli.", ok: backendHTTPS),
            .init(title: "AI analizi mevcut", detail: analyzed ? "Proje analiz verisi mevcut." : "Önce video analizi veya manuel proje oluştur.", ok: analyzed),
            .init(title: "Gerçek ölçü doğrulandı", detail: hasRealScale ? "LiDAR veya manuel saha ölçüsü mevcut." : "AI tahminini gerçek ölçüyle doğrula.", ok: hasRealScale),
            .init(title: "Mühendislik profili", detail: hasEngineeringProfile ? project.resolvedEngineeringSettings.profileName : "Proje için teknik profil seçilmedi.", ok: hasEngineeringProfile),
            .init(title: "Kural profili doğrulaması", detail: ruleVerified ? "Profil yetkili mühendis tarafından doğrulanmış." : "Kurum/revizyon/kaynak doğrulaması gerekli.", ok: ruleVerified),
            .init(title: "AI öğe kalite kontrolü", detail: qualityReviewed ? "Belirsiz cihaz ve borular incelenmiş." : "AI tespitlerini tek tek gözden geçir.", ok: qualityReviewed),
            .init(title: "AR / RoomPlan kalibrasyonu", detail: arCalibrationReady ? String(format: "Çok noktalı hizalama uygun • RMS %.1f cm", (project.arRoomAlignment?.calibrationRMSErrorM ?? 0) * 100) : (calibrationReady ? "Eski kalibrasyon mevcut; çok noktalı AR↔RoomPlan önerilir." : "Çok noktalı saha hizalaması gerekli."), ok: calibrationReady),
            .init(title: "3B boru kot kapsamı", detail: pipes.isEmpty ? "Boru hattı yok." : "%\(Int((elevationCoverage * 100).rounded())) segmentte başlangıç/bitiş kotu mevcut.", ok: threeDReady),
            .init(title: "Hidrolik ağ bütünlüğü", detail: hydraulicReady ? String(format: "Kritik Δp: %.3f mbar", hydraulic?.criticalPressureDropMbar ?? 0) : (hydraulic?.message ?? "Hidrolik hesap kullanılamıyor."), ok: hydraulicReady),
            .init(title: "Saha kanıt bütünlüğü", detail: evidenceReady ? "Yerel/bulut kanıtlar onay için erişilebilir." : project.approvalEvidenceBlockingReasons.prefix(2).joined(separator: " • "), ok: evidenceReady),
            .init(title: "Bulut artifact sağlığı", detail: cloudHealthy ? (cloudRefs.isEmpty ? "Bulut artifact zorunlu değil / kayıt yok." : "\(cloudRefs.count) artifact son 24 saatte doğrulanmış.") : "Bulut kanıt sağlık kontrolünü çalıştır.", ok: cloudHealthy),
            .init(title: "Mühendis onay akışı", detail: approvalReady ? (project.approvalWorkflow?.status.title ?? "Hazır") : "En az mühendis incelemesi aşamasına getir.", ok: approvalReady),
            .init(title: "Doğrulama hataları", detail: errors == 0 ? "Bloklayıcı hata yok." : "\(errors) bloklayıcı hata var.", ok: errors == 0),
            .init(title: "Doğrulama uyarıları", detail: warnings == 0 ? "Açık uyarı yok." : "\(warnings) uyarı mühendis tarafından incelenmeli.", ok: warnings == 0)
        ]
    }

    private var readyCount: Int { rows.filter(\.ok).count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(readyCount)/\(rows.count)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("kontrol geçti")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(readyCount), total: Double(rows.count))
                    Text("Bu ekran teknik yayın kontrolüdür; resmî proje onayı yerine geçmez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Kontroller") {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(row.ok ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title).font(.headline)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            Section("Yayın öncesi cihaz testi") {
                Label("Gerçek iPhone'da video seçme ve yükleme", systemImage: "iphone")
                Label("LiDAR destekli cihazda RoomPlan saha ölçümü", systemImage: "viewfinder")
                Label("Uçak modu / zayıf ağ / timeout hata akışı", systemImage: "wifi.exclamationmark")
                Label("PDF, DXF ve JSON dışa aktarma + yeniden içe aktarma", systemImage: "doc.badge.gearshape")
                Label("Hesap/ekip senkronizasyonunda yetki rolleri", systemImage: "person.2.badge.gearshape")
                Label("Yetkili mühendisle örnek proje karşılaştırması", systemImage: "person.badge.shield.checkmark")
            }
        }
        .navigationTitle("Üretime Hazırlık")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReadinessRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let ok: Bool
}
