import SwiftUI

struct ProjectCanvasView: View {
    let analysis: ProjectAnalysis
    var showsDevices = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .secondarySystemBackground)

                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    drawRooms(context: &context, size: size)
                    drawPipes(context: &context, size: size)
                    drawDimensions(context: &context, size: size)
                }

                if showsDevices {
                    ForEach(analysis.devices) { device in
                        deviceView(device, in: geometry.size)
                    }
                }
            }
        }
    }

    private func scaled(_ point: Point2D, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        stride(from: 0.0, through: size.width, by: 24).forEach { x in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        stride(from: 0.0, through: size.height, by: 24).forEach { y in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
    }

    private func drawRooms(context: inout GraphicsContext, size: CGSize) {
        for room in analysis.rooms where room.polygon.count >= 3 {
            var path = Path()
            path.move(to: scaled(room.polygon[0], in: size))
            for point in room.polygon.dropFirst() {
                path.addLine(to: scaled(point, in: size))
            }
            path.closeSubpath()
            context.stroke(path, with: .color(.primary.opacity(0.75)), lineWidth: 2)

            if let first = room.polygon.first {
                let p = scaled(first, in: size)
                context.draw(Text(room.name).font(.caption.bold()), at: CGPoint(x: p.x + 34, y: p.y + 14))
            }
        }
    }

    private func drawPipes(context: inout GraphicsContext, size: CGSize) {
        for pipe in analysis.pipes {
            var path = Path()
            let start = scaled(pipe.start, in: size)
            let end = scaled(pipe.end, in: size)
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            context.draw(
                Text("Ø\(pipe.diameterMM) • \(pipe.lengthMeters, specifier: "%.1f") m")
                    .font(.caption2.bold()),
                at: CGPoint(x: midpoint.x, y: midpoint.y - 11)
            )
        }
    }

    private func drawDimensions(context: inout GraphicsContext, size: CGSize) {
        for dimension in analysis.dimensions {
            let start = scaled(dimension.start, in: size)
            let end = scaled(dimension.end, in: size)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(.blue.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            context.draw(
                Text("\(dimension.meters, specifier: "%.2f") m").font(.caption2),
                at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 9)
            )
        }
    }

    @ViewBuilder
    private func deviceView(_ device: GasDevice, in size: CGSize) -> some View {
        let point = scaled(device.position, in: size)
        VStack(spacing: 2) {
            Image(systemName: device.type.symbol)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(.background, in: Circle())
                .shadow(radius: 2)
            Text(device.label)
                .font(.caption2.bold())
                .padding(.horizontal, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .position(point)
    }
}
