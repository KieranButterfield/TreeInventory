//
//  SupabaseClient.swift
//  TreeInventory
//
// SQL Schema:
// -- create table projects (
// --   id uuid primary key default gen_random_uuid(),
// --   name text,
// --   site_codes text[],
// --   created_at timestamptz default now()
// -- );
// -- create table tree_records (
// --   id uuid primary key default gen_random_uuid(),
// --   project_id uuid references projects(id),
// --   surveyor_name text, collected_at timestamptz, uploaded_at timestamptz,
// --   latitude double precision, longitude double precision, gps_accuracy numeric,
// --   utm_northing numeric, utm_easting numeric, utm_zone text,
// --   site_code text, tree_id text, dbh_inches numeric, height_feet numeric,
// --   spread1_feet numeric, spread2_feet numeric, tree_type text,
// --   is_multi_branch boolean, condition text, species text, notes text,
// --   created_at timestamptz default now()
// -- );

import Foundation

enum SupabaseError: Error {
    case notConfigured
    case networkError(Error)
}

struct SupabaseConfig: Sendable {
    nonisolated init() {}
    nonisolated var url: String = ""
    nonisolated var anonKey: String = ""
    nonisolated var isConfigured: Bool { !url.isEmpty && !anonKey.isEmpty }
}

actor SupabaseClient {
    @MainActor static let shared = SupabaseClient()

    @MainActor init() {}

    private var config = SupabaseConfig()

    func configure(url: String, anonKey: String) {
        config.url = url
        config.anonKey = anonKey
    }

    func uploadRecord(_ record: TreeRecord) async throws {
        guard config.isConfigured else { throw SupabaseError.notConfigured }
        // TODO: implement real Supabase REST upload
    }

    func fetchRecords(forProjectId projectId: UUID) async throws -> [[String: Any]] {
        guard config.isConfigured else { throw SupabaseError.notConfigured }
        // TODO: implement real Supabase REST fetch
        return []
    }
}
