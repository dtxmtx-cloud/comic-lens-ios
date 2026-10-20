import Foundation

struct NewsArticle: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let body: String
    let url: URL
    let source: String
    let publishedAt: Date
    var previewText: String { body.isEmpty ? "記事本文・概要は配信されていません。元記事を開いてください。" : body }
}

struct FeedSource: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var address: String
    var enabled = true

    static let defaults: [FeedSource] = [
        .init(name: "NHK ニュース", address: "https://www3.nhk.or.jp/rss/news/cat0.xml"),
        .init(name: "GIGAZINE", address: "https://gigazine.net/news/rss_2.0/"),
        .init(name: "ITmedia NEWS", address: "https://rss.itmedia.co.jp/rss/2.0/news_bursts.xml")
    ]
}

struct WeatherSnapshot {
    var temperature: Double?
    var maximum: Double?
    var minimum: Double?
    var weatherCode = 3
    var isDay = true
    var airQuality: Int?
    var uvIndex: Double?
    var locationName = "位置情報を確認中"

    var description: String {
        switch weatherCode {
        case 0: return "快晴"
        case 1: return "晴れ"
        case 2: return "晴れ時々曇り"
        case 3: return "曇り"
        case 45, 48: return "霧"
        case 51...57: return "霧雨"
        case 61...67, 80...82: return "雨"
        case 71...77, 85, 86: return "雪"
        case 95...99: return "雷雨"
        default: return "天気情報"
        }
    }

    var symbol: String {
        switch weatherCode {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3, 45, 48: return "cloud.fill"
        case 51...67, 80...82, 95...99: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        default: return "cloud.fill"
        }
    }

    var raining: Bool { (51...67).contains(weatherCode) || (80...82).contains(weatherCode) || (95...99).contains(weatherCode) }
    var snowing: Bool { (71...77).contains(weatherCode) || weatherCode == 85 || weatherCode == 86 }
    var cloudy: Bool { weatherCode != 0 && weatherCode != 1 }
}