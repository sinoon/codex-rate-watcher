import Foundation

public enum RateWatcherURLSessionFactory {
  public static let shared: URLSession = URLSession(configuration: makeConfiguration())

  public static func makeConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 60
    configuration.httpMaximumConnectionsPerHost = 4
    configuration.waitsForConnectivity = false
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.httpAdditionalHeaders = [
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
    ]
    return configuration
  }
}
