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

/// One choice: a strip of sample icons at that preset's spacing, the width it
/// occupies, and whether it is the one in effect.
///
/// All four are drawn together on a shared left edge. That is the whole point —
/// a single strip is not judgeable (docs/en/preset-appearance.md), and the
/// photographs are legible only because they are stacked this way.
struct SpacingSampleRow: View {
    let preset: SpacingPreset
    let isSelected: Bool
    let isCurrent: Bool

    /// Every name is checked to resolve by `SpacingSampleTests`: a symbol that
    /// does not exist draws an empty slot, which reads as a bug in the drawing.
    static let symbols = ["wifi", "battery.75percent", "speaker.wave.2.fill",
                          "moon.fill", "clock", "magnifyingglass"]

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(preset.title).font(.callout.weight(isSelected ? .semibold : .regular))
                    Text("\(Int(SpacingSample.totalWidth(for: preset.value))) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if isCurrent {
                        Text("in effect now")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    }
                }
                strip
            }
        }
        .contentShape(Rectangle())
    }

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.symbols.prefix(SpacingSample.iconCount).enumerated()), id: \.offset) { _, symbol in
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: SpacingSample.slotWidth(for: preset.value), height: 22)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.82)))
    }
}

/// The picker and the sample are the same thing: every preset drawn to the
/// measured widths, on a shared left edge, and choosing one means clicking it.
struct SpacingSampleView: View {
    let current: SpacingSettings
    @Binding var selection: SpacingPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SpacingPreset.allCases) { preset in
                Button {
                    selection = preset
                } label: {
                    SpacingSampleRow(preset: preset,
                                     isSelected: preset == selection,
                                     isCurrent: SpacingSample.value(of: current) == .some(preset.value))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(preset == selection ? [.isSelected] : [])
            }

            if SpacingSample.value(of: current) == nil {
                Text("The spacing in effect was set outside this app, so it is not one of these.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Six sample icons, drawn to the widths measured on this version of macOS.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
