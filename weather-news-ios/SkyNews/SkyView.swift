import SwiftUI

struct SkyView: View {
    let weather: WeatherSnapshot

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            GeometryReader { geometry in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let size = geometry.size
                ZStack {
                    LinearGradient(colors: palette, startPoint: .top, endPoint: .bottom)
                    if weather.isDay {
                        Circle()
                            .fill(RadialGradient(colors: [.white.opacity(0.8), .white.opacity(0)],
                                                 center: .center, startRadius: 12, endRadius: 160))
                            .frame(width: 320, height: 320)
                            .position(x: size.width * 0.79, y: size.height * 0.20)
                    } else {
                        Circle().fill(.white.opacity(0.75))
                            .frame(width: 58, height: 58)
                            .blur(radius: 2)
                            .position(x: size.width * 0.82, y: size.height * 0.17)
                        ForEach(0..<28, id: \.self) { i in
                            Circle().fill(.white.opacity(0.15 + 0.55 * abs(sin(time / 5 + Double(i)))))
                                .frame(width: i % 5 == 0 ? 3 : 1.5, height: i % 5 == 0 ? 3 : 1.5)
                                .position(x: size.width * CGFloat(Double((i * 71 + 13) % 101) / 101),
                                          y: size.height * CGFloat(Double((i * 37 + 11) % 65) / 100))
                        }
                    }

                    ForEach(0..<(weather.cloudy ? 10 : 5), id: \.self) { i in
                        CloudSilhouette()
                            .fill(.white.opacity(weather.raining ? 0.15 : (weather.isDay ? 0.21 : 0.08)))
                            .frame(width: CGFloat(155 + i % 3 * 60), height: CGFloat(65 + i % 3 * 16))
                            .blur(radius: CGFloat(12 + i % 4 * 5))
                            .position(
                                x: size.width * CGFloat(Double((i * 29 + 17) % 120) / 100)
                                    + CGFloat(sin(time / (33 + Double(i) * 5) + Double(i)) * 62),
                                y: size.height * CGFloat(Double((i * 17 + 7) % 75) / 100)
                            )
                    }

                    if weather.raining || weather.snowing {
                        ForEach(0..<65, id: \.self) { i in
                            let x = Double((i * 73 + 19) % 101) / 101.0
                            let y = (time * (weather.snowing ? 0.085 : 0.29)
                                     + Double((i * 29) % 97) / 97.0).truncatingRemainder(dividingBy: 1)
                            Capsule()
                                .fill(.white.opacity(weather.snowing ? 0.55 : 0.29))
                                .frame(width: weather.snowing ? 3 : 1.4, height: weather.snowing ? 4 : 22)
                                .rotationEffect(.degrees(weather.snowing ? 0 : -12))
                                .position(x: size.width * CGFloat(x), y: size.height * CGFloat(y))
                        }
                    }

                    LinearGradient(colors: [.clear, .black.opacity(0.11), .black.opacity(0.30)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var palette: [Color] {
        if !weather.isDay {
            return [.init(red: 0.06, green: 0.13, blue: 0.29),
                    .init(red: 0.15, green: 0.27, blue: 0.43),
                    .init(red: 0.27, green: 0.32, blue: 0.45)]
        }
        if weather.raining {
            return [.init(red: 0.33, green: 0.43, blue: 0.57),
                    .init(red: 0.49, green: 0.59, blue: 0.67),
                    .init(red: 0.58, green: 0.65, blue: 0.73)]
        }
        if weather.cloudy {
            return [.init(red: 0.49, green: 0.64, blue: 0.75),
                    .init(red: 0.63, green: 0.74, blue: 0.82),
                    .init(red: 0.62, green: 0.70, blue: 0.78)]
        }
        return [.init(red: 0.27, green: 0.57, blue: 0.82),
                .init(red: 0.43, green: 0.72, blue: 0.91),
                .init(red: 0.68, green: 0.82, blue: 0.91)]
    }
}

private struct CloudSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 0, y: rect.height * 0.40, width: rect.width, height: rect.height * 0.60))
        path.addEllipse(in: CGRect(x: rect.width * 0.22, y: rect.height * 0.12,
                                   width: rect.width * 0.38, height: rect.height * 0.78))
        path.addEllipse(in: CGRect(x: rect.width * 0.49, y: rect.height * 0.02,
                                   width: rect.width * 0.39, height: rect.height * 0.88))
        return path
    }
}