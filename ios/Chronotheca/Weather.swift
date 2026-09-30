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
            return T("Apple не пускает приложение к погоде. На developer.apple.com → "
                + "Identifiers → com.kobiashvili.diary должна стоять галочка WeatherKit "
                + "и на вкладке Capabilities, и на вкладке App Services. ",
                "Apple does not let the app get the weather. On developer.apple.com → "
                + "Identifiers → com.kobiashvili.diary, WeatherKit must be ticked on both "
                + "the Capabilities and the App Services tabs. ") + code
        }
        return ns.localizedDescription + " " + code
    }

    /// Состояние неба на языке приложения (P355): система отвечает на
    /// языке телефона, а запись пишется на языке дневника.
    static func words(_ c: WeatherCondition) -> String {
        switch c {
        case .clear: return T("ясно", "clear")
        case .mostlyClear: return T("почти ясно", "mostly clear")
        case .partlyCloudy: return T("переменная облачность", "partly cloudy")
        case .mostlyCloudy, .cloudy: return T("облачно", "cloudy")
        case .foggy: return T("туман", "fog")
        case .haze, .smoky: return T("дымка", "haze")
        case .drizzle: return T("морось", "drizzle")
        case .rain, .sunShowers: return T("дождь", "rain")
        case .heavyRain: return T("ливень", "heavy rain")
        case .snow, .flurries, .sunFlurries: return T("снег", "snow")
        case .heavySnow, .blizzard, .blowingSnow: return T("метель", "blizzard")
        case .sleet, .freezingRain, .freezingDrizzle, .wintryMix: return T("мокрый снег", "sleet")
        case .hail: return T("град", "hail")
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms: return T("гроза", "thunderstorm")
        case .windy, .breezy: return T("ветрено", "windy")
        case .hot: return T("жара", "hot")
        case .frigid: return T("мороз", "frigid")
        default: return c.description.lowercased()
        }
    }
}
