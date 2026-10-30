import AppKit
import SwiftUI

// Yazma önerileri (QuickType) ve emoji şeridi.

/// Odaktaki yazı alanında imlecin önündeki metin (Erişilebilirlik ile okunur).
struct YaziBaglami: Equatable {
    var metin: String
    var imlec: Int

    /// Arka kuyrukta çağrılır. Yazı alanı odakta değilse nil.
    static func oku() -> YaziBaglami? {
        let sistem = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sistem, 0.25)
        var odak: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sistem, kAXFocusedUIElementAttribute as CFString, &odak) == .success,
              let odak, CFGetTypeID(odak) == AXUIElementGetTypeID() else { return nil }
        let o = odak as! AXUIElement
        var deger: CFTypeRef?, aralik: CFTypeRef?
        AXUIElementCopyAttributeValue(o, kAXValueAttribute as CFString, &deger)
        AXUIElementCopyAttributeValue(o, kAXSelectedTextRangeAttribute as CFString, &aralik)
        guard let metin = deger as? String, let aralik, CFGetTypeID(aralik) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        guard AXValueGetValue(aralik as! AXValue, .cfRange, &r), r.length == 0 else { return nil }
        let ns = metin as NSString
        guard r.location >= 0, r.location <= ns.length else { return nil }
        // tahmin için imlecin önündeki son birkaç yüz karakter yeter
        let bas = max(0, r.location - 300)
        return YaziBaglami(metin: ns.substring(with: NSRange(location: bas, length: r.location - bas)), imlec: r.location - bas)
    }
}

/// Orijinaldeki gibi üç kutu: yarım kelime varken ilki yazılanın kendisi (tırnak içinde), diğerleri
/// tamamlama; yokken üçü de sonraki kelime tahmini. Yanlış yazılmışsa ilk tamamlama mavi (düzeltme).
struct Oneriler: Equatable {
    var aktif = false
    var yarim = ""
    var silinecek = 0
    var kelimeler: [String] = []
    var duzeltme = false

    /// macOS'un Touch Bar için kullandığı aday sistemi (NSSpellChecker); ana iş parçacığında çağrılır.
    static func iste(_ b: YaziBaglami, _ tamam: @escaping (Oneriler) -> Void) {
        let denetci = NSSpellChecker.shared
        let ns = b.metin as NSString
        denetci.requestCandidates(forSelectedRange: NSRange(location: b.imlec, length: 0), in: b.metin,
                                  types: NSTextCheckingAllSystemTypes, options: nil, inSpellDocumentWithTag: 0) { _, sonuc in
            let aralik = sonuc.first?.range ?? NSRange(location: b.imlec, length: 0)
            let yarim = aralik.length > 0 && NSMaxRange(aralik) <= ns.length ? ns.substring(with: aralik) : ""
            var gorulen = Set<String>([yarim.lowercased()])
            var kelimeler: [String] = []
            for r in sonuc {
                guard let k = r.replacementString?.trimmingCharacters(in: .whitespaces), !k.isEmpty,
                      gorulen.insert(k.lowercased()).inserted else { continue }
                kelimeler.append(k)
            }
            let yanlis = yarim.count > 2 && denetci.checkSpelling(of: yarim, startingAt: 0).location != NSNotFound
            let o = Oneriler(aktif: true, yarim: yarim, silinecek: yarim.count,
                             kelimeler: Array(kelimeler.prefix(yarim.isEmpty ? 3 : 2)),
                             duzeltme: yanlis && !kelimeler.isEmpty)
            DispatchQueue.main.async { tamam(o) }
        }
    }

    /// Yarım kelimeyi siler, seçilen kelimeyi ve bir boşluk yazar.
    func sec(_ kelime: String) {
        for _ in 0..<silinecek { Sistem.tus(51) }
        Sistem.yaz(kelime + " ")
    }
}

enum Emoji {
    /// Orijinal emoji seçicinin kategorileri ve sırası: Sık Kullanılanlar, Suratlar ve İnsanlar, Hayvanlar ve Doğa,
    /// Yiyecek ve İçecek, Etkinlik, Seyahat ve Yerler, Nesneler, Semboller, Bayraklar.
    static let kategoriler: [(simge: String, emojiler: [String])] = [
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

    static var sik: [String] {
        get { Kayit.dizi("sikEmoji") ?? Array("😂❤️👍🙏😊😍🎉🔥✨😭").map(String.init) }
        set { Kayit.yaz("sikEmoji", Array(newValue.prefix(24))) }
    }

    static func kullan(_ e: String) {
        Sistem.yaz(e)
        sik = [e] + sik.filter { $0 != e }
    }
}

/// Parmakla kaydırılan, bırakınca momentumla süzülüp kenarda yaylanan şerit (orijinaldeki NSScrubber).
final class Kaydirma: ObservableObject {
    @Published var ofset: CGFloat = 0
    var baslangic: CGFloat = 0
    var surukleniyor = false
    var icerik: CGFloat = 0
    var genislik: CGFloat = 0
    var secili: CGRect?

    /// İçerik daralınca boşluk kalmasın; seçili öğe (varsa) görünür olsun.
    func yerlestir(animasyon: Bool = false) {
        guard !surukleniyor, genislik > 0 else { return }
        let enAz = min(0, genislik - icerik)
        var x = min(0, max(enAz, ofset))
        if let r = secili {
            if r.maxX + x > genislik { x = genislik - r.maxX - 8 }
            if r.minX + x < 0 { x = -r.minX + 8 }
            x = min(0, max(enAz, x))
        }
        guard x != ofset else { return }
        if animasyon { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { ofset = x } } else { ofset = x }
    }
}

/// Şeritteki seçili öğenin içerikteki yeri (`.seritteSecili()` ile bildirilir).
struct SeciliKonum: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = value ?? nextValue() }
}

extension View {
    func seritteSecili(_ secili: Bool) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: SeciliKonum.self, value: secili ? g.frame(in: .named("seritIcerik")) : nil)
        })
    }
}

struct KaydirmaSeridi<Icerik: View>: View {
    @ViewBuilder var icerik: () -> Icerik
    @StateObject private var k = Kaydirma()

    var body: some View {
        GeometryReader { g in
            let enAz = min(0, g.size.width - k.icerik)
            HStack(spacing: Olcu.ara) { icerik() }
                .fixedSize()
                .coordinateSpace(.named("seritIcerik"))
                .background(GeometryReader { ig in
                    Color.clear
                        .onAppear { k.icerik = ig.size.width; k.genislik = g.size.width; k.yerlestir() }
                        .onChange(of: ig.size.width) { _, w in k.icerik = w; k.yerlestir(animasyon: true) }
                        .onChange(of: g.size.width) { _, w in k.genislik = w; k.yerlestir(animasyon: true) }
                })
                .onPreferenceChange(SeciliKonum.self) { r in k.secili = r; k.yerlestir(animasyon: true) }
                .offset(x: k.ofset)
                .frame(maxHeight: .infinity)
                .simultaneousGesture(DragGesture(minimumDistance: 6)
                    .onChanged { e in
                        if !k.surukleniyor { k.surukleniyor = true; k.baslangic = k.ofset }
                        var x = k.baslangic + e.translation.width
                        // kenarlarda lastik gibi direnç
                        if x > 0 { x = x / 3 } else if x < enAz { x = enAz + (x - enAz) / 3 }
                        k.ofset = x
                    }
                    .onEnded { e in
                        k.surukleniyor = false
                        let hedef = min(0, max(enAz, k.baslangic + e.predictedEndTranslation.width))
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { k.ofset = hedef }
                    })
        }
        .clipShape(Capsule())
    }
}
