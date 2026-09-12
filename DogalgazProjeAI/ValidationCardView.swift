import SwiftUI

struct ValidationCardView: View {
    let project: GasProject
    private var summary: ValidationSummary { .init(issues: ProjectValidator.validate(project)) }

    var body: some View {
        DisclosureGroup {
            ForEach(summary.issues) { issue in
                HStack(alignment: .top) {
                    Image(systemName: icon(issue.severity)).foregroundStyle(color(issue.severity))
                    VStack(alignment: .leading) {
                        Text(issue.title).font(.subheadline.bold())
                        Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
            }
        } label: {
            Label(summary.errorCount == 0 ? "Ön Kontrol: \(summary.warningCount) uyarı" : "Ön Kontrol: \(summary.errorCount) hata", systemImage: summary.errorCount == 0 ? "checkmark.shield" : "exclamationmark.shield")
                .font(.headline)
        }
        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func icon(_ severity: ValidationSeverity) -> String { severity == .error ? "xmark.circle.fill" : severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill" }
    private func color(_ severity: ValidationSeverity) -> Color { severity == .error ? .red : severity == .warning ? .orange : .blue }
}
