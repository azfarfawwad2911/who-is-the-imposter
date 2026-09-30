import SwiftUI
import Combine
import AudioToolbox

@main struct KaunImposterApp: App {
    var body: some Scene { WindowGroup { GameView() } }
}

struct GameView: View {
    @StateObject private var game = PartyGame()
    @StateObject private var rooms = OnlineRooms()
    @State private var holding = false
    @State private var confirmReveal = false
    @State private var tick = Date()
    private let bg = Color(red: 0.063, green: 0.051, blue: 0.137)
    private let card = Color(red: 0.13, green: 0.106, blue: 0.243)
    private let purple = Color(red: 0.596, green: 0.408, blue: 0.980)
    private let pink = Color(red: 1, green: 0.388, blue: 0.624)
    private let muted = Color(red: 0.71, green: 0.67, blue: 0.82)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch game.screen {
                    case .home: home
                    case .connection: connection
                    case .modes: modes
                    case .setup: setup
                    case .category: categories
                    case .handoff: handoff
                    case .discussion: discussion
                    case .result: result
                    case .settings: settings
                    case .onlineEntry: onlineEntry
                    case .onlineRoom: onlineRoom
                    }
                }
                .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 50)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Kaun Imposter?", isPresented: Binding(get: { game.alert != nil || rooms.error != nil }, set: { if !$0 { game.alert = nil; rooms.error = nil } })) {
            Button("OK") { game.alert = nil; rooms.error = nil }
        } message: { Text(game.alert ?? rooms.error ?? "") }
        .confirmationDialog("Reveal now?", isPresented: $confirmReveal) {
            Button("Reveal", role: .destructive) { game.reveal() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Make sure everyone has chosen a suspect.") }
        .onChange(of: rooms.code) { newValue in if !newValue.isEmpty { game.screen = .onlineRoom } }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in tick = date; rooms.clock = date }
    }
    private func effect() { if game.sound { AudioServicesPlaySystemSound(1104) } }
    private func title(_ kicker: String, _ name: String, _ sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker.uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(pink)
            Text(name).font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            if let sub { Text(sub).font(.system(size: 15)).foregroundStyle(muted) }
        }.padding(.bottom, 8)
    }
    private func action(_ name: String, primary: Bool = true, _ run: @escaping () -> Void) -> some View {
        Button { effect(); withAnimation(.easeInOut(duration: 0.2)) { run() } } label: {
            Text(name).font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity)
                .padding(.vertical, 18).foregroundStyle(.white)
                .background(primary ? AnyShapeStyle(LinearGradient(colors: [purple, pink], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(card), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(primary ? .clear : purple.opacity(0.35)))
        }.buttonStyle(.plain)
    }
    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9, content: content)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(purple.opacity(0.22)))
    }
    private var home: some View {
        Group {
            title("✦ PARTY GAME", "KAUN\nIMPOSTER?", game.text("One word. One outsider. Trust nobody.", "Ek word. Ek outsider. Kisi par bharosa mat karo."))
            Image("AppIconPreview").resizable().scaledToFit().frame(width: 190, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 32)).frame(maxWidth: .infinity).padding(.vertical, 10)
            action(game.text("PLAY", "KHELO")) { game.screen = .connection }
            action("MODES", primary: false) { game.screen = .modes }
            action("SETTINGS", primary: false) { game.screen = .settings }
            Text(game.text("Pass the phone or play together online.", "Phone pass karo ya online saath khelo."))
                .font(.footnote).foregroundStyle(muted).frame(maxWidth: .infinity).padding(.top, 16)
        }
    }
    private var connection: some View {
        Group {
            title("01 / 04", game.text("How will you play?", "Kaise kheloge?"), "Pick your party setup.")
            tile { Text("📱  Offline · Pass the phone").font(.title3.bold()); Text("Everyone plays on one phone. No internet needed.").foregroundStyle(muted) }
            action("PLAY OFFLINE") { game.screen = .modes }
            tile { Text("🌐  Online · Room code").font(.title3.bold()); Text("Players join from their own phones, including Android phones.").foregroundStyle(muted) }
            action("PLAY ONLINE", primary: false) { game.screen = .onlineEntry }
            action("←  BACK", primary: false) { game.home() }
        }
    }
    private var modes: some View {
        Group {
            title("02 / 04", game.text("Choose a mode", "Mode chuno"), "Each mode changes who knows what.")
            ForEach(["Classic", "Double Trouble", "Chaos", "Blitz"], id: \.self) { mode in
                Button {
                    effect(); game.mode = mode; game.screen = .setup
                } label: {
                    tile {
                        Text("✦  \(mode)").font(.title2.bold()).foregroundStyle(.white)
                        Text(mode == "Classic" ? "One Ghobar Player gets a different word." : mode == "Double Trouble" ? "Two Ghobar Players. 5–10 players." : mode == "Chaos" ? "Everyone gets a different word." : "One Ghobar Player. 60-second discussion.")
                            .font(.subheadline).foregroundStyle(muted)
                    }
                }.buttonStyle(.plain)
            }
            action("←  BACK", primary: false) { game.screen = .connection }
        }
    }
    private var setup: some View {
        Group {
            title("03 / 04", game.text("Set up your party", "Party setup"), "3 to 10 players · enter everyone's name.")
            tile {
                Stepper("PLAYERS  \(game.count)", value: $game.count, in: 3...10)
                    .font(.headline).tint(pink)
            }
            tile {
                ForEach(0..<game.count, id: \.self) { i in
                    TextField("Player \(i + 1)", text: $game.names[i])
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                        .padding(12).background(bg, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            action("NEXT · CATEGORY") { game.prepareNames() }
            action("←  BACK", primary: false) { game.screen = .modes }
        }
    }
    private var categories: some View {
        Group {
            title("04 / 04", game.text("Choose words", "Words chuno"), "The Ghobar word is independently random and different.")
            ForEach(game.bank.categories, id: \.self) { category in
                Button { effect(); game.category = category; game.start() } label: {
                    tile { HStack { Text(category).font(.title3.bold()); Spacer(); Text("→") }.foregroundStyle(.white) }
                }.buttonStyle(.plain)
            }
            action("←  BACK", primary: false) { game.screen = .setup }
        }
    }
    private func secretCard(word: String, imposter: Bool, didLook: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Text(holding ? (imposter ? "YOU ARE A GHOBAR PLAYER" : "YOUR WORD") : "HOLD TO REVEAL")
                .font(.headline).multilineTextAlignment(.center)
            Text(holding ? word : "✦").font(.system(size: word.count > 17 ? 28 : 37, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center).minimumScaleFactor(0.65)
            Text(holding ? (imposter ? "Act natural. Don't give yourself away!" : "Keep it secret and give careful clues.") : "Keep your word secret.")
                .font(.subheadline).foregroundStyle(muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(18).background(holding ? (imposter ? Color(red: 0.47, green: 0.12, blue: 0.25) : purple.opacity(0.45)) : card, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !holding { holding = true; didLook() } }.onEnded { _ in holding = false })
    }
    private var handoff: some View {
        Group {
            title("SECRET WORD  \(game.index + 1) / \(game.count)", game.players[game.index], "Make sure only this player sees the screen.")
            secretCard(word: game.words[game.index], imposter: game.mode != "Chaos" && game.words[game.index] != game.sharedWord) { game.didLook = true }
            action(game.index == game.count - 1 ? "EVERYONE READY · START" : "HIDE & PASS TO NEXT") { holding = false; game.next() }
        }
    }
    private var discussion: some View {
        Group {
            title("DISCUSSION", "Find the outsider", "Take turns giving clues. Decide together, then reveal.")
            Text(game.timeText(game.remaining)).font(.system(size: 70, weight: .bold, design: .rounded))
                .monospacedDigit().frame(maxWidth: .infinity).padding(.vertical, 34)
            action("REVEAL NOW") { confirmReveal = true }
            action(game.timer == nil || !game.timer!.isValid ? "RESUME TIMER" : "PAUSE TIMER", primary: false) {
                if game.timer?.isValid == true { game.timer?.invalidate() } else if game.remaining > 0 { game.startTimer() }
            }
        }
    }
    private var result: some View {
        Group {
            title("THE REVEAL", game.mode == "Chaos" ? "TOTAL CHAOS" : "THE GHOBAR PLAYER", "Did you guess correctly?")
            if game.mode == "Chaos" {
                ForEach(0..<game.count, id: \.self) { i in tile { Text(game.players[i]).foregroundStyle(muted); Text(game.words[i]).font(.title2.bold()) } }
            } else {
                ForEach(0..<game.count, id: \.self) { i in
                    if game.words[i] != game.sharedWord {
                        tile { Text("🔴  \(game.players[i])").font(.title2.bold()); Text("Different word: \(game.words[i])") }
                    }
                }
                tile { Text("EVERYONE ELSE'S WORD").font(.caption.bold()).foregroundStyle(muted); Text(game.sharedWord).font(.title.bold()) }
            }
            action("PLAY AGAIN · SAME PLAYERS") { game.screen = .category }
            action("CHANGE PLAYERS", primary: false) { game.screen = .setup }
            action("HOME", primary: false) { game.home() }
        }
    }
    private var settings: some View {
        Group {
            title("PREFERENCES", "Settings", "Make the game yours.")
            tile { Toggle("Sound", isOn: $game.sound).tint(pink) }
            tile { Toggle("Roman Urdu", isOn: $game.roman).tint(pink) }
            tile { Picker("Discussion timer", selection: $game.timerLength) {
                Text("1 minute").tag(60); Text("2 minutes").tag(120); Text("3 minutes").tag(180); Text("5 minutes").tag(300)
            }.tint(pink) }
            action("←  HOME", primary: false) { game.home() }
        }
    }
    private var onlineEntry: some View {
        Group {
            title("ONLINE / 01", "Play together", "Create a room or enter a friend's code.")
            tile { TextField("Your name", text: $rooms.name).textInputAutocapitalization(.words).padding(10) }
            action(rooms.busy ? "CONNECTING..." : "CREATE ROOM") { rooms.create(mode: game.mode, duration: game.timerLength) }
                .disabled(rooms.busy)
            tile { TextField("6-digit room code", text: $rooms.inputCode).keyboardType(.numberPad).padding(10) }
            action("JOIN ROOM", primary: false) { rooms.join() }.disabled(rooms.busy)
            action("←  HOME", primary: false) { game.home() }
        }
    }
    private var onlineRoom: some View {
        Group {
            if rooms.status == "lobby" {
                title("ONLINE / ROOM \(rooms.code)", "Room lobby", rooms.host ? "Share the code, then start the game." : "Waiting for the host to start...")
                tile { Text("PLAYERS  \(rooms.players.count) / 10").font(.headline); ForEach(0..<rooms.players.count, id: \.self) { i in Text("•  \(rooms.players[i].1)") } }
                if rooms.host {
                    Text("MODE").font(.caption.bold()).foregroundStyle(muted)
                    ForEach(["Classic", "Double Trouble", "Chaos", "Blitz"], id: \.self) { m in action(m + (rooms.mode == m ? " ✓" : ""), primary: false) { rooms.change("mode", to: m) } }
                    Text("CATEGORY").font(.caption.bold()).foregroundStyle(muted)
                    ForEach(game.bank.categories, id: \.self) { c in action(c + (rooms.category == c ? " ✓" : ""), primary: false) { rooms.change("category", to: c) } }
                    action("START GAME") { rooms.startRound() }
                }
            } else if rooms.status == "words" {
                title("ONLINE / SECRET", "Your secret word", "Hold the card to reveal. Keep it private.")
                secretCard(word: rooms.myWord, imposter: rooms.isImposter) { rooms.didLook = true }
                if rooms.host { action("START DISCUSSION") { holding = false; rooms.startDiscussion() } }
                else { Text("Waiting for host to start discussion...").foregroundStyle(muted) }
            } else if rooms.status == "discussion" {
                title("ONLINE / DISCUSSION", "Find the outsider", "Talk together. The host reveals when ready.")
                Text(game.timeText(rooms.secondsLeft)).font(.system(size: 70, weight: .bold, design: .rounded))
                    .monospacedDigit().frame(maxWidth: .infinity).padding(.vertical, 34)
                if rooms.host { action("REVEAL NOW") { rooms.reveal() } }
            } else if rooms.status == "result" {
                title("ONLINE / REVEAL", rooms.mode == "Chaos" ? "TOTAL CHAOS" : "THE GHOBAR PLAYER", "Here are the words from this round.")
                ForEach(0..<rooms.players.count, id: \.self) { i in
                    let id = rooms.players[i].0
                    let name = rooms.players[i].1
                    let word = (rooms.room["assignments"] as? [String: String])?[id] ?? ""
                    let imp = rooms.mode != "Chaos" && word != (rooms.room["mainWord"] as? String ?? "")
                    tile { Text(name + (imp ? "  🔴" : "")).font(.headline); Text(word).font(.title2.bold()) }
                }
                if rooms.host { action("NEW ROUND") { rooms.newRound() } }
            }
            action("LEAVE ROOM", primary: false) { rooms.leave(); game.home() }
        }
    }
}
