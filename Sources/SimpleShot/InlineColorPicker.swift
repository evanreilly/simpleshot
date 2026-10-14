import AppKit
import SwiftUI

extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((number >> 16) & 255) / 255,
                  green: CGFloat((number >> 8) & 255) / 255, blue: CGFloat(number & 255) / 255, alpha: 1)
    }
    var hex: String {
        let rgb = usingColorSpace(.sRGB) ?? .red
        return String(format: "%02X%02X%02X", Int(round(rgb.redComponent * 255)),
                      Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
    }
}

struct InlineColorPicker: View {
    let title: String
    @Binding var color: NSColor
    var compact = false
    @State private var showing = false
    @State private var hex = ""
    @State private var hue: CGFloat = 0
    @State private var saturation: CGFloat = 1
    @State private var brightness: CGFloat = 1
    private let palette = ["FF3B30", "FF9500", "FFCC00", "34C759", "00C7BE", "007AFF",
                           "5856D6", "AF52DE", "FF2D55", "FFFFFF", "808080", "000000"]
    var body: some View {
        Button { syncColor(); showing.toggle() } label: {
            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: color)).overlay(Circle().stroke(.gray, lineWidth: 1)).frame(width: 16, height: 16)
                if !compact { Text(title).font(.caption) }
            }
        }
        .buttonStyle(MarkupControlStyle())
        .help(title).accessibilityLabel(title)
        .popover(isPresented: $showing) {
            VStack(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(palette, id: \.self) { value in
                        Button { color = NSColor(hex: value)!; syncColor() } label: {
                            Circle().fill(Color(nsColor: NSColor(hex: value)!))
                                .overlay(Circle().stroke(.gray, lineWidth: 1)).frame(width: 24, height: 24)
                        }.buttonStyle(.plain).accessibilityLabel("#" + value)
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Color(hue: hue, saturation: 1, brightness: 1)
                        LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                        Circle().stroke(.white, lineWidth: 2).shadow(color: .black, radius: 1)
                            .frame(width: 10, height: 10)
                            .offset(x: saturation * geometry.size.width - 5,
                                    y: (1-brightness) * geometry.size.height - 5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        saturation = min(max(value.location.x / geometry.size.width, 0), 1)
                        brightness = 1 - min(max(value.location.y / geometry.size.height, 0), 1)
                        applyColor()
                    })
                    .accessibilityLabel("Color saturation and brightness")
                }.frame(height: 150)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        LinearGradient(colors: (0...6).map { Color(hue: Double($0)/6, saturation: 1, brightness: 1) },
                                       startPoint: .leading, endPoint: .trailing)
                        RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 2)
                            .frame(width: 6).offset(x: hue * (geometry.size.width - 6))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        hue = min(max(value.location.x / geometry.size.width, 0), 1)
                        applyColor()
                    })
                    .accessibilityLabel("Hue")
                    .accessibilityAdjustableAction { direction in
                        hue = min(max(hue + (direction == .increment ? 0.02 : -0.02), 0), 1)
                        applyColor()
                    }
                }.frame(height: 18)
                HStack {
                    Text("#")
                    TextField("Hex color", text: $hex).textFieldStyle(.roundedBorder)
                        .onChange(of: hex) { _, value in
                            if let parsed = NSColor(hex: value), parsed.hex != color.hex { color = parsed; syncColor() }
                        }
                }
            }.frame(width: 208).padding(12)
        }
    }
    private func syncColor() {
        let rgb = color.usingColorSpace(.sRGB) ?? .red
        hue = rgb.hueComponent; saturation = rgb.saturationComponent; brightness = rgb.brightnessComponent
        hex = color.hex
    }
    private func applyColor() {
        color = NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        hex = color.hex
    }
}

struct MarkupControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 18, minHeight: 30)
            .padding(.horizontal, 6)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.06),
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
