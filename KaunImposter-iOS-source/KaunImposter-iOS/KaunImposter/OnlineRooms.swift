import Foundation
import Combine

@MainActor final class OnlineRooms: ObservableObject {
    @Published var code = ""
    @Published var name = ""
    @Published var inputCode = ""
    @Published var room: [String: Any] = [:]
    @Published var error: String?
    @Published var busy = false
    @Published var didLook = false
    @Published var clock = Date()
    private(set) var uid = ""
    private var token = ""
    private(set) var host = false
    private var pollTask: Task<Void, Never>?
    let bank = WordBank()

    var status: String { room["status"] as? String ?? "lobby" }
    var mode: String { room["mode"] as? String ?? "Classic" }
    var category: String { room["category"] as? String ?? "All" }
    var players: [(String, String)] {
        let entries = room["players"] as? [String: [String: Any]] ?? [:]
        return entries.map { ($0.key, $0.value["name"] as? String ?? "Player") }.sorted { $0.1 < $1.1 }
    }
    var myWord: String { (room["assignments"] as? [String: String])?[uid] ?? "" }
    var isImposter: Bool { mode != "Chaos" && !myWord.isEmpty && myWord != (room["mainWord"] as? String ?? "") }
    var secondsLeft: Int {
        let started = (room["startedAt"] as? NSNumber)?.doubleValue ?? clock.timeIntervalSince1970 * 1000
        let length = mode == "Blitz" ? 60 : (room["duration"] as? Int ?? 180)
        return max(0, length - Int((clock.timeIntervalSince1970 * 1000 - started) / 1000))
    }

    func create(mode: String, duration: Int) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter your name"; return }
        busy = true; host = true
        Task {
            do {
                try await signIn()
                code = String(format: "%06d", Int.random(in: 100000...999999))
                let data: [String: Any] = ["hostUid": uid, "status": "lobby", "mode": mode,
                    "category": "All", "duration": duration, "players": [uid: ["name": name]]]
                _ = try await database("PUT", "", body: data)
                room = data; busy = false; beginPolling()
            } catch { busy = false; self.error = error.localizedDescription }
        }
    }
    func join() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              inputCode.count == 6, inputCode.allSatisfy(\.isNumber) else { error = "Enter your name and 6-digit code"; return }
        busy = true; host = false; code = inputCode
        Task {
            do {
                try await signIn()
                let current = try await database("GET", "") as? [String: Any] ?? [:]
                guard current["hostUid"] != nil else { throw RoomError.message("Room not found") }
                guard (current["status"] as? String) == "lobby" else { throw RoomError.message("This round already started") }
                let entries = current["players"] as? [String: Any] ?? [:]
                guard entries.count < 10 else { throw RoomError.message("Room is full") }
                _ = try await database("PUT", "/players/\(uid)", body: ["name": name])
                room = current; busy = false; beginPolling()
            } catch { busy = false; self.error = error.localizedDescription }
        }
    }
    func change(_ key: String, to value: String) {
        guard host else { return }
        Task { do { _ = try await database("PATCH", "", body: [key: value]); await refresh() }
               catch { self.error = error.localizedDescription } }
    }
    func startRound() {
        guard host else { return }
        let people = players.map { $0.0 }.shuffled(), pool = bank.words(in: category).shuffled()
        guard people.count >= 3 else { error = "At least 3 players needed"; return }
        guard mode != "Double Trouble" || people.count >= 5 else { error = "Double Trouble needs 5 players"; return }
        guard pool.count >= people.count else { error = "Not enough words"; return }
        var assignments = [String: String]()
        for (i, id) in people.enumerated() {
            assignments[id] = mode == "Chaos" ? pool[i] : (i < (mode == "Double Trouble" ? 2 : 1) ? pool[1] : pool[0])
        }
        didLook = false
        Task {
            do {
                _ = try await database("PATCH", "", body: ["status": "words", "assignments": assignments,
                    "mainWord": pool[0], "otherWord": pool[1]])
                await refresh()
            } catch { self.error = error.localizedDescription }
        }
    }
    func startDiscussion() {
        guard host, didLook else { error = "Hold to see your word first"; return }
        Task { do { _ = try await database("PATCH", "", body: ["status": "discussion",
                    "startedAt": Int(Date().timeIntervalSince1970 * 1000)]); await refresh() }
               catch { self.error = error.localizedDescription } }
    }
    func reveal() {
        guard host else { return }
        Task { do { _ = try await database("PATCH", "", body: ["status": "result"]); await refresh() }
               catch { self.error = error.localizedDescription } }
    }
    func newRound() {
        guard host else { return }
        didLook = false
        Task { do { _ = try await database("PATCH", "", body: ["status": "lobby", "assignments": NSNull(),
                    "mainWord": NSNull(), "otherWord": NSNull(), "startedAt": NSNull()]); await refresh() }
               catch { self.error = error.localizedDescription } }
    }
    func leave() {
        pollTask?.cancel(); pollTask = nil
        let leavingCode = code, leavingUid = uid, wasHost = host
        Task {
            if !leavingCode.isEmpty && !token.isEmpty {
                _ = try? await database("DELETE", wasHost ? "" : "/players/\(leavingUid)")
            }
            room = [:]; code = ""; didLook = false
        }
    }
    private func beginPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }
    private func refresh() async {
        do {
            let result = try await database("GET", "") as? [String: Any] ?? [:]
            if result.isEmpty { error = "Room closed"; pollTask?.cancel(); room = [:]; return }
            room = result; clock = Date()
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func signIn() async throws {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(FirebaseConfig.apiKey)")!
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])
        let response = try await perform(req) as? [String: Any] ?? [:]
        guard let id = response["localId"] as? String, let jwt = response["idToken"] as? String else {
            throw RoomError.message("Could not sign in")
        }
        uid = id; token = jwt
    }
    private func database(_ method: String, _ suffix: String, body: Any? = nil) async throws -> Any {
        guard let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(FirebaseConfig.databaseURL)/rooms/\(code)\(suffix).json?auth=\(encoded)") else {
            throw RoomError.message("Invalid room URL")
        }
        var req = URLRequest(url: url); req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(req)
    }
    private func perform(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RoomError.message("Server \(status): \(message.prefix(160))")
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
    enum RoomError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
