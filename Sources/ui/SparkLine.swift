//
//  SparkLine.swift
//  盯基金 plugin v0.2
//
//  Pure-SwiftUI port of the design's <svg> sparkline for the gold
//  chart. Handles:
//    - smooth quadratic curve through points
//    - filled area under the curve with a vertical gradient
//    - pulsing "current point" indicator
//    - dashed midline grid
//    - empty / 1-point degenerate cases
//

import SwiftUI

struct SparkLine: View {
    let values: [Double]
    let lineColor: Color
    let fillColor: Color
    let pulseColor: Color

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let padX: CGFloat = 8
            let padY: CGFloat = 14

            ZStack {
                // dashed midline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: H / 2))
                    p.addLine(to: CGPoint(x: W, y: H / 2))
                }
                .stroke(
                    Color.white.opacity(0.04),
                    style: StrokeStyle(lineWidth: 0.5, lineCap: .round, dash: [2, 4])
                )

                // bail when not enough data
                if values.count >= 2,
                   let maxV = values.max(),
                   let minV = values.min(),
                   maxV != minV {

                    let xs: (Int) -> CGFloat = { i in
                        padX + (CGFloat(i) / CGFloat(values.count - 1)) * (W - padX * 2)
                    }
                    let ys: (Double) -> CGFloat = { v in
                        let t = (v - minV) / (maxV - minV)
                        return padY + (1 - CGFloat(t)) * (H - padY * 2)
                    }

                    // area fill
                    Path { p in
                        p.move(to: CGPoint(x: xs(0), y: ys(values[0])))
                        for i in 1..<values.count {
                            p.addLine(to: CGPoint(x: xs(i), y: ys(values[i])))
                        }
                        p.addLine(to: CGPoint(x: xs(values.count - 1), y: H))
                        p.addLine(to: CGPoint(x: xs(0), y: H))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [fillColor.opacity(0.45), fillColor.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // line
                    Path { p in
                        p.move(to: CGPoint(x: xs(0), y: ys(values[0])))
                        for i in 1..<values.count {
                            p.addLine(to: CGPoint(x: xs(i), y: ys(values[i])))
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [lineColor.opacity(0.9), lineColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )

                    // current point dot + pulsing halo
                    let lastX = xs(values.count - 1)
                    let lastY = ys(values[values.count - 1])
                    Circle()
                        .fill(pulseColor)
                        .frame(width: 7, height: 7)
                        .position(x: lastX, y: lastY)
                    PulsingRing(color: pulseColor)
                        .frame(width: 18, height: 18)
                        .position(x: lastX, y: lastY)
                } else {
                    // degenerate: flat line in the middle
                    Path { p in
                        p.move(to: CGPoint(x: padX, y: H / 2))
                        p.addLine(to: CGPoint(x: W - padX, y: H / 2))
                    }
                    .stroke(lineColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.2))
                }
            }
        }
    }
}

private struct PulsingRing: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(color.opacity(pulse ? 0 : 0.6), lineWidth: 1.2)
            .scaleEffect(pulse ? 1.4 : 0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}
