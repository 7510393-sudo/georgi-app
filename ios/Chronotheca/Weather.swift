import Foundation
import CoreLocation
import WeatherKit

/// Погода в момент записи — строкой в шапке файла дня: «погода: +12°, туман».
///
/// Берётся у Погоды Apple, когда человек сам отметил место: своих серверов
/// у приложения нет, а координаты уходят только в Apple (P198, P208).
/// Не вышло — запись без погоды, а причина видна в настройках под строкой
/// «Погода» (P354): молча — значит, не узнать, чего не хватает.
enum WeatherNote {

    /// Страница с условиями Погоды Apple — её требуется показывать там,
    /// где приложение показывает погоду.
    static let legal = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    static func now(at location: CLLocation) async -> Result<String, Error> {
        do {
            let weather = try await WeatherService.shared.weather(for: location, including: .current)
            let t = Int(weather.temperature.converted(to: .celsius).value.rounded())
            let degrees = (t > 0 ? "+" : "") + "\(t)°"
            return .success(degrees + ", " + words(weather.condition))
        } catch {
            return .failure(error)
        }
    }

    /// Почему Погода Apple не ответила — словами, и с кодом ошибки: по нему
    /// видно, где чинить (P354).
    static func explain(_ error: Error) -> String {
        let ns = error as NSError
        let code = "(" + ns.domain + " " + String(ns.code) + ")"
        // Самая частая беда: у знака приложения на developer.apple.com
        // включено право WeatherKit, но не включена служба WeatherKit —
        // это две разные галочки на двух вкладках.
        if ns.domain.contains("JWTAuthenticator") {
            return "Apple не пускает приложение к погоде. На developer.apple.com → "
                + "Identifiers → com.kobiashvili.diary должна стоять галочка WeatherKit "
                + "и на вкладке Capabilities, и на вкладке App Services. " + code
        }
        return ns.localizedDescription + " " + code
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
