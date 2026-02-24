import SwiftUI
import LinnetAudio

struct EqualizerView: View {
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        VStack(spacing: 12) {
            // Header: Enable toggle + Preset picker
            HStack {
                Toggle("EQ", isOn: Binding(
                    get: { player.eqEnabled },
                    set: { player.setEQEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()

                Spacer()

                Picker("Preset", selection: Binding(
                    get: { player.eqPreset },
                    set: { player.setEQPreset($0) }
                )) {
                    ForEach(Equalizer.Preset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(!player.eqEnabled)
            }
            .frame(height: 24)

            Divider()

            // Band sliders
            if player.eqBands.isEmpty {
                Spacer()
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<player.eqBands.count, id: \.self) { index in
                        BandSlider(
                            band: player.eqBands[index],
                            isEnabled: player.eqEnabled,
                            onChanged: { gain in
                                player.setEQGain(gain, forBandAt: index)
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380, height: 280)
    }
}

// MARK: - Band Slider

private struct BandSlider: View {
    let band: Equalizer.Band
    let isEnabled: Bool
    let onChanged: (Float) -> Void

    var body: some View {
        VStack(spacing: 4) {
            // dB value
            Text(gainText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(height: 14)

            // Vertical slider
            GeometryReader { geo in
                ZStack {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                        .frame(width: 4)

                    // Zero line
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 12, height: 1)
                        .offset(y: 0)

                    // Thumb
                    Circle()
                        .fill(isEnabled ? Color.accentColor : Color.secondary)
                        .frame(width: 12, height: 12)
                        .offset(y: thumbOffset(in: geo.size.height))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard isEnabled else { return }
                                    let gain = gainFromDrag(y: value.location.y, height: geo.size.height)
                                    onChanged(gain)
                                }
                        )
                }
                .frame(maxWidth: .infinity)
            }

            // Frequency label
            Text(band.label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(height: 14)
        }
    }

    private var gainText: String {
        let g = band.gain
        if g == 0 { return "0" }
        return String(format: "%+.0f", g)
    }

    private func thumbOffset(in height: CGFloat) -> CGFloat {
        // Map gain (-12...+12) to offset. +12 is top (negative offset), -12 is bottom.
        let usableHeight = height - 12 // account for thumb size
        let normalized = CGFloat(band.gain - Equalizer.minGain) / CGFloat(Equalizer.maxGain - Equalizer.minGain)
        // normalized: 0 = minGain (bottom), 1 = maxGain (top)
        return (usableHeight / 2) - (normalized * usableHeight)
    }

    private func gainFromDrag(y: CGFloat, height: CGFloat) -> Float {
        let usableHeight = height - 12
        let clamped = max(6, min(y, height - 6))
        let normalized = 1.0 - ((clamped - 6) / usableHeight)
        let gain = Equalizer.minGain + Float(normalized) * (Equalizer.maxGain - Equalizer.minGain)
        return round(gain) // snap to integer dB
    }
}
