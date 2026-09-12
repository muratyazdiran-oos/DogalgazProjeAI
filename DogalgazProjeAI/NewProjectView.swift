import SwiftUI

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProjectStore

    @State private var projectName = ""
    @State private var customerName = ""
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Proje") {
                    TextField("Proje adı", text: $projectName)
                    TextField("Müşteri adı", text: $customerName)
                    TextField("Adres", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Text("Projeyi oluşturduktan sonra tesisat videosunu seçerek AI analizini başlatabilirsiniz.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Yeni Proje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur") {
                        let project = GasProject(
                            name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                            customerName: customerName.trimmingCharacters(in: .whitespacesAndNewlines),
                            address: address.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        store.add(project)
                        dismiss()
                    }
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
