//
//  SupabaseClient.swift
//  TreeInventory
//
//  Thin REST client for syncing projects and tree records to Supabase via
//  PostgREST (Supabase's auto-generated REST API over Postgres).
//
//  SQL Schema — run this once in the Supabase project's SQL editor:
//
// create table projects (
//   id uuid primary key,
//   name text,
//   site_codes text[],
//   created_at timestamptz default now()
// );
//
// create table tree_records (
//   id uuid primary key,
//   project_id uuid references projects(id),
//   surveyor_name text,
//   collected_at timestamptz,       -- TreeRecord.timestamp (actual capture time)
//   uploaded_at timestamptz,        -- set by app after successful sync
//   latitude double precision,
//   longitude double precision,
//   gps_accuracy numeric,
//   utm_northing numeric,
//   utm_easting numeric,
//   utm_zone text,
//   site_code text,
//   tree_id text,
//   dbh_inches numeric,
//   height_feet numeric,
//   spread1_feet numeric,
//   spread2_feet numeric,
//   tree_type text,
//   is_multi_branch boolean,
//   condition text,
//   species text,
//   notes text,
//   photo_url text,                 -- reserved for Supabase Storage URL
//   created_at timestamptz default now()
// );
//
//  RLS — enable before going live (anon key is in the app binary):
//
// alter table projects     enable row level security;
// alter table tree_records enable row level security;
// create policy "anon read"   on projects     for select using (true);
// create policy "anon insert" on projects     for insert with check (true);
// create policy "anon update" on projects     for update using (true);
// create policy "anon read"   on tree_records for select using (true);
// create policy "anon insert" on tree_records for insert with check (true);
// create policy "anon update" on tree_records for update using (true);
//
//  Configuration (project URL + anon key) is entered by the user in
//  ExportSettingsView and persisted via @AppStorage. The anon key is
//  Supabase's public client key — by design, meant to be embedded in
//  client apps. Access control belongs to server-side Row Level Security
//  policies, not to keeping this key secret.
//

import Foundation

enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpError(status: Int, body: String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase isn't configured yet — add your project URL and anon key below."
        case .invalidURL:
            return "That Supabase project URL doesn't look valid."
        case .httpError(let status, let body):
            return body.isEmpty
                ? "Supabase returned an error (HTTP \(status))."
                : "Supabase returned an error (HTTP \(status)): \(body)"
        case .networkError(let message):
            return message
        }
    }
}

private struct SupabaseConfig: Sendable {
    var url: String = ""
    var anonKey: String = ""
    var isConfigured: Bool { !url.isEmpty && !anonKey.isEmpty }
}

/// Thin REST client for Supabase's PostgREST API. Call `configure` with a
/// project URL + anon key, then `uploadProject` / `uploadRecord` to upsert
/// rows. Upserts are keyed on each row's `id`, so re-syncing the same
/// record updates it server-side instead of creating a duplicate.
///
/// Only `Sendable` payload types (built on the main actor, where the
/// SwiftData models live) cross into this actor — `TreeRecord`/`Project`
/// themselves never do.
actor SupabaseClient {
    @MainActor static let shared = SupabaseClient()

    @MainActor init() {}

    private var config = SupabaseConfig()

    func configure(url: String, anonKey: String) {
        var trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmedURL.hasSuffix("/") { trimmedURL.removeLast() }
        config.url = trimmedURL
        config.anonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool { config.isConfigured }

    /// Verifies the URL/key combination is reachable and accepted by
    /// PostgREST, without writing any data. Throws with a descriptive
    /// reason on failure.
    func testConnection() async throws {
        guard config.isConfigured else { throw SupabaseError.notConfigured }
        // Hit the projects table directly — the API root requires service_role
        // in newer Supabase, while table endpoints respect RLS + anon key.
        guard let url = restURL(path: "/projects", query: [
            URLQueryItem(name: "limit", value: "1"),
        ]) else { throw SupabaseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeaders(to: &request)

        let (data, response) = try await send(request)
        try validate(response, data: data)
    }

    func uploadProject(_ payload: SupabaseProjectPayload) async throws {
        try await upsert(payload, table: "projects")
    }

    func uploadRecord(_ payload: SupabaseTreeRecordPayload) async throws {
        try await upsert(payload, table: "tree_records")
    }

    /// Fetches the raw JSON array of tree records for a project. Returns
    /// `Data` rather than a decoded `[String: Any]` so the result stays
    /// `Sendable` across the actor boundary — callers parse it on whichever
    /// actor they're running on.
    func fetchRecordsJSON(forProjectId projectId: UUID) async throws -> Data {
        guard config.isConfigured else { throw SupabaseError.notConfigured }
        guard let url = restURL(path: "/tree_records", query: [
            URLQueryItem(name: "project_id", value: "eq.\(projectId.uuidString)"),
            URLQueryItem(name: "select", value: "*"),
        ]) else { throw SupabaseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeaders(to: &request)

        let (data, response) = try await send(request)
        try validate(response, data: data)
        return data
    }

    // MARK: - Internals

    private func upsert<T: Encodable & Sendable>(_ payload: T, table: String) async throws {
        guard config.isConfigured else { throw SupabaseError.notConfigured }
        guard let url = restURL(path: "/\(table)", query: [
            URLQueryItem(name: "on_conflict", value: "id"),
        ]) else { throw SupabaseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuthHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try Self.jsonEncoder.encode(payload)

        let (data, response) = try await send(request)
        try validate(response, data: data)
    }

    private func restURL(path: String, query: [URLQueryItem] = []) -> URL? {
        guard !config.url.isEmpty,
              var components = URLComponents(string: config.url + "/rest/v1" + path)
        else { return nil }
        if !query.isEmpty { components.queryItems = query }
        return components.url
    }

    private func applyAuthHeaders(to request: inout URLRequest) {
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw SupabaseError.networkError(error.localizedDescription)
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.httpError(status: http.statusCode, body: body)
        }
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - Payload mapping

/// Mirrors the `projects` table. Built on the main actor from a `Project`
/// SwiftData model, then handed to the actor as a plain `Sendable` value.
struct SupabaseProjectPayload: Sendable {
    let id: String
    let name: String
    let site_codes: [String]

    @MainActor
    init(project: Project) {
        id = project.id.uuidString
        name = project.name
        site_codes = project.siteCodes
    }
}

// Explicit nonisolated encode avoids the main-actor-isolated synthesized
// conformance that SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor would otherwise produce.
extension SupabaseProjectPayload: Encodable {
    private enum CodingKeys: String, CodingKey { case id, name, site_codes }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(name,       forKey: .name)
        try c.encode(site_codes, forKey: .site_codes)
    }
}

/// Mirrors the `tree_records` table. Built on the main actor from a
/// `TreeRecord` SwiftData model, then handed to the actor as a plain
/// `Sendable` value.
struct SupabaseTreeRecordPayload: Sendable {
    let id: String
    let project_id: String?
    let surveyor_name: String
    let collected_at: Date
    let uploaded_at: Date?
    let latitude: Double
    let longitude: Double
    let gps_accuracy: Double
    let utm_northing: Double
    let utm_easting: Double
    let utm_zone: String
    let site_code: String
    let tree_id: String
    let dbh_inches: Double?
    let height_feet: Double?
    let spread1_feet: Double?
    let spread2_feet: Double?
    let tree_type: String
    let is_multi_branch: Bool
    let condition: String
    let species: String
    let notes: String

    @MainActor
    init(record: TreeRecord) {
        id = record.id.uuidString
        project_id = record.project?.id.uuidString
        surveyor_name = record.surveyorName
        collected_at = record.timestamp
        uploaded_at = record.uploadedAt
        latitude = record.latitude
        longitude = record.longitude
        gps_accuracy = record.gpsAccuracy
        utm_northing = record.utmNorthing
        utm_easting = record.utmEasting
        utm_zone = record.utmZone
        site_code = record.siteCode
        tree_id = record.treeId
        dbh_inches = record.dbhInches
        height_feet = record.heightFeet
        spread1_feet = record.spread1Feet
        spread2_feet = record.spread2Feet
        tree_type = record.treeType.rawValue
        is_multi_branch = record.isMultiBranch
        condition = record.condition.rawValue
        species = record.species
        notes = record.notes
    }
}

extension SupabaseTreeRecordPayload: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id, project_id, surveyor_name, collected_at, uploaded_at
        case latitude, longitude, gps_accuracy
        case utm_northing, utm_easting, utm_zone
        case site_code, tree_id
        case dbh_inches, height_feet, spread1_feet, spread2_feet
        case tree_type, is_multi_branch, condition, species, notes
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,             forKey: .id)
        try c.encodeIfPresent(project_id,  forKey: .project_id)
        try c.encode(surveyor_name,  forKey: .surveyor_name)
        try c.encode(collected_at,   forKey: .collected_at)
        try c.encodeIfPresent(uploaded_at, forKey: .uploaded_at)
        try c.encode(latitude,       forKey: .latitude)
        try c.encode(longitude,      forKey: .longitude)
        try c.encode(gps_accuracy,   forKey: .gps_accuracy)
        try c.encode(utm_northing,   forKey: .utm_northing)
        try c.encode(utm_easting,    forKey: .utm_easting)
        try c.encode(utm_zone,       forKey: .utm_zone)
        try c.encode(site_code,      forKey: .site_code)
        try c.encode(tree_id,        forKey: .tree_id)
        try c.encodeIfPresent(dbh_inches,   forKey: .dbh_inches)
        try c.encodeIfPresent(height_feet,  forKey: .height_feet)
        try c.encodeIfPresent(spread1_feet, forKey: .spread1_feet)
        try c.encodeIfPresent(spread2_feet, forKey: .spread2_feet)
        try c.encode(tree_type,      forKey: .tree_type)
        try c.encode(is_multi_branch, forKey: .is_multi_branch)
        try c.encode(condition,      forKey: .condition)
        try c.encode(species,        forKey: .species)
        try c.encode(notes,          forKey: .notes)
    }
}
