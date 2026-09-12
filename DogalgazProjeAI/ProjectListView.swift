import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView(
                        "Henüz proje yok",
                        systemImage: "ruler",
                        description: Text("İlk doğalgaz projenizi oluşturun veya JSON proje yedeğini içe aktarın.")
                    )
                } else {
                    List {
                        ForEach(store.projects) { project in
                            NavigationLink(value: project.id) {
                                ProjectRow(project: project)
                            }
                        }
                        .onDelete(perform: store.delete)
                    }
                }
            }
            .navigationTitle("Doğalgaz Projeleri")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Label("AI Ayarları", systemImage: "gearshape") }
                    Button { showingImporter = true } label: { Label("İçe Aktar", systemImage: "square.and.arrow.down") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewProject = true } label: { Label("Yeni Proje", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingNewProject) { NewProjectView() }
            .sheet(isPresented: $showingSettings) { APISettingsView() }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    try store.importProject(from: url)
                } catch {
                    importError = error.localizedDescription
                }
            }
            .alert("Yerel veri uyarısı", isPresented: Binding(
                get: { store.persistenceWarning != nil },
                set: { if !$0 { store.clearPersistenceWarning() } }
            )) {
                Button("Tamam", role: .cancel) { store.clearPersistenceWarning() }
            } message: {
                Text(store.persistenceWarning ?? "Bilinmeyen hata")
            }
            .alert("İçe aktarma başarısız", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text(importError ?? "Bilinmeyen hata")
            }
            .navigationDestination(for: UUID.self) { id in
                if let project = store.projects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: project)
                }
            }
        }
    }
}

private struct ProjectRow: View {
    let project: GasProject

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(project.name).font(.headline)
                Spacer()
                Image(systemName: project.analysis == nil ? "video.badge.plus" : "checkmark.seal.fill")
                    .foregroundColor(project.analysis == nil ? Color.secondary : Color.green)
            }
            if !project.customerName.isEmpty { Text(project.customerName).font(.subheadline) }
            if !project.address.isEmpty {
                Text(project.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let updatedAt = project.updatedAt {
                Text("Güncellendi: \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
