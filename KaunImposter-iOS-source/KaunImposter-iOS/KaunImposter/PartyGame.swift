import Foundation
import Combine

struct WordBank {
    private let groups: [String: [String]]
    init() {
        if let url = Bundle.main.url(forResource: "words", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let value = try? JSONDecoder().decode([String: [String]].self, from: data) {
            groups = value
        } else { groups = [:] }
    }
    let categories = ["All", "Food", "Daily Life", "Funny & Animals", "Animals"]
    func words(in category: String) -> [String] {
        if category == "All" { return Array(Set(groups.values.flatMap { $0 })) }
        return Array(Set(groups[category] ?? []))
    }
}

@MainActor final class PartyGame: ObservableObject {
    enum Screen { case home, connection, modes, setup, category, handoff, discussion, result, settings, onlineEntry, onlineRoom }
    @Published var screen: Screen = .home
    @Published var mode = "Classic"
    @Published var category = "All"
    @Published var count = 4
    @Published var names = Array(repeating: "", count: 10)
    @Published var players = [String]()
    @Published var words = [String]()
    @Published var sharedWord = ""
    @Published var index = 0
    @Published var didLook = false
    @Published var remaining = 180
    @Published var sound = true
    @Published var roman = false
    @Published var timerLength = 180
    @Published var alert: String?
    let bank = WordBank()
    var timer: Timer?

    func text(_ english: String, _ urdu: String) -> String { roman ? urdu : english }
    func prepareNames() {
        let trimmed = names.prefix(count).enumerated().map { i, name in
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Player \(i + 1)" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard Set(trimmed.map { $0.lowercased() }).count == count else { alert = "Names must be unique"; return }
        guard mode != "Double Trouble" || count >= 5 else { alert = "Double Trouble needs at least 5 players"; return }
        players = trimmed
        screen = .category
    }
    func start() {
        let pool = bank.words(in: category).shuffled()
        guard pool.count >= count else { alert = "Not enough words in this category"; return }
        sharedWord = pool[0]
        words = Array(repeating: sharedWord, count: count)
        if mode == "Chaos" { words = Array(pool.prefix(count)) }
        else {
            let number = mode == "Double Trouble" ? 2 : 1
            for position in Array(0..<count).shuffled().prefix(number) { words[position] = pool[1] }
        }
        index = 0; didLook = false
        remaining = mode == "Blitz" ? 60 : timerLength
        screen = .handoff
    }
    func next() {
        guard didLook else { alert = "Hold the card to see your word first"; return }
        if index < count - 1 { index += 1; didLook = false }
        else { screen = .discussion; startTimer() }
    }
    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remaining > 0 { self.remaining -= 1 }
                if self.remaining == 0 { self.timer?.invalidate() }
            }
        }
    }
    func reveal() { timer?.invalidate(); screen = .result }
    func home() { timer?.invalidate(); screen = .home }
    func timeText(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
