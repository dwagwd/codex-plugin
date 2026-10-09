import Foundation

/// Linear projection of an observed quota rate until the backend-reported reset.
/// It extrapolates the recent pace only; it is not a prediction of future work.
public struct QuotaForecast: Equatable {
    public enum Outlook: String, Codable { case onTrack, tight, exhausts }
    /// Projected used percentage at the reset time, capped at 100.
    public let projectedUsedAtReset: Double
    /// When the window reaches 100% at the observed pace, if that happens before the reset.
    public let exhaustsAt: Double?
    public var outlook: Outlook {
        if exhaustsAt != nil { return .exhausts }
        return projectedUsedAtReset >= quotaForecastTightThreshold ? .tight : .onTrack
    }
}

public let quotaForecastTightThreshold: Double = 90

public func forecastQuota(used: Double?, perHour: Double?, resetsAt: Double?, now: Double) -> QuotaForecast? {
    guard let used, used.isFinite, (0...100).contains(used),
          let perHour, perHour.isFinite, perHour >= 0,
          let resetsAt, resetsAt.isFinite, now.isFinite, resetsAt > now else { return nil }
    if used >= 100 { return QuotaForecast(projectedUsedAtReset: 100, exhaustsAt: now) }
    let projected = used + perHour * (resetsAt - now) / 3600
    guard projected >= 100, perHour > 0 else { return QuotaForecast(projectedUsedAtReset: projected, exhaustsAt: nil) }
    return QuotaForecast(projectedUsedAtReset: 100, exhaustsAt: now + (100 - used) / perHour * 3600)
}

let forecastTranslations: [String: [String: String]] = [
    "paceForecast": ["en": "Pace forecast", "zh-Hant": "速度預估", "zh-Hans": "速度预估", "ja": "ペース予測", "ko": "속도 예측", "es": "Previsión de ritmo", "fr": "Prévision du rythme", "de": "Tempoprognose", "pt-BR": "Previsão de ritmo", "it": "Previsione del ritmo"],
    "forecastAtReset": ["en": "at reset", "zh-Hant": "於重置時", "zh-Hans": "于重置时", "ja": "リセット時", "ko": "재설정 시", "es": "al reiniciar", "fr": "à la réinitialisation", "de": "beim Zurücksetzen", "pt-BR": "na redefinição", "it": "al ripristino"],
    "forecastFullIn": ["en": "100% in", "zh-Hant": "達 100% 尚餘", "zh-Hans": "达 100% 还剩", "ja": "100% まで", "ko": "100%까지", "es": "100% en", "fr": "100% dans", "de": "100% in", "pt-BR": "100% em", "it": "100% tra"],
    "forecastHelp": ["en": "Linear projection of the observed rate until the reported reset time. It is not a promise of future usage.", "zh-Hant": "以觀測速度線性外推至回報的重置時間，並非未來用量的保證。", "zh-Hans": "以观测速度线性外推至报告的重置时间，并非未来用量的保证。", "ja": "観測した速度を報告されたリセット時刻まで直線的に延長した推定です。将来の使用量を保証するものではありません。", "ko": "관측된 속도를 보고된 재설정 시각까지 선형으로 연장한 추정치이며, 향후 사용량을 보장하지 않습니다.", "es": "Proyección lineal del ritmo observado hasta el reinicio informado. No garantiza el uso futuro.", "fr": "Projection linéaire du rythme observé jusqu’à la réinitialisation indiquée. Ce n’est pas une garantie d’usage futur.", "de": "Lineare Fortschreibung des beobachteten Tempos bis zum gemeldeten Zurücksetzen. Keine Zusage für künftige Nutzung.", "pt-BR": "Projeção linear do ritmo observado até a redefinição informada. Não é uma garantia de uso futuro.", "it": "Proiezione lineare del ritmo osservato fino al ripristino indicato. Non è una garanzia dell’uso futuro."],
]
