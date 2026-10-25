//
//  LevelMeterView.swift
//  Resonance
//
//  A horizontal bar showing live microphone loudness.
//  Maps -60 dBFS (quiet) ... 0 dBFS (very loud) to an empty ... full bar.
//

import SwiftUI

struct LevelMeterView: View {
    let db: Float

    private var fraction: CGFloat {
        let clamped = min(max(db, -60), 0)
        return CGFloat((clamped + 60) / 60)
    }

    private var color: Color {
        switch db {
        case ..<(-45): return .gray
        case ..<(-10): return AppTheme.accent
        default: return AppTheme.warning
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.violetSoft)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color)
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 0.08), value: fraction)
            }
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(db)) decibels")
    }
}

#Preview {
    VStack(spacing: 12) {
        LevelMeterView(db: -70)
        LevelMeterView(db: -30)
        LevelMeterView(db: -5)
    }
    .padding()
}
