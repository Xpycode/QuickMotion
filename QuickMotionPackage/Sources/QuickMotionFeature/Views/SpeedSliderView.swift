import SwiftUI

/// Speed control slider with logarithmic scale and live feedback
public struct SpeedSliderView: View {
    @Binding var sliderValue: Double
    let speedMultiplier: Double
    let inputDuration: String?
    let outputDuration: String?

    public init(
        sliderValue: Binding<Double>,
        speedMultiplier: Double,
        inputDuration: String? = nil,
        outputDuration: String? = nil
    ) {
        self._sliderValue = sliderValue
        self.speedMultiplier = speedMultiplier
        self.inputDuration = inputDuration
        self.outputDuration = outputDuration
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Speed slider row
            HStack(spacing: 16) {
                Text("Speed:")
                    .foregroundStyle(.secondary)

                Slider(value: $sliderValue, in: 0...1)
                    .frame(minWidth: 200)

                Text(formattedSpeed)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 50, alignment: .trailing)
            }

            // Duration feedback row
            if let input = inputDuration, let output = outputDuration {
                HStack {
                    Spacer()

                    Text(input)
                        .foregroundStyle(.secondary)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)

                    Text(output)
                        .fontWeight(.medium)

                    Spacer()
                }
                .font(.callout)
            }
        }
    }

    private var formattedSpeed: String {
        String(format: "%.0fx", speedMultiplier)
    }
}

// MARK: - Preset Speed Buttons (optional enhancement)

public struct SpeedPresetsView: View {
    @Binding var sliderValue: Double
    let presets: [(label: String, speed: Double)] = [
        ("2x", 2),
        ("4x", 4),
        ("8x", 8),
        ("16x", 16),
        ("32x", 32),
        ("64x", 64)
    ]

    public init(sliderValue: Binding<Double>) {
        self._sliderValue = sliderValue
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.speed) { preset in
                Button(preset.label) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sliderValue = sliderFromSpeed(preset.speed)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func sliderFromSpeed(_ speed: Double) -> Double {
        let value = log(speed / 2.0) / log(50.0)
        return min(1, max(0, value))
    }
}

#Preview("Speed Slider") {
    struct PreviewWrapper: View {
        @State var value = 0.5

        var speed: Double {
            2.0 * pow(50.0, value)
        }

        var body: some View {
            VStack(spacing: 20) {
                SpeedSliderView(
                    sliderValue: $value,
                    speedMultiplier: speed,
                    inputDuration: "5:34",
                    outputDuration: "28s"
                )

                SpeedPresetsView(sliderValue: $value)
            }
            .padding()
            .frame(width: 400)
        }
    }

    return PreviewWrapper()
}
