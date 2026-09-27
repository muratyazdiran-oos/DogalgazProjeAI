import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var showingNewProject = false
    @State private var showingSettings = false
    @State private var showingImporter = false
    @State private var importError: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                GasUI.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        actionGrid
                        projectsSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showingNewProject) { NewProjectView() }
            .sheet(isPresented: $showingSettings) { APISettingsView() }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    try store.importProject(from: url)
                } catch { importError = error.localizedDescription }
            }
            .alert("Yerel veri uyarısı", isPresented: Binding(
                get: { store.persistenceWarning != nil },
                set: { if !$0 { store.clearPersistenceWarning() } }
            )) {
                Button("Tamam", role: .cancel) { store.clearPersistenceWarning() }
            } message: { Text(store.persistenceWarning ?? "Bilinmeyen hata") }
            .alert("İçe aktarma başarısız", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("Tamam", role: .cancel) { }
            } message: { Text(importError ?? "Bilinmeyen hata") }
            .navigationDestination(for: UUID.self) { id in
                if let project = store.projects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: project)
                }
            }
        }
        .tint(GasUI.blue)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(GasUI.blue.opacity(0.16))
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(GasUI.blue)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("DoğalgazProjeAI")
                    .font(.title2.bold())
                Text("Yapay zeka ile profesyonel doğalgaz projeleri")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(GasUI.card, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var actionGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            DashboardAction(title: "Yeni Proje", subtitle: "Plan oluşturun", icon: "plus", accent: GasUI.blue, prominent: true) {
                showingNewProject = true
            }
            DashboardAction(title: "LiDAR ile Tara", subtitle: "Odayı ölçün", icon: "viewfinder", accent: GasUI.green, prominent: true) {
                showingNewProject = true
            }
            DashboardAction(title: "Video ile Tara", subtitle: "Videodan analiz", icon: "video.fill", accent: GasUI.blue, prominent: false) {
                showingNewProject = true
            }
            DashboardAction(title: "Projeyi İçe Aktar", subtitle: "JSON yedeği açın", icon: "square.and.arrow.down.fill", accent: .purple, prominent: false) {
                showingImporter = true
            }
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Son Projeler").font(.title3.bold())
                Spacer()
                Text("\(store.projects.count) proje")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GasUI.blue)
            }

            if store.projects.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "ruler.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(GasUI.blue)
                    Text("Henüz proje yok").font(.headline)
                    Text("İlk projenizi oluşturun; ardından LiDAR, video ve mühendislik araçlarını kullanabilirsiniz.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("İlk Projeyi Oluştur") { showingNewProject = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(GasUI.card, in: RoundedRectangle(cornerRadius: 22))
            } else {
                ForEach(store.projects.prefix(8)) { project in
                    NavigationLink(value: project.id) {
                        ProjectDashboardCard(project: project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            if let index = store.projects.firstIndex(where: { $0.id == project.id }) {
                                store.delete(at: IndexSet(integer: index))
                            }
                        } label: { Label("Projeyi Sil", systemImage: "trash") }
                    }
                }
            }
        }
    }
}

private struct DashboardAction: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(accent.opacity(prominent ? 0.22 : 0.13))
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 50, height: 50)
                Spacer(minLength: 4)
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: prominent ? 142 : 122, alignment: .leading)
            .padding(16)
            .background(
                LinearGradient(
                    colors: prominent ? [accent.opacity(0.20), GasUI.card] : [GasUI.card, GasUI.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(prominent ? accent.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectDashboardCard: View {
    let project: GasProject

    private var statusText: String {
        if project.analysis != nil { return "Analiz tamamlandı" }
        if project.roomScan != nil { return "Ölçüm alındı" }
        return "Analiz bekliyor"
    }

    private var statusColor: Color {
        project.analysis != nil ? GasUI.green : (project.roomScan != nil ? .orange : .secondary)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(GasUI.blue.opacity(0.12))
                Image(systemName: project.analysis == nil ? "building.2.crop.circle" : "checkmark.seal.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(project.analysis == nil ? GasUI.blue : GasUI.green)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(project.name).font(.headline).lineLimit(1)
                if !project.address.isEmpty {
                    Label(project.address, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption2.weight(.semibold)).foregroundStyle(statusColor)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(GasUI.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.05)) }
    }
}

enum GasUI {
    static let background = Color(red: 0.025, green: 0.055, blue: 0.08)
    static let card = Color(red: 0.065, green: 0.105, blue: 0.145)
    static let blue = Color(red: 0.10, green: 0.55, blue: 1.0)
    static let green = Color(red: 0.05, green: 0.78, blue: 0.48)
}
