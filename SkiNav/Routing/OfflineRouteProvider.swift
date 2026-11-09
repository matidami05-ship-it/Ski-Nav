import FerrostarCore
import FerrostarCoreFFI
import Foundation
import Valhalla
import ValhallaConfigModels

enum RoutingError: LocalizedError {
    case badRequest
    case engine(String)
    case outsideMap

    var errorDescription: String? {
        switch self {
        case .badRequest: "Couldn’t build the route request."
        case let .engine(message): message
        case .outsideMap: "That destination is outside your downloaded map."
        }
    }
}

/// Calculates routes on the phone with Valhalla, using the downloaded routing tiles.
///
/// Ferrostar's own Valhalla adapter writes the request and reads the response, so offline
/// routes have exactly the same banners, voice prompts and speed limits as online ones.
final class OfflineRouteProvider: CustomRouteProvider {
    private static var engines: [String: Valhalla] = [:]
    private static let engineLock = NSLock()

    private let valhalla: Valhalla
    private let adapter: RouteAdapter

    init(routingTar: URL, options: [String: Any]) throws {
        valhalla = try Self.engine(for: routingTar)
        let provider = try WellKnownRouteProvider.valhalla(
            endpointUrl: "https://offline.invalid/route",
            profile: "auto"
        ).withJsonOptions(options: options)
        adapter = try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: provider)
    }

    /// Loading the engine maps the tile file into memory; do it once per file.
    private static func engine(for tar: URL) throws -> Valhalla {
        engineLock.lock()
        defer { engineLock.unlock() }
        if let existing = engines[tar.path] { return existing }
        let config = try ValhallaConfig(tileExtractTar: tar)
        let engine = try Valhalla(config, configName: "valhalla-\(abs(tar.path.hashValue)).json")
        engines[tar.path] = engine
        return engine
    }

    static func releaseEngines() {
        engineLock.lock()
        defer { engineLock.unlock() }
        for engine in engines.values { engine.close() }
        engines = [:]
    }

    func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        let request = try adapter.generateRequest(userLocation: userLocation, waypoints: waypoints)
        guard case let .httpPost(_, _, body) = request,
              let json = String(data: body, encoding: .utf8)
        else { throw RoutingError.badRequest }

        let engine = valhalla
        let response: String = try await Task.detached(priority: .userInitiated) {
            try engine.route(rawRequest: json)
        }.value

        if let error = Self.errorMessage(in: response) {
            throw RoutingError.engine(error)
        }
        return try adapter.parseResponse(response: Data(response.utf8))
    }

    /// Valhalla answers errors as JSON like {"error_code":171,"error":"No suitable edges near location"}.
    private static func errorMessage(in response: String) -> String? {
        guard response.contains("error"),
              let data = response.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["routes"] == nil
        else { return nil }
        let code = obj["error_code"] as? Int
        let text = (obj["error"] as? String) ?? (obj["message"] as? String) ?? "No route found."
        switch code {
        case 170, 171, 172:
            return "No road found near the start or destination. Is it inside your downloaded map?"
        case 442, 443:
            return "No route found between these places."
        default:
            return text
        }
    }
}
