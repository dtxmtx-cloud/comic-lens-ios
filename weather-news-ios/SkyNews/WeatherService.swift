import Foundation
import CoreLocation
import Combine

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }
    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let uv_index_max: [Double]?
    }
    let current: Current
    let daily: Daily
}

private struct AQIResponse: Decodable {
    struct Current: Decodable { let us_aqi: Int? }
    let current: Current
}

@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var current = WeatherSnapshot()
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastLocation: CLLocation?
    private var requestedPermission = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        if manager.authorizationStatus == .notDetermined && !requestedPermission {
            requestedPermission = true
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse ||
                    manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else {
            current.locationName = "東京（位置情報未許可）"
            Task { await load(latitude: 35.6812, longitude: 139.7671) }
        }
    }

    func refresh() async {
        if let location = lastLocation {
            await load(latitude: location.coordinate.latitude,
                       longitude: location.coordinate.longitude)
        } else {
            start()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied ||
                  manager.authorizationStatus == .restricted {
            current.locationName = "東京（位置情報未許可）"
            Task { await load(latitude: 35.6812, longitude: 139.7671) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        Task {
            if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                current.locationName = placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea ?? "現在地"
            } else {
                current.locationName = "現在地"
            }
            await load(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "位置情報を取得できませんでした。"
        if lastLocation == nil {
            current.locationName = "東京（暫定）"
            Task { await load(latitude: 35.6812, longitude: 139.7671) }
        }
    }

    private func load(latitude: Double, longitude: Double) async {
        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,uv_index_max"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        var air = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        air.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "us_aqi")
        ]
        guard let url = forecast.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
            current.temperature = response.current.temperature_2m
            current.maximum = response.daily.temperature_2m_max.first
            current.minimum = response.daily.temperature_2m_min.first
            current.uvIndex = response.daily.uv_index_max?.first
            current.weatherCode = response.current.weather_code
            current.isDay = response.current.is_day == 1
            errorMessage = nil
        } catch {
            errorMessage = "天気を取得できませんでした。"
        }
        if let airURL = air.url,
           let (airData, _) = try? await URLSession.shared.data(from: airURL),
           let airResponse = try? JSONDecoder().decode(AQIResponse.self, from: airData) {
            current.airQuality = airResponse.current.us_aqi
        }
    }
}