import CoreLocation
import Foundation
import SQLite3

/// Searches the region's offline place database (built from OpenStreetMap by the maps workflow).
final class OfflineSearchDB {
    private var db: OpaquePointer?
    private let lock = NSLock()

    init?(url: URL) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        db = handle
    }

    deinit {
        sqlite3_close(db)
    }

    /// Prefix search, e.g. "kwik tr" finds "Kwik Trip". Results near `near` rank higher.
    func search(_ text: String, near: CLLocationCoordinate2D?, limit: Int = 25) -> [Place] {
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let match = tokens.map { "\"\($0)\"*" }.joined(separator: " ")

        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT p.id, p.name, p.detail, p.city, p.kind, p.lat, p.lon, p.rank, bm25(places_fts, 10.0, 2.0, 1.0)
        FROM places_fts JOIN places p ON p.id = places_fts.rowid
        WHERE places_fts MATCH ?1
        ORDER BY bm25(places_fts, 10.0, 2.0, 1.0) - p.rank / 25.0
        LIMIT 400
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, match, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        struct Row {
            var place: Place
            var score: Double
        }
        var rows: [Row] = []
        let origin = near.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let name = column(stmt, 1)
            let detail = column(stmt, 2)
            let city = column(stmt, 3)
            let kind = column(stmt, 4)
            let lat = sqlite3_column_double(stmt, 5)
            let lon = sqlite3_column_double(stmt, 6)
            let rank = Double(sqlite3_column_int(stmt, 7))
            let bm25 = sqlite3_column_double(stmt, 8) // more negative = better

            let subtitle = [detail, city].filter { !$0.isEmpty && $0 != name }.joined(separator: " · ")
            let place = Place(
                id: "osm-\(id)",
                name: name,
                subtitle: subtitle,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                category: kind == "poi" ? detail.components(separatedBy: " · ").first : kind
            )

            // Text match, how important the place is, and how close it is.
            var score = -bm25 + rank / 25.0
            if name.lowercased().hasPrefix(tokens[0]) { score += 2 }
            if let origin {
                let km = origin.distance(from: CLLocation(latitude: lat, longitude: lon)) / 1000
                score -= log2(1 + km) * 0.9
            }
            rows.append(Row(place: place, score: score))
        }

        // Drop exact duplicates (same name in the same town), keep the best.
        var seen = Set<String>()
        return rows
            .sorted { $0.score > $1.score }
            .filter { seen.insert("\($0.place.name.lowercased())|\($0.place.subtitle.lowercased())").inserted }
            .prefix(limit)
            .map(\.place)
    }

    /// Points of interest of the given OSM types inside a box (min/max lat and lon).
    func places(ofTypes types: [String], minLat: Double, maxLat: Double, minLon: Double, maxLon: Double,
                limit: Int = 3000) -> [Place]
    {
        guard !types.isEmpty else { return [] }
        // detail is "Type", "Type · address", "Brand · Type" or "Brand · Type · address".
        var conditions: [String] = []
        var binds: [String] = []
        for t in types {
            conditions.append("(detail = ? OR detail LIKE ? OR detail LIKE ? OR detail LIKE ?)")
            binds += [t, "\(t) · %", "% · \(t)", "% · \(t) · %"]
        }
        let sql = """
        SELECT id, name, detail, city, lat, lon FROM places
        WHERE kind = 'poi' AND lat BETWEEN ?1 AND ?2 AND lon BETWEEN ?3 AND ?4
          AND (\(conditions.joined(separator: " OR ")))
        LIMIT \(limit)
        """

        lock.lock()
        defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, minLat)
        sqlite3_bind_double(stmt, 2, maxLat)
        sqlite3_bind_double(stmt, 3, minLon)
        sqlite3_bind_double(stmt, 4, maxLon)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, b) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(5 + i), b, -1, transient)
        }

        var out: [Place] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = column(stmt, 1)
            let detail = column(stmt, 2)
            let city = column(stmt, 3)
            out.append(Place(
                id: "osm-\(sqlite3_column_int64(stmt, 0))",
                name: name,
                subtitle: [detail, city].filter { !$0.isEmpty }.joined(separator: " · "),
                coordinate: CLLocationCoordinate2D(latitude: sqlite3_column_double(stmt, 4),
                                                   longitude: sqlite3_column_double(stmt, 5)),
                category: types.first
            ))
        }
        return out
    }

    private func column(_ stmt: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: c)
    }
}
