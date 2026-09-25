import Foundation
import CoreLocation
import WeatherKit

/// Погода в момент записи — строкой в шапке файла дня: «погода: +12°, туман».
///
/// Берётся у Погоды Apple, когда человек сам отметил место: своих серверов
/// у приложения нет, а координаты уходят только в Apple (P198, P208).
/// Не вышло — молча без погоды: запись важнее.
enum WeatherNote {

    /// Страница с условиями Погоды Apple — её требуется показывать там,
    /// где приложение показывает погоду.
    static let legal = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    static func now(at location: CLLocation) async -> String? {
        guard let weather = try? await WeatherService.shared.weather(for: location,
                                                                     including: .current)
        else { return nil }
        let t = Int(weather.temperature.converted(to: .celsius).value.rounded())
        let degrees = (t > 0 ? "+" : "") + "\(t)°"
        return degrees + ", " + words(weather.condition)
    }

    /// Состояние неба по-русски: система отвечает на языке телефона, а
    /// запись должна читаться одинаково на любом.
    static func words(_ c: WeatherCondition) -> String {
        switch c {
        case .clear: return "ясно"
        case .mostlyClear: return "почти ясно"
        case .partlyCloudy: return "переменная облачность"
        case .mostlyCloudy, .cloudy: return "облачно"
        case .foggy: return "туман"
        case .haze, .smoky: return "дымка"
        case .drizzle: return "морось"
        case .rain, .sunShowers: return "дождь"
        case .heavyRain: return "ливень"
        case .snow, .flurries, .sunFlurries: return "снег"
        case .heavySnow, .blizzard, .blowingSnow: return "метель"
        case .sleet, .freezingRain, .freezingDrizzle, .wintryMix: return "мокрый снег"
        case .hail: return "град"
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms: return "гроза"
        case .windy, .breezy: return "ветрено"
        case .hot: return "жара"
        case .frigid: return "мороз"
        default: return c.description.lowercased()
        }
    }
}
