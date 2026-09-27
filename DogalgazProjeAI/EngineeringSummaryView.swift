import SwiftUI

struct EngineeringSummaryView: View {
    let project: GasProject
    private var settings: EngineeringSettings { project.resolvedEngineeringSettings }
    private var analysis: ProjectAnalysis? { project.resolvedAnalysis }

    var body: some View {
        if let analysis {
            let summary = EngineeringCalculator.summarize(analysis, settings: settings)
            let hydraulic = HydraulicCalculator.calculate(analysis, settings: settings)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Mühendislik Özeti", systemImage: "function")
                        .font(.headline)
                    Spacer()
                    Text(settings.verifiedByEngineer ? "DOĞRULANDI" : "ÖN HESAP")
                        .font(.caption2.bold()).padding(.horizontal, 9).padding(.vertical, 5)
                        .background((settings.verifiedByEngineer ? GasUI.green : Color.orange).opacity(0.16), in: Capsule())
                        .foregroundStyle(settings.verifiedByEngineer ? GasUI.green : .orange)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metric("Toplam Güç", String(format: "%.1f kW", summary.totalLoadKW), "bolt.fill")
                    metric("Gaz Debisi", String(format: "%.2f m³/h", summary.estimatedGasFlowM3h), "wind")
                    metric("Toplam Boru", String(format: "%.2f m", summary.totalPipeMeters), "point.topleft.down.to.point.bottomright.curvepath")
                    metric("Gaz Cihazı", "\(summary.gasDeviceCount)", "flame.fill")
                }
                Divider().overlay(Color.white.opacity(0.08))
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: hydraulic.available ? "waveform.path.ecg" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hydraulic.available ? GasUI.green : .orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Hidrolik Ön Kontrol").font(.subheadline.bold())
                        Text(hydraulic.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let drop = hydraulic.criticalPressureDropMbar { resultRow("Kritik hat Δp", String(format: "%.3f mbar", drop)) }
                if let outlet = hydraulic.estimatedMinimumOutletPressureMbar { resultRow("Tahmini min. çıkış", String(format: "%.2f mbar", outlet)) }
                if let velocity = hydraulic.maximumVelocityMS { resultRow("Maks. hesaplanan hız", String(format: "%.2f m/s", velocity)) }
                if summary.unknownCapacityCount > 0 { warning("\(summary.unknownCapacityCount) cihazın gücü doğrulanmadı.") }
                if summary.unknownDiameterCount > 0 { warning("\(summary.unknownDiameterCount) boru bölümünde çap doğrulanmadı.") }
                if hydraulic.disconnectedPipeCount > 0 { warning("\(hydraulic.disconnectedPipeCount) boru bölümü sayaç ağına bağlı değil.") }
                if hydraulic.unattachedDeviceCount > 0 { warning("\(hydraulic.unattachedDeviceCount) gaz cihazı boru ağına bağlı görünmüyor.") }
                Text("Darcy–Weisbach tabanlı değerler ön kontroldür; saha ve teknik şartname doğrulaması yetkili mühendis tarafından yapılmalıdır.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(18)
            .background(GasUI.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.05)) }
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).foregroundStyle(GasUI.blue)
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
    private func resultRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.semibold) }.font(.subheadline)
    }
    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
    }
}