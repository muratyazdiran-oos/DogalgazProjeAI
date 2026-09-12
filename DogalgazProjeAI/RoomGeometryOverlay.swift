import SwiftUI

/// RoomPlan duvarlarını ve kapı/pencere/açıklıkları proje üzerine ayrı teknik katman olarak çizer.
struct RoomGeometryOverlay: View {
    let scan: RoomScanSnapshot

    var body: some View {
        Canvas { context, size in
            for wall in scan.walls {
                let a = scaled(scan.normalizedPoint(x: wall.startX, z: wall.startZ), size)
                let b = scaled(scan.normalizedPoint(x: wall.endX, z: wall.endZ), size)
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(.primary), lineWidth: 5)
            }

            for opening in scan.openings {
                let center = scaled(scan.normalizedPoint(x: opening.centerX, z: opening.centerZ), size)
                let symbol: String
                switch opening.kind {
                case .door: symbol = "D"
                case .window: symbol = "P"
                case .opening: symbol = "A"
                }
                context.draw(
                    Text("\(symbol) \(opening.widthMeters, specifier: "%.2f")m")
                        .font(.caption2.bold()),
                    at: center
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func scaled(_ point: Point2D, _ size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}
