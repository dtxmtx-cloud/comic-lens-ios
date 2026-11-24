import SwiftUI

/// A static sky that derives its palette, cloud density and weather details
/// exclusively from the latest Open-Meteo current-weather snapshot.
///
/// No animated background, camera feed, remote wallpaper, or rotating pictures.
/// Changing the weather snapshot automatically changes the wallpaper.
struct SkyView: View {
    let weather: WeatherSnapshot

    private enum SkyCondition: Equatable {
        case clear, partlyCloudy, overcast, fog, rain, snow, thunder
    }

    private var condition: SkyCondition {
        switch weather.weatherCode {
        case 95...99: return .thunder
        case 71...77, 85, 86: return .snow
        case 51...67, 80...82: return .rain
        case 45, 48: return .fog
        case 3: return .overcast
        case 2: return .partlyCloudy
        default:
            let cloud = weather.cloudCover ?? 0
            return cloud > 80 ? .overcast : (cloud > 25 ? .partlyCloudy : .clear)
        }
    }

    private var cloudiness: Double {
        let fromAPI = Double(weather.cloudCover ?? -1) / 100.0
        if fromAPI >= 0 { return min(1, max(0, fromAPI)) }
        switch condition {
        case .clear: return 0.07
        case .partlyCloudy: return 0.45
        case .overcast, .fog, .rain, .snow, .thunder: return 0.92
        }
    }

    private var nearSunset: Bool {
        guard weather.isDay, let hour = weather.localHour else { return false }
        return (5...7).contains(hour) || (16...18).contains(hour)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: skyPalette, startPoint: .top, endPoint: .bottom)

                if weather.isDay {
                    daylight(at: size)
                } else {
                    nightlight(at: size)
                }

                // Long, semi-transparent clouds create a cloudy-photograph-like
                // impression without replacing the user's restrained design.
                clouds(in: size)

                if condition == .fog {
                    haze(in: size)
                }

                if condition == .rain || condition == .thunder {
                    rainfall(in: size)
                }
                if condition == .snow {
                    snowfall(in: size)
                }
                // Dim the lower half slightly so white text and glass ticker
                // lanes remain readable for every weather and light condition.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(weather.isDay ? 0.06 : 0.04), location: 0.40),
                        .init(color: .black.opacity(weather.isDay ? 0.18 : 0.23), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func daylight(at size: CGSize) -> some View {
        if condition != .thunder {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(nearSunset ? 0.48 : (cloudiness > 0.75 ? 0.23 : 0.63)),
                            Color.white.opacity(cloudiness > 0.75 ? 0.09 : 0.23),
                            Color.white.opacity(0)
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: 235
                    )
                )
                .frame(width: 470, height: 470)
                .position(
                    x: size.width * 0.74,
                    y: size.height * (nearSunset ? 0.48 : 0.18)
                )
        }
    }

    private func nightlight(at size: CGSize) -> some View {
        ZStack {
            if cloudiness < 0.7 {
                ForEach(0..<25, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(Double((i * 7) % 5 + 2) / 15))
                        .frame(width: i % 6 == 0 ? 2.4 : 1.2,
                               height: i % 6 == 0 ? 2.4 : 1.2)
                        .position(
                            x: size.width * CGFloat(Double((i * 67 + 17) % 101) / 101),
                            y: size.height * CGFloat(Double((i * 29 + 11) % 64) / 100)
                        )
                }
                Circle()
                    .fill(Color.white.opacity(0.65))
                    .frame(width: 43, height: 43)
                    .blur(radius: 2)
                    .position(x: size.width * 0.80, y: size.height * 0.19)
            }
        }
    }

    private func clouds(in size: CGSize) -> some View {
        let density = cloudiness
        let count = max(3, Int(5 + density * 13))
        let alpha: Double = weather.isDay ? 0.10 + density * 0.26 : 0.06 + density * 0.13
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let width = size.width * CGFloat(0.72 + Double(i % 5) * 0.13)
                let y = size.height * CGFloat(Double((i * 29 + 9) % 93) / 100)
                CloudSilhouette()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(alpha * Double(i % 3 + 1) / 3),
                                Color.white.opacity(alpha),
                                Color(red: 0.44, green: 0.55, blue: 0.68)
                                    .opacity(alpha * 0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width, height: CGFloat(78 + i % 4 * 36))
                    .blur(radius: CGFloat(17 + (i % 5) * 8))
                    .position(
                        x: size.width * CGFloat(Double((i * 37 + 13) % 115) / 100),
                        y: y
                    )
            }
            if density > 0.72 {
                // Overcast layers are broad and diffuse, not solid gray bars.
                Ellipse()
                    .fill(.white.opacity(weather.isDay ? 0.19 : 0.07))
                    .frame(width: size.width * 1.8, height: size.height * 0.20)
                    .blur(radius: 70)
                    .position(x: size.width * 0.48, y: size.height * 0.28)
            }
        }
    }

    private func haze(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Ellipse()
                    .fill(.white.opacity(weather.isDay ? 0.18 : 0.07))
                    .frame(width: size.width * 1.55, height: 135)
                    .blur(radius: 55)
                    .position(x: size.width * 0.5,
                              y: size.height * (0.19 + Double(i) * 0.17))
            }
        }
    }

    private func rainfall(in size: CGSize) -> some View {
        let intense = weather.precipitation ?? 0
        let count = intense > 1.0 ? 70 : 37
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(weather.isDay ? 0.13 : 0.21))
                    .frame(width: 1.1, height: CGFloat(10 + (i % 4) * 5))
                    .rotationEffect(.degrees(-12))
                    .position(
                        x: size.width * CGFloat(Double((i * 73 + 19) % 103) / 103),
                        y: size.height * CGFloat(Double((i * 47 + 5) % 101) / 101)
                    )
            }
        }
    }

    private func snowfall(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<65, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(weather.isDay ? 0.49 : 0.67))
                    .frame(width: CGFloat(2 + i % 3), height: CGFloat(2 + i % 3))
                    .blur(radius: i % 6 == 0 ? 1 : 0)
                    .position(
                        x: size.width * CGFloat(Double((i * 71 + 15) % 103) / 103),
                        y: size.height * CGFloat(Double((i * 37 + 19) % 101) / 101)
                    )
            }
        }
    }

    private var skyPalette: [Color] {
        if !weather.isDay {
            switch condition {
            case .thunder: return [
                Color(red: 0.07, green: 0.09, blue: 0.18),
                Color(red: 0.15, green: 0.17, blue: 0.28),
                Color(red: 0.20, green: 0.22, blue: 0.34)
            ]
            case .rain, .snow, .fog, .overcast: return [
                Color(red: 0.10, green: 0.15, blue: 0.26),
                Color(red: 0.22, green: 0.30, blue: 0.42),
                Color(red: 0.29, green: 0.36, blue: 0.48)
            ]
            default: return [
                Color(red: 0.07, green: 0.15, blue: 0.31),
                Color(red: 0.17, green: 0.28, blue: 0.44),
                Color(red: 0.28, green: 0.34, blue: 0.47)
            ]
            }
        }
        switch condition {
        case .clear:
            return nearSunset ? [
                Color(red: 0.42, green: 0.61, blue: 0.82),
                Color(red: 0.65, green: 0.71, blue: 0.83),
                Color(red: 0.82, green: 0.72, blue: 0.68)
            ] : [
                Color(red: 0.42, green: 0.68, blue: 0.90),
                Color(red: 0.59, green: 0.76, blue: 0.90),
                Color(red: 0.75, green: 0.84, blue: 0.91)
            ]
        case .partlyCloudy:
            return [
                Color(red: 0.54, green: 0.71, blue: 0.87),
                Color(red: 0.65, green: 0.76, blue: 0.86),
                Color(red: 0.66, green: 0.74, blue: 0.83)
            ]
        case .overcast:
            return [
                Color(red: 0.54, green: 0.64, blue: 0.75),
                Color(red: 0.63, green: 0.71, blue: 0.81),
                Color(red: 0.59, green: 0.67, blue: 0.78)
            ]
        case .fog:
            return [
                Color(red: 0.62, green: 0.69, blue: 0.76),
                Color(red: 0.72, green: 0.76, blue: 0.82),
                Color(red: 0.67, green: 0.73, blue: 0.79)
            ]
        case .rain:
            return [
                Color(red: 0.39, green: 0.51, blue: 0.65),
                Color(red: 0.48, green: 0.60, blue: 0.72),
                Color(red: 0.57, green: 0.67, blue: 0.76)
            ]
        case .snow:
            return [
                Color(red: 0.57, green: 0.68, blue: 0.80),
                Color(red: 0.70, green: 0.78, blue: 0.86),
                Color(red: 0.76, green: 0.81, blue: 0.87)
            ]
        case .thunder:
            return [
                Color(red: 0.23, green: 0.31, blue: 0.46),
                Color(red: 0.37, green: 0.46, blue: 0.59),
                Color(red: 0.45, green: 0.52, blue: 0.65)
            ]
        }
    }
}

private struct CloudSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 0, y: rect.height * 0.40,
                                   width: rect.width, height: rect.height * 0.60))
        path.addEllipse(in: CGRect(x: rect.width * 0.22, y: rect.height * 0.12,
                                   width: rect.width * 0.38, height: rect.height * 0.78))
        path.addEllipse(in: CGRect(x: rect.width * 0.49, y: rect.height * 0.02,
                                   width: rect.width * 0.39, height: rect.height * 0.88))
        return path
    }
}