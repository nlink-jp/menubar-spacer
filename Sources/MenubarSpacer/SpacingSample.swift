import SwiftUI

/// The geometry the in-window sample is drawn with.
///
/// These are not chosen numbers. A square status item occupies
/// `iconWidth + value` points, measured on macOS 27.0 with the keys at 4, 8, 24
/// and unset — see docs/en/preset-appearance.md, whose photographs this drawing
/// has to agree with. `SpacingSampleTests` pins every number against that table,
/// so the drawing cannot drift away from the thing it depicts.
enum SpacingSample {
    /// The width of the square status item itself, independent of spacing.
    static let iconWidth: CGFloat = 22
    /// What macOS behaves like when both keys are unset.
    static let defaultValue = 16
    /// Enough repetitions for the difference to add up, as in the photographs.
    static let iconCount = 6

    static func slotWidth(for value: Int?) -> CGFloat {
        iconWidth + CGFloat(value ?? defaultValue)
    }

    static func totalWidth(for value: Int?, count: Int = iconCount) -> CGFloat {
        slotWidth(for: value) * CGFloat(count)
    }

    /// What the live state draws as. A state this app did not produce — one key
    /// set by hand, or a value it cannot interpret — has no single spacing to
    /// draw, and the caller must say so instead of inventing one.
    static func value(of settings: SpacingSettings) -> Int?? {
        if settings == .unset { return Int?.none }          // the macOS default
        if let uniform = settings.uniformValue { return uniform }
        return nil                                          // nothing to draw
    }
}

/// One strip of sample icons at a given spacing.
struct SpacingSampleRow: View {
    let title: String
    let value: Int?

    /// Every name is checked to resolve by `SpacingSampleTests`: a symbol that
    /// does not exist draws an empty slot, which reads as a bug in the drawing.
    static let symbols = ["wifi", "battery.75percent", "speaker.wave.2.fill",
                          "moon.fill", "clock", "magnifyingglass"]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.medium))
                Text("\(Int(SpacingSample.totalWidth(for: value))) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(Array(Self.symbols.prefix(SpacingSample.iconCount).enumerated()), id: \.offset) { _, symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .frame(width: SpacingSample.slotWidth(for: value), height: 22)
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.82)))
        }
    }
}

/// The sample: what the menu bar holds now, and what the selected preset would
/// make of it. Drawn to the measured geometry — it is a scale drawing, not a
/// photograph of this Mac's menu bar, and says so.
struct SpacingSampleView: View {
    let current: SpacingSettings
    let selected: SpacingPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch SpacingSample.value(of: current) {
            case let .some(value):
                SpacingSampleRow(title: "Now", value: value)
            case .none:
                Text("The current spacing was set outside this app, so it cannot be drawn here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if SpacingSample.value(of: current) != .some(selected.value) {
                SpacingSampleRow(title: "After applying \(selected.title)", value: selected.value)
            }

            Text("Six sample icons, drawn to the widths measured on this version of macOS.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
