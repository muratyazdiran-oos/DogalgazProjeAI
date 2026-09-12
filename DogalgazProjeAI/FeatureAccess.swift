import Foundation

/// Test dönemi erişim politikası: ödeme, abonelik ve proje limiti yoktur.
enum FeatureAccess {
    static let paymentsEnabled = false
    static let requiresSubscription = false
    static let projectLimit: Int? = nil
    static func canUse(_ feature: AppFeature) -> Bool { true }
}

enum AppFeature: String, CaseIterable {
    case videoAnalysis, roomScan, manualMeasure, projectEditor, validation, pdfExport
}
