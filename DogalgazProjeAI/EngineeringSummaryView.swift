import SwiftUI

struct EngineeringSummaryView: View {
    let project: GasProject

    private var settings: EngineeringSettings { project.resolvedEngineeringSettings }
    private var analysis: ProjectAnalysis? { project.resolvedAnalysis }

    var body: some View {
        if let analysis {
            let summary = EngineeringCalculator.summarize(analysis, settings: settings)
            let hydraulic = HydraulicCalculator.calculate(analysis, settings: settings)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Hesap Özeti").font(.headline)
                    Spacer()
                    Text(settings.verifiedByEngineer ? "Profil doğrulandı" : "Ön hesap")
                        .font(.caption.bold())
                        .foregroundStyle(settings.verifiedByEngineer ? .green : .orange)
                }

                LabeledContent("Toplam cihaz gücü", value: String(format: "%.1f kW", summary.totalLoadKW))
                LabeledContent("Yaklaşık gaz debisi", value: String(format: "%.2f m³/h", summary.estimatedGasFlowM3h))
                LabeledContent("Toplam boru", value: String(format: "%.2f m", summary.totalPipeMeters))
                LabeledContent("En uzun tek parça", value: String(format: "%.2f m", summary.longestSingleSegmentMeters))
                LabeledContent("Gaz cihazı", value: "\(summary.gasDeviceCount)")
                LabeledContent("Kural profili", value: settings.profileName)

                Divider()
                Text("Hidrolik Ön Kontrol").font(.subheadline.bold())
                Label(hydraulic.message, systemImage: hydraulic.available ? "waveform.path.ecg" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(hydraulic.available ? .primary : .orange)

                if let drop = hydraulic.criticalPressureDropMbar {
                    LabeledContent("Kritik hat Δp", value: String(format: "%.3f mbar", drop))
                }
                if let outlet = hydraulic.estimatedMinimumOutletPressureMbar {
                    LabeledContent("Tahmini min. çıkış", value: String(format: "%.2f mbar", outlet))
                }
                if let velocity = hydraulic.maximumVelocityMS {
                    LabeledContent("Maks. hesaplanan hız", value: String(format: "%.2f m/s", velocity))
                }

                if summary.unknownCapacityCount > 0 {
                    warning("\(summary.unknownCapacityCount) gaz cihazının gücü doğrulanmadı.")
                }
                if summary.unknownDiameterCount > 0 {
                    warning("\(summary.unknownDiameterCount) boru bölümünde çap doğrulanmadı.")
                }
                if hydraulic.disconnectedPipeCount > 0 {
                    warning("\(hydraulic.disconnectedPipeCount) boru bölümü sayaç ağına bağlı değil.")
                }
                if hydraulic.unattachedDeviceCount > 0 {
                    warning("\(hydraulic.unattachedDeviceCount) gaz cihazı boru ağına bağlı görünmüyor.")
                }

                if !hydraulic.segmentResults.isEmpty {
                    DisclosureGroup("Segment hesapları") {
                        ForEach(hydraulic.segmentResults) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Boru \(item.pipeID.uuidString.prefix(6))")
                                    .font(.caption.bold())
                                Text(String(format: "Debi %.2f m³/h • Yük %.1f kW", item.flowM3h, item.downstreamLoadKW))
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let velocity = item.velocityMS, let drop = item.pressureDropMbar {
                                    Text(String(format: "Hız %.2f m/s • Δp %.3f mbar", velocity, drop))
                                        .font(.caption2).foregroundStyle(.secondary)
                                } else {
                                    Text("Çap/metraj eksik; hidrolik sonuç üretilemedi.")
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                        }
                    }
                    .font(.subheadline)
                }

                Text("Darcy–Weisbach tabanlı bu değerler ön kontroldür. Boru iç çapı, bağlantı elemanları, cihaz giriş şartları ve yürürlükteki dağıtım şirketi teknik esasları yetkili mühendis tarafından doğrulanmalıdır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
