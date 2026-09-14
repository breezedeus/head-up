import Testing
@testable import HeadUp

struct WeatherServiceTests {
    @Test func mapsCommonWeatherCodesToReadableChinese() {
        #expect(WeatherService.description(for: 0) == "晴")
        #expect(WeatherService.description(for: 63) == "中雨")
        #expect(WeatherService.description(for: 95) == "雷暴")
    }

    @Test func mapsWeatherCodesToSystemSymbols() {
        #expect(WeatherService.symbolName(for: 0, isDay: true) == "sun.max.fill")
        #expect(WeatherService.symbolName(for: 0, isDay: false) == "moon.stars.fill")
        #expect(WeatherService.symbolName(for: 73, isDay: true) == "snowflake")
    }
}
