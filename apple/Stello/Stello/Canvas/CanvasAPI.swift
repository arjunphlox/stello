import Foundation

/// `/api/projects` — canvas docs on the Worker, shared with the web canvas,
/// the Figma plugin and the MCP connector. A PUT carries the rev it last read;
/// a stale rev gets 409 with the server's current copy.
nonisolated struct CanvasAPI: Sendable {
    let token: String
    var session: URLSession = .shared

    enum SaveResult: Sendable {
        case saved(CanvasProject)
        case conflict(CanvasProject)
    }

    struct Summary: Decodable, Sendable, Identifiable {
        let id: String
        let name: String?
        let rev: Int
        let cards: Int?
    }

    private struct ProjectBody: Decodable { let project: CanvasProject }
    private struct ListBody: Decodable { let projects: [Summary] }
    private struct ConflictBody: Decodable { let project: CanvasProject? }

    static var current: CanvasAPI? { SyncAccount.api.map { CanvasAPI(token: $0.token) } }

    private func url(_ id: String? = nil) -> URL {
        let base = SyncAPI.baseURL.appending(path: "api/projects")
        guard let id else { return base }
        return base.appending(path: id)
    }

    func list() async throws -> [Summary] {
        let (data, _) = try await send(URLRequest(url: url()))
        return try JSONDecoder().decode(ListBody.self, from: data).projects
    }

    func get(_ id: String) async throws -> CanvasProject {
        let (data, _) = try await send(URLRequest(url: url(id)))
        return try JSONDecoder().decode(ProjectBody.self, from: data).project
    }

    func create(_ doc: CanvasDoc) async throws -> CanvasProject {
        var request = URLRequest(url: url())
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["doc": doc])
        let (data, _) = try await send(request)
        return try JSONDecoder().decode(ProjectBody.self, from: data).project
    }

    func save(_ id: String, doc: CanvasDoc, rev: Int) async throws -> SaveResult {
        struct Put: Encodable { let rev: Int; let doc: CanvasDoc }
        var request = URLRequest(url: url(id))
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(Put(rev: rev, doc: doc))
        let (data, code) = try await send(request, allow409: true)
        if code == 409, let project = try JSONDecoder().decode(ConflictBody.self, from: data).project {
            return .conflict(project)
        }
        return .saved(try JSONDecoder().decode(ProjectBody.self, from: data).project)
    }

    func delete(_ id: String) async throws {
        var request = URLRequest(url: url(id))
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    private func send(_ request: URLRequest, allow409: Bool = false) async throws -> (Data, Int) {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            SyncAccount.tokenRejected()
            throw SyncAPI.Failure.unauthorized
        }
        if allow409 && code == 409 { return (data, code) }
        guard (200..<300).contains(code) else {
            throw SyncAPI.Failure.server(code, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return (data, code)
    }
}
