import SwiftUI
import UIKit

// Low-memory weather wallpaper. Weather is rasterized into ONE static image
// when the weather classification or screen size changes, not every frame.
// The previous SwiftUI version created dozens of blurred shapes at once.
struct SkyView: UIViewRepresentable {
    let weather: WeatherSnapshot

    func makeUIView(context: Context) -> StaticWeatherSky {
        StaticWeatherSky()
    }

    func updateUIView(_ view: StaticWeatherSky, context: Context) {
        view.setWeather(weather)
    }
}

final class StaticWeatherSky: UIView {
    private enum Condition: Int {
        case clear, partlyCloudy, overcast, fog, rain, snow, thunder
    }

    private var weather = WeatherSnapshot()
    private var signature = ""
    private var drawnSignature = ""
    private var drawnSize = CGSize.zero
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(red: 0.61, green: 0.71, blue: 0.81, alpha: 1)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setWeather(_ snapshot: WeatherSnapshot) {
        let next = [
            String(snapshot.weatherCode),
            snapshot.isDay ? "1" : "0",
            String((snapshot.cloudCover ?? -1) / 10),
            String(Int((snapshot.precipitation ?? 0) * 2)),
            String(Int((snapshot.snowfallAmount ?? 0) * 2)),
            String(snapshot.localHour ?? -1)
        ].joined(separator: ":")
        guard next != signature else { return }
        signature = next
        weather = snapshot
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let size = bounds.size
        guard drawnSignature != signature || drawnSize != size else { return }
        drawnSignature = signature
        drawnSize = size
        imageView.image = drawWallpaper(size: size)
    }

    private var condition: Condition {
        switch weather.weatherCode {
        case 95...99: return .thunder
        case 71...77, 85, 86: return .snow
        case 51...67, 80...82: return .rain
        case 45, 48: return .fog
        case 3: return .overcast
        case 2: return .partlyCloudy
        default:
            let cover = weather.cloudCover ?? 0
            if cover > 80 { return .overcast }
            if cover > 25 { return .partlyCloudy }
            return .clear
        }
    }

    private var cloudCover: CGFloat {
        if let reported = weather.cloudCover {
            return CGFloat(min(100, max(0, reported))) / 100
        }
        switch condition {
        case .clear: return 0.08
        case .partlyCloudy: return 0.45
        default: return 0.90
        }
    }

    private var dusk: Bool {
        guard weather.isDay, let hour = weather.localHour else { return false }
        return (5...7).contains(hour) || (16...18).contains(hour)
    }

    private var colors: [UIColor] {
        if !weather.isDay {
            if condition == .thunder {
                return [
                    UIColor(red: 0.08, green: 0.11, blue: 0.22, alpha: 1),
                    UIColor(red: 0.16, green: 0.21, blue: 0.33, alpha: 1),
                    UIColor(red: 0.23, green: 0.29, blue: 0.39, alpha: 1)
                ]
            }
            return [
                UIColor(red: 0.10, green: 0.17, blue: 0.30, alpha: 1),
                UIColor(red: 0.23, green: 0.32, blue: 0.44, alpha: 1),
                UIColor(red: 0.32, green: 0.40, blue: 0.50, alpha: 1)
            ]
        }
        switch condition {
        case .clear:
            return dusk
                ? [UIColor(red: 0.49, green: 0.65, blue: 0.83, alpha: 1),
                   UIColor(red: 0.70, green: 0.77, blue: 0.87, alpha: 1),
                   UIColor(red: 0.77, green: 0.72, blue: 0.72, alpha: 1)]
                : [UIColor(red: 0.47, green: 0.68, blue: 0.87, alpha: 1),
                   UIColor(red: 0.66, green: 0.79, blue: 0.90, alpha: 1),
                   UIColor(red: 0.72, green: 0.82, blue: 0.90, alpha: 1)]
        case .partlyCloudy:
            return [UIColor(red: 0.53, green: 0.68, blue: 0.84, alpha: 1),
                    UIColor(red: 0.63, green: 0.74, blue: 0.85, alpha: 1),
                    UIColor(red: 0.65, green: 0.74, blue: 0.84, alpha: 1)]
        case .overcast:
            return [UIColor(red: 0.57, green: 0.67, blue: 0.77, alpha: 1),
                    UIColor(red: 0.64, green: 0.73, blue: 0.81, alpha: 1),
                    UIColor(red: 0.59, green: 0.68, blue: 0.77, alpha: 1)]
        case .fog:
            return [UIColor(red: 0.65, green: 0.72, blue: 0.79, alpha: 1),
                    UIColor(red: 0.73, green: 0.79, blue: 0.84, alpha: 1),
                    UIColor(red: 0.69, green: 0.76, blue: 0.82, alpha: 1)]
        case .rain:
            return [UIColor(red: 0.38, green: 0.50, blue: 0.65, alpha: 1),
                    UIColor(red: 0.52, green: 0.63, blue: 0.74, alpha: 1),
                    UIColor(red: 0.56, green: 0.68, blue: 0.76, alpha: 1)]
        case .snow:
            return [UIColor(red: 0.59, green: 0.70, blue: 0.81, alpha: 1),
                    UIColor(red: 0.69, green: 0.78, blue: 0.87, alpha: 1),
                    UIColor(red: 0.73, green: 0.82, blue: 0.87, alpha: 1)]
        case .thunder:
            return [UIColor(red: 0.26, green: 0.35, blue: 0.49, alpha: 1),
                    UIColor(red: 0.39, green: 0.48, blue: 0.60, alpha: 1),
                    UIColor(red: 0.47, green: 0.56, blue: 0.66, alpha: 1)]
        }
    }

    private func drawWallpaper(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        // 1x is enough for the intentionally blurred/soft wallpaper and keeps
        // raster memory low even on high-resolution iPhones.
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let palette = colors

            cg.saveGState()
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: palette.map(\.cgColor) as CFArray,
                locations: [0, 0.48, 1]
            )
            if let gradient {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            } else {
                cg.setFillColor(palette[1].cgColor)
                cg.fill(rect)
            }
            cg.restoreGState()

            if weather.isDay && condition != .thunder {
                // Single soft radial circle, drawn once into the wallpaper.
                let center = CGPoint(x: size.width * 0.77,
                                     y: size.height * (dusk ? 0.48 : 0.20))
                if let glow = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [
                        UIColor.white.withAlphaComponent(dusk ? 0.26 : 0.30).cgColor,
                        UIColor.white.withAlphaComponent(0).cgColor
                    ] as CFArray,
                    locations: [0, 1]
                ) {
                    cg.drawRadialGradient(
                        glow,
                        startCenter: center, startRadius: 2,
                        endCenter: center, endRadius: size.width * 0.48,
                        options: [.drawsAfterEndLocation]
                    )
                }
            }

            // 0..6 simple translucent ellipses. No blur, shadow or offscreen
            // compositing is used; density follows current cloud-cover data.
            let clouds = 1 + Int(cloudCover * 5)
            for i in 0..<clouds {
                let cloudWidth = size.width * CGFloat(0.68 + Double(i % 3) * 0.24)
                let cloudHeight = size.height * CGFloat(0.07 + Double(i % 3) * 0.015)
                let origin = CGPoint(
                    x: size.width * CGFloat(Double((i * 41 + 3) % 103) / 103) - cloudWidth * 0.4,
                    y: size.height * CGFloat(Double((i * 27 + 15) % 87) / 100)
                )
                cg.setFillColor(
                    UIColor.white.withAlphaComponent(
                        (weather.isDay ? 0.07 : 0.035) + Double(cloudCover) * 0.09
                    ).cgColor
                )
                cg.fillEllipse(in: CGRect(origin: origin,
                                          size: CGSize(width: cloudWidth, height: cloudHeight)))
                cg.fillEllipse(in: CGRect(x: origin.x + cloudWidth * 0.22,
                                          y: origin.y - cloudHeight * 0.30,
                                          width: cloudWidth * 0.48,
                                          height: cloudHeight * 1.34))
            }

            if !weather.isDay && cloudCover < 0.75 {
                cg.setFillColor(UIColor.white.withAlphaComponent(0.64).cgColor)
                cg.fillEllipse(in: CGRect(x: size.width * 0.77,
                                          y: size.height * 0.18,
                                          width: 33, height: 33))
            }
            if condition == .rain || condition == .thunder {
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
                cg.setLineWidth(1)
                for i in 0..<18 {
                    let x = size.width * CGFloat(Double((i * 71 + 9) % 101) / 101)
                    let y = size.height * CGFloat(Double((i * 37 + 17) % 101) / 101)
                    cg.move(to: CGPoint(x: x, y: y))
                    cg.addLine(to: CGPoint(x: x - 3, y: y + 13))
                }
                cg.strokePath()
            }
            if condition == .snow {
                cg.setFillColor(UIColor.white.withAlphaComponent(0.39).cgColor)
                for i in 0..<24 {
                    cg.fillEllipse(in: CGRect(
                        x: size.width * CGFloat(Double((i * 73 + 13) % 101) / 101),
                        y: size.height * CGFloat(Double((i * 41 + 11) % 101) / 101),
                        width: 2.4, height: 2.4
                    ))
                }
            }
            // Modest darkening toward bottom preserves white headline contrast.
            if let shade = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.black.withAlphaComponent(0).cgColor,
                    UIColor.black.withAlphaComponent(weather.isDay ? 0.15 : 0.19).cgColor
                ] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(shade, start: CGPoint(x: 0, y: size.height * 0.42),
                                      end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }
}