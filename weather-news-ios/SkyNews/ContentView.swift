import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var weather = WeatherService()
    @StateObject private var feeds = SourceStore()
    @StateObject private var news = NewsStore()
    @StateObject private var interests = InterestStore()

    @AppStorage("news.scrollSpeed") private var scrollSpeed = 17.0
    @AppStorage("news.fontSize") private var fontSize = 20.0
    @AppStorage("news.preferencePercent") private var preferencePercent = 70
    @AppStorage("news.fetchWebBodies") private var fetchWebBodies = true
    @State private var showSettings = false
    @State private var paused = false
    @State private var visibleArticleID: String?

    private var ordered: [NewsArticle] {
        interests.rank(news.articles, preferredPercent: preferencePercent)
    }

    private var selected: NewsArticle? {
        ordered.first(where: { $0.id == visibleArticleID }) ?? ordered.first
    }

    var body: some View {
        ZStack {
            SkyView(weather: weather.current)
            VStack(spacing: 8) {
                clockAndWeather
                    .padding(.horizontal, 22)
                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                    Text("NEWS STREAM")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(2)
                    Spacer()
                    if news.loading { ProgressView().tint(.white) }
                    Text("\(news.articles.count) 件")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.87))
                .padding(.horizontal, 24)
                .padding(.top, 6)

                if ordered.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(news.message ?? "RSSの記事を取得しています…")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NewsScrollView(
                        articles: ordered,
                        pointsPerSecond: scrollSpeed,
                        textSize: fontSize,
                        paused: paused,
                        onVisibleArticle: { id in
                            if visibleArticleID != id {
                                DispatchQueue.main.async { visibleArticleID = id }
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let message = news.message {
                    Text(message).font(.caption2)
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2).padding(.horizontal, 20)
                }
                controls
                    .padding(.horizontal, 15)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            weather.start()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task {
            await news.refresh(feeds.sources, fetchWebBodies: fetchWebBodies)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000_000)
                guard !Task.isCancelled else { break }
                await news.refresh(feeds.sources, fetchWebBodies: fetchWebBodies)
                await weather.refresh()
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            Task { await news.refresh(feeds.sources, fetchWebBodies: fetchWebBodies) }
        }) {
            SettingsView(sources: feeds, interest: interests) {
                Task { await news.refresh(feeds.sources, fetchWebBodies: fetchWebBodies) }
            }
        }
    }

    private var clockAndWeather: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let now = timeline.date
                VStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Text(Self.dateText(now))
                        Image(systemName: weather.current.symbol)
                            .symbolRenderingMode(.hierarchical)
                        Text(weather.current.locationName)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.97))

                    Text(Self.timeText(now))
                        .font(.system(size: 90, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: weather.current.symbol)
                        Text(weather.current.temperature.map { String(format: "%.0f°C", $0) } ?? "--°C")
                    }
                    .font(.system(size: 23, weight: .semibold))
                    Text(weather.current.description)
                    Text("最高: \(formatDegree(weather.current.maximum))  最低: \(formatDegree(weather.current.minimum))")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)

                weatherGauge(
                    value: weather.current.airQuality.map(String.init) ?? "--",
                    label: "AQI",
                    valueFraction: min(1, Double(weather.current.airQuality ?? 0) / 180)
                )
                weatherGauge(
                    value: weather.current.uvIndex.map { String(format: "%.1f", $0) } ?? "--",
                    label: "UV",
                    valueFraction: min(1, (weather.current.uvIndex ?? 0) / 11)
                )
            }
            .foregroundStyle(.white)
            .padding(.top, -3)
        }
    }

    private func weatherGauge(value: String, label: String, valueFraction: Double) -> some View {
        VStack(spacing: -2) {
            ZStack {
                Circle().trim(from: 0.08, to: 0.92)
                    .stroke(.white.opacity(0.24), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Circle().trim(from: 0.08, to: 0.08 + 0.84 * max(0, valueFraction))
                    .stroke(.white.opacity(0.90), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            .rotationEffect(.degrees(90))
            .overlay {
                Text(value).font(.system(size: 22, weight: .medium))
            }
            .frame(width: 70, height: 70)
            Text(label).font(.caption2)
        }
        .frame(width: 79)
    }

    private var controls: some View {
        HStack(spacing: 9) {
            Button { paused.toggle() } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .frame(width: 34, height: 38)
            }
            .accessibilityLabel(paused ? "スクロール再開" : "スクロール一時停止")

            Button {
                if let article = selected {
                    interests.vote(article, liked: true)
                }
            } label: {
                Label("興味あり", systemImage: "hand.thumbsup.fill")
                    .foregroundStyle(interests.votes[selected?.id ?? ""] == 1 ? .mint : .white)
            }
            .disabled(selected == nil)

            Button {
                if let article = selected {
                    interests.vote(article, liked: false)
                }
            } label: {
                Label("興味なし", systemImage: "hand.thumbsdown.fill")
                    .foregroundStyle(interests.votes[selected?.id ?? ""] == -1 ? .orange : .white)
            }
            .disabled(selected == nil)

            Spacer(minLength: 0)

            if let article = selected {
                Link(destination: article.url) {
                    Image(systemName: "arrow.up.right.square").frame(width: 30, height: 38)
                }
                .accessibilityLabel("元記事を開く")
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").frame(width: 30, height: 38)
            }
            .accessibilityLabel("設定")
        }
        .font(.system(size: 12, weight: .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .background(.black.opacity(0.28), in: Capsule())
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "d日(E)"
        return formatter.string(from: date)
    }

    private func formatDegree(_ value: Double?) -> String {
        value.map { String(format: "%.0f°", $0) } ?? "--°"
    }
}