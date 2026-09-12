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
        let calibrationReady = project.calibration?.calibratedAt != nil

        return [
            .init(title: "Demo modu kapalı", detail: APIConfig.useMockAI ? "Gerçek AI analizi için demo modunu kapat." : "Gerçek backend kullanılacak.", ok: !APIConfig.useMockAI),
            .init(title: "HTTPS backend", detail: backendHTTPS ? (APIConfig.baseURL?.host ?? "Yapılandırıldı") : "Üretimde HTTPS backend adresi gerekli.", ok: backendHTTPS),
            .init(title: "AI analizi mevcut", detail: analyzed ? "Proje analiz verisi mevcut." : "Önce video analizi veya manuel proje oluştur.", ok: analyzed),
            .init(title: "Gerçek ölçü doğrulandı", detail: hasRealScale ? "LiDAR veya manuel saha ölçüsü mevcut." : "AI tahminini gerçek ölçüyle doğrula.", ok: hasRealScale),
            .init(title: "Mühendislik profili", detail: hasEngineeringProfile ? project.resolvedEngineeringSettings.profileName : "Proje için teknik profil seçilmedi.", ok: hasEngineeringProfile),
            .init(title: "Kural profili doğrulaması", detail: ruleVerified ? "Profil yetkili mühendis tarafından doğrulanmış." : "Kurum/revizyon/kaynak doğrulaması gerekli.", ok: ruleVerified),
            .init(title: "AI öğe kalite kontrolü", detail: qualityReviewed ? "Belirsiz cihaz ve borular incelenmiş." : "AI tespitlerini tek tek gözden geçir.", ok: qualityReviewed),
            .init(title: "AI / LiDAR kalibrasyonu", detail: calibrationReady ? "Mekânsal hizalama kaydedilmiş." : "Katman hizalamasını saha ölçüsüyle doğrula.", ok: calibrationReady),
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
