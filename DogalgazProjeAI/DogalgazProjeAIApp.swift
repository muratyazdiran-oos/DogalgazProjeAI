import SwiftUI

@main
struct DogalgazProjeAIApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(store)
        }
    }
}
