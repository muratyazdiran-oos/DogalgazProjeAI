import SwiftUI

struct MaterialSummaryView: View {
    let summary: MaterialSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Malzeme Özeti")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                row("Toplam boru", "\(summary.totalPipeMeters, specifier: "%.1f") m")
                row("Vana", "\(summary.valves) adet")
                row("Dirsek", "\(summary.elbows) adet")
                row("Tee", "\(summary.tees) adet")
                row("Menfez", "\(summary.vents) adet")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
    }
}
