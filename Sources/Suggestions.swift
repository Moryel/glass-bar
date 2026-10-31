import AppKit
import SwiftUI

// Typing suggestions (QuickType) and the emoji strip.

/// Text before the cursor in the focused text field (read through Accessibility).
struct TextContext: Equatable {
    var text: String
    var cursor: Int

    /// Called on the work queue. nil if no text field is focused.
    static func read() -> TextContext? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let o = focused as! AXUIElement
        var value: CFTypeRef?, range: CFTypeRef?
        AXUIElementCopyAttributeValue(o, kAXValueAttribute as CFString, &value)
        AXUIElementCopyAttributeValue(o, kAXSelectedTextRangeAttribute as CFString, &range)
        guard let text = value as? String, let range, CFGetTypeID(range) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        guard AXValueGetValue(range as! AXValue, .cfRange, &r), r.length == 0 else { return nil }
        let ns = text as NSString
        guard r.location >= 0, r.location <= ns.length else { return nil }
        // the last few hundred characters before the cursor are enough for prediction
        let press = max(0, r.location - 300)
        return TextContext(text: ns.substring(with: NSRange(location: press, length: r.location - press)), cursor: r.location - press)
    }
}

/// Three boxes like the original: with a partial word, the first is the typed text itself (in quotes), the others
/// completions; without one, all three predict the next word. If misspelled, the first completion is blue (correction).
struct Suggestions: Equatable {
    var isActive = false
    var partialWord = ""
    var charactersToDelete = 0
    var words: [String] = []
    var isCorrection = false

    /// The candidate system macOS uses for the Touch Bar (NSSpellChecker); called on the main thread.
    static func request(_ b: TextContext, _ completion: @escaping (Suggestions) -> Void) {
        let checker = NSSpellChecker.shared
        let ns = b.text as NSString
        checker.requestCandidates(forSelectedRange: NSRange(location: b.cursor, length: 0), in: b.text,
                                  types: NSTextCheckingAllSystemTypes, options: nil, inSpellDocumentWithTag: 0) { _, result in
            let range = result.first?.range ?? NSRange(location: b.cursor, length: 0)
            let partialWord = range.length > 0 && NSMaxRange(range) <= ns.length ? ns.substring(with: range) : ""
            var seen = Set<String>([partialWord.lowercased()])
            var words: [String] = []
            for r in result {
                guard let k = r.replacementString?.trimmingCharacters(in: .whitespaces), !k.isEmpty,
                      seen.insert(k.lowercased()).inserted else { continue }
                words.append(k)
            }
            let isMisspelled = partialWord.count > 2 && checker.checkSpelling(of: partialWord, startingAt: 0).location != NSNotFound
            let o = Suggestions(isActive: true, partialWord: partialWord, charactersToDelete: partialWord.count,
                             words: Array(words.prefix(partialWord.isEmpty ? 3 : 2)),
                             isCorrection: isMisspelled && !words.isEmpty)
            DispatchQueue.main.async { completion(o) }
        }
    }

    /// Deletes the partial word and types the chosen word plus a space.
    func select(_ word: String) {
        for _ in 0..<charactersToDelete { SystemControl.pressKey(51) }
        SystemControl.typeText(word + " ")
    }
}

enum Emoji {
    /// Categories and order of the original emoji picker: Frequently Used, Smileys & People, Animals & Nature,
    /// Food & Drink, Activity, Travel & Places, Objects, Symbols, Flags.
    static let categories: [(symbol: String, emojis: [String])] = [
        ("clock", []),
        ("face.smiling", Array("😀😃😄😁😆🥹😅😂🤣🥲☺️😊😇🙂🙃😉😌😍🥰😘😗😋😛😜🤪🤨🧐🤓😎🥸🤩🥳😏😒😞😔😟😕🙁😣😖😫😩🥺😢😭😤😠😡🤯😳🥵🥶😱😨😰😥😓🤗🤔🫣🤭🫢🤫😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕👋🤚🖐️✋🖖👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆👇☝️👍👎✊👊🤛🤜👏🙌🫶👐🤲🤝🙏💅💪👶🧒👦👧🧑👱👨🧔👩🧓👴👵👮🕵️💂👷🤴👸👳🧕🤵👰🤰🤱👼🎅🤶🦸🦹🧙🧚🧛🧜🧝🧞🧟💆💇🚶🧍🧎🏃💃🕺👯🧖🧗👫👭👬💏💑👪").map(String.init)),
        ("pawprint", Array("🐶🐱🐭🐹🐰🦊🐻🐼🐻‍❄️🐨🐯🦁🐮🐷🐸🐵🙈🙉🙊🐔🐧🐦🐤🦆🦅🦉🦇🐺🐗🐴🦄🐝🪱🐛🦋🐌🐞🐜🪰🐢🐍🦎🦖🦕🐙🦑🦐🦞🦀🐡🐠🐟🐬🐳🐋🦈🐊🐅🐆🦓🦍🦧🐘🦛🦏🐪🐫🦒🦘🐃🐂🐄🐎🐖🐏🐑🦙🐐🦌🐕🐩🐈🐓🦃🦚🦜🦢🦩🕊️🐇🦝🦨🦡🦫🦦🦥🐁🐀🐿️🦔🌵🎄🌲🌳🌴🪵🌱🌿☘️🍀🎍🪴🎋🍃🍂🍁🍄🐚🪨🌾💐🌷🌹🥀🌺🌸🌼🌻🌞🌝🌛🌜🌚🌕🌖🌗🌘🌑🌒🌓🌔🌙🌎🌍🌏🪐💫⭐️🌟✨⚡️☄️💥🔥🌪️🌈☀️🌤️⛅️🌥️☁️🌦️🌧️⛈️🌩️🌨️❄️☃️⛄️🌬️💨💧💦🌊").map(String.init)),
        ("fork.knife", Array("🍏🍎🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌶️🫑🌽🥕🧄🧅🥔🍠🥐🥯🍞🥖🥨🧀🥚🍳🧈🥞🧇🥓🥩🍗🍖🌭🍔🍟🍕🫓🥪🥙🧆🌮🌯🥗🥘🫕🥫🍝🍜🍲🍛🍣🍱🥟🍤🍙🍚🍘🍥🥠🥮🍢🍡🍧🍨🍦🥧🧁🍰🎂🍮🍭🍬🍫🍿🍩🍪🌰🥜🍯🥛🍼☕️🫖🍵🧃🥤🧋🍶🍺🍻🥂🍷🥃🍸🍹🧉🍾🧊🥄🍴🍽️🥣🥡🥢🧂").map(String.init)),
        ("figure.run", Array("⚽️🏀🏈⚾️🥎🎾🏐🏉🥏🎱🪀🏓🏸🏒🏑🥍🏏🪃🥅⛳️🪁🏹🎣🤿🥊🥋🎽🛹🛼🛷⛸️🥌🎿⛷️🏂🪂🏋️🤼🤸⛹️🤺🤾🏌️🏇🧘🏄🏊🤽🚣🧗🚵🚴🏆🥇🥈🥉🏅🎖️🏵️🎗️🎫🎟️🎪🤹🎭🩰🎨🎬🎤🎧🎼🎹🥁🪘🎷🎺🪗🎸🪕🎻🎲♟️🎯🎳🎮🎰🧩").map(String.init)),
        ("car", Array("🚗🚕🚙🚌🚎🏎️🚓🚑🚒🚐🛻🚚🚛🚜🦯🦽🦼🛴🚲🛵🏍️🛺🚨🚔🚍🚘🚖🚡🚠🚟🚃🚋🚞🚝🚄🚅🚈🚂🚆🚇🚊🚉✈️🛫🛬🛩️💺🛰️🚀🛸🚁🛶⛵️🚤🛥️🛳️⛴️🚢⚓️🪝⛽️🚧🚦🚥🚏🗺️🗿🗽🗼🏰🏯🏟️🎡🎢🎠⛲️⛱️🏖️🏝️🏜️🌋⛰️🏔️🗻🏕️⛺️🛖🏠🏡🏘️🏚️🏗️🏭🏢🏬🏣🏤🏥🏦🏨🏪🏫🏩💒🏛️⛪️🕌🕍🛕🕋⛩️🛤️🛣️🗾🎑🏞️🌅🌄🌠🎇🎆🌇🌆🏙️🌃🌌🌉🌁").map(String.init)),
        ("lightbulb", Array("⌚️📱📲💻⌨️🖥️🖨️🖱️🖲️🕹️🗜️💽💾💿📀📼📷📸📹🎥📽️🎞️📞☎️📟📠📺📻🎙️🎚️🎛️🧭⏱️⏲️⏰🕰️⌛️⏳📡🔋🔌💡🔦🕯️🪔🧯🛢️💸💵💴💶💷🪙💰💳💎⚖️🪜🧰🪛🔧🔨⚒️🛠️⛏️🪚🔩⚙️🪤🧱⛓️🧲🔫💣🧨🪓🔪🗡️⚔️🛡️🚬⚰️🪦⚱️🏺🔮📿🧿💈⚗️🔭🔬🕳️🩹🩺💊💉🩸🧬🦠🧫🧪🌡️🧹🪠🧺🧻🚽🚰🚿🛁🛀🧼🪥🪒🧽🪣🧴🛎️🔑🗝️🚪🪑🛋️🛏️🛌🧸🪆🖼️🪞🪟🛍️🛒🎁🎈🎏🎀🪄🪅🎊🎉🎎🏮🎐🧧✉️📩📨📧💌📥📤📦🏷️🪧📪📫📬📭📮📯📜📃📄📑🧾📊📈📉🗒️🗓️📆📅🗑️📇🗃️🗳️🗄️📋📁📂🗂️🗞️📰📓📔📒📕📗📘📙📚📖🔖🧷🔗📎🖇️📐📏🧮📌📍✂️🖊️🖋️✒️🖌️🖍️📝✏️🔍🔎🔏🔐🔒🔓").map(String.init)),
        ("heart", Array("❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝💟☮️✝️☪️🕉️☸️✡️🔯🕎☯️☦️🛐⛎♈️♉️♊️♋️♌️♍️♎️♏️♐️♑️♒️♓️🆔⚛️🉑☢️☣️📴📳🈶🈚️🈸🈺🈷️✴️🆚💮🉐㊙️㊗️🈴🈵🈹🈲🅰️🅱️🆎🆑🅾️🆘❌⭕️🛑⛔️📛🚫💯💢♨️🚷🚯🚳🚱🔞📵🚭❗️❕❓❔‼️⁉️🔅🔆〽️⚠️🚸🔱⚜️🔰♻️✅🈯️💹❇️✳️❎🌐💠Ⓜ️🌀💤🏧🚾♿️🅿️🛗🈳🈂️🛂🛃🛄🛅🚹🚺🚼⚧️🚻🚮🎦📶🈁🔣ℹ️🔤🔡🔠🆖🆗🆙🆒🆕🆓0️⃣1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟🔢#️⃣*️⃣⏏️▶️⏸️⏯️⏹️⏺️⏭️⏮️⏩⏪⏫⏬◀️🔼🔽➡️⬅️⬆️⬇️↗️↘️↙️↖️↕️↔️↪️↩️⤴️⤵️🔀🔁🔂🔄🔃🎵🎶➕➖➗✖️🟰♾️💲💱™️©️®️〰️➰➿🔚🔙🔛🔝🔜✔️☑️🔘🔴🟠🟡🟢🔵🟣⚫️⚪️🟤🔺🔻🔸🔹🔶🔷🔳🔲▪️▫️◾️◽️◼️◻️🟥🟧🟨🟩🟦🟪⬛️⬜️🟫🔈🔇🔉🔊🔔🔕📣📢💬💭🗯️♠️♣️♥️♦️🃏🎴🀄️🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛").map(String.init)),
        ("flag", Array("🏳️🏴🏁🚩🏳️‍🌈🏳️‍⚧️🇹🇷🇦🇿🇨🇾🇩🇪🇬🇧🇺🇸🇫🇷🇮🇹🇪🇸🇵🇹🇳🇱🇧🇪🇱🇺🇨🇭🇦🇹🇩🇰🇸🇪🇳🇴🇫🇮🇮🇸🇮🇪🇵🇱🇨🇿🇸🇰🇭🇺🇷🇴🇧🇬🇬🇷🇷🇸🇭🇷🇧🇦🇸🇮🇦🇱🇲🇰🇲🇪🇽🇰🇲🇩🇺🇦🇧🇾🇷🇺🇬🇪🇦🇲🇪🇪🇱🇻🇱🇹🇰🇿🇺🇿🇹🇲🇰🇬🇹🇯🇦🇫🇵🇰🇮🇳🇧🇩🇨🇳🇯🇵🇰🇷🇰🇵🇲🇳🇹🇼🇭🇰🇻🇳🇹🇭🇲🇾🇸🇬🇮🇩🇵🇭🇦🇺🇳🇿🇸🇦🇦🇪🇶🇦🇰🇼🇧🇭🇴🇲🇾🇪🇮🇶🇮🇷🇸🇾🇯🇴🇱🇧🇮🇱🇵🇸🇪🇬🇱🇾🇹🇳🇩🇿🇲🇦🇸🇩🇪🇹🇰🇪🇳🇬🇬🇭🇸🇳🇿🇦🇨🇦🇲🇽🇨🇺🇧🇷🇦🇷🇨🇱🇨🇴🇵🇪🇻🇪🇺🇾🇧🇴🇪🇨🇺🇳🇪🇺").map(String.init)),
    ]

    static var recents: [String] {
        get { Defaults.stringArray("sikEmoji") ?? Array("😂❤️👍🙏😊😍🎉🔥✨😭").map(String.init) }
        set { Defaults.set("sikEmoji", Array(newValue.prefix(24))) }
    }

    static func insert(_ e: String) {
        SystemControl.typeText(e)
        recents = [e] + recents.filter { $0 != e }
    }
}

/// A strip scrolled with the finger that glides with momentum on release and bounces at the edges (NSScrubber in the original).
final class ScrollState: ObservableObject {
    @Published var offset: CGFloat = 0
    var startOffset: CGFloat = 0
    var isDragging = false
    var contentWidth: CGFloat = 0
    var width: CGFloat = 0
    var selectedFrame: CGRect?

    /// No empty space when the content shrinks; the selected item (if any) stays visible.
    func clampOffset(animated: Bool = false) {
        guard !isDragging, width > 0 else { return }
        let minOffset = min(0, width - contentWidth)
        var x = min(0, max(minOffset, offset))
        if let r = selectedFrame {
            if r.maxX + x > width { x = width - r.maxX - 8 }
            if r.minX + x < 0 { x = -r.minX + 8 }
            x = min(0, max(minOffset, x))
        }
        guard x != offset else { return }
        if animated { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { offset = x } } else { offset = x }
    }
}

/// Frame of the selected item within the strip's content (reported with `.selectedInStrip()`).
struct SelectedFrameKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = value ?? nextValue() }
}

extension View {
    func selectedInStrip(_ isSelected: Bool) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: SelectedFrameKey.self, value: isSelected ? g.frame(in: .named("stripContent")) : nil)
        })
    }
}

struct ScrollingStrip<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @StateObject private var k = ScrollState()

    var body: some View {
        GeometryReader { g in
            let minOffset = min(0, g.size.width - k.contentWidth)
            HStack(spacing: Metrics.spacing) { content() }
                .fixedSize()
                .coordinateSpace(.named("stripContent"))
                .background(GeometryReader { ig in
                    Color.clear
                        .onAppear { k.contentWidth = ig.size.width; k.width = g.size.width; k.clampOffset() }
                        .onChange(of: ig.size.width) { _, w in k.contentWidth = w; k.clampOffset(animated: true) }
                        .onChange(of: g.size.width) { _, w in k.width = w; k.clampOffset(animated: true) }
                })
                .onPreferenceChange(SelectedFrameKey.self) { r in k.selectedFrame = r; k.clampOffset(animated: true) }
                .offset(x: k.offset)
                .frame(maxHeight: .infinity)
                .simultaneousGesture(DragGesture(minimumDistance: 6)
                    .onChanged { e in
                        if !k.isDragging { k.isDragging = true; k.startOffset = k.offset }
                        var x = k.startOffset + e.translation.width
                        // rubber-band resistance at the edges
                        if x > 0 { x = x / 3 } else if x < minOffset { x = minOffset + (x - minOffset) / 3 }
                        k.offset = x
                    }
                    .onEnded { e in
                        k.isDragging = false
                        let target = min(0, max(minOffset, k.startOffset + e.predictedEndTranslation.width))
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { k.offset = target }
                    })
        }
        .clipShape(Capsule())
    }
}
