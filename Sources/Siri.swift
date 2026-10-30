import SwiftUI

// iOS 27 Siri'si: kenar ışıltısı yok; koyu Liquid Glass bir küre süzülüp gelir, hafifçe nabız gibi atar,
// içinde Siri'nin eski renklerini taşıyan tek öğe olan dalga sesle oynar. Renkler WWDC26'nın yumuşak
// pembe, koyu mavi, mor ve turuncusu.
enum SiriRenk {
    static let pembe = Color(hex: 0xE98DBF)
    static let lacivert = Color(hex: 0x3D5AD6)
    static let mor = Color(hex: 0x8C6FE8)
    static let turuncu = Color(hex: 0xF0A066)
    static let hepsi = [pembe, lacivert, mor, turuncu]
    static let cam = Color(hex: 0x10132A)
}

/// Control Strip'teki Siri logosu: koyu cam bir kürenin içinde yavaşça dönen, birbirine karışan
/// pembe, mavi, mor ve turuncu ışık kurdeleleri; ortada beyaz bir öz, üstte cam parlaması.
struct SiriKure: View {
    var aktif = false
    var boyut: CGFloat = 21

    private static let kurdeleler: [KurdeleGorunum.Kurdele] = [
        .init(renk: NSColor(srgbRed: 1, green: 0.37, blue: 0.66, alpha: 1), x: -0.16, y: -0.12, w: 0.62, h: 0.34, aci: 25),
        .init(renk: NSColor(srgbRed: 0.25, green: 0.49, blue: 1, alpha: 1), x: 0.16, y: -0.04, w: 0.6, h: 0.32, aci: -40),
        .init(renk: NSColor(srgbRed: 0.6, green: 0.36, blue: 1, alpha: 1), x: 0.02, y: 0.16, w: 0.64, h: 0.3, aci: 10),
        .init(renk: NSColor(srgbRed: 1, green: 0.6, blue: 0.3, alpha: 1), x: -0.12, y: 0.12, w: 0.42, h: 0.24, aci: 70),
    ]

    var body: some View {
        let b = boyut
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0x1A1F45), Color(hex: 0x05060F)],
                                         center: .center, startRadius: 0, endRadius: b * 0.55))
            KurdeleKatmani(kurdeleler: SiriKure.kurdeleler)
                .blendMode(.plusLighter)
            // parlak öz
            Circle().fill(RadialGradient(colors: [.white.opacity(aktif ? 0.75 : 0.5), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: b * 0.24))
                .blendMode(.plusLighter)
            // cam kenar ve parlama
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04), .white.opacity(0.22)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: b * 0.55, height: b * 0.28)
                .offset(y: -b * 0.26)
        }
        .frame(width: b, height: b)
        .clipShape(Circle())
        .shadow(color: Color(hex: 0x9A5CFF).opacity(aktif ? 0.75 : 0.35), radius: aktif ? 6 : 3)
    }
}

/// Dinlerken uygulama alanının ortasında yüzen hap, Apple'ın yeni Siri'si gibi: Dynamic Island'dan akan berrak bir
/// Liquid Glass damlası. Arkasındaki çubuğu büyüterek kırar (macOS 26'da gerçek cam), kenarı koyu kırılma halkası ve
/// parlak iç çizgiyle cam gibi durur; ortasında renkli Siri çizgileri akar. Konuştukça çizgiler yükselir ve damla
/// jöle gibi hafifçe şişer.
struct SiriHap: View {
    @ObservedObject private var mikrofon = Mikrofon.ortak
    @StateObject private var yumusak = Yumusatici()

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let hedef = mikrofon.calisiyor ? mikrofon.seviye : 0.2 + 0.12 * sin(t * 1.6)
            // mikrofon değeri kesik kesik gelir; her karede yumuşatılır ki çizgiler titremesin
            let ses = yumusak.ilerle(hedef, t)
            ZStack {
                CamDamla()
                SiriDalga(t: t, ses: ses)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.2),
                                                 .init(color: .white, location: 0.8), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .padding(.horizontal, 14).padding(.vertical, 2)
                // kırılma halkası: camın kenarı arkadakini kırdığı için koyulaşır
                Capsule().strokeBorder(.black.opacity(0.45), lineWidth: 3).blur(radius: 1.5).clipShape(Capsule())
                // parlak iç çizgi: üstte ve altta ışığı yakalar
                Capsule().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.85), location: 0),
                                                              .init(color: .white.opacity(0.12), location: 0.45),
                                                              .init(color: .white.opacity(0.5), location: 1)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.9)
                    .padding(1.2)
                // üst sol speküler parlama
                Ellipse().fill(.white.opacity(0.35)).frame(width: 70, height: 6).blur(radius: 3)
                    .offset(x: -80, y: -7)
            }
            .frame(width: 300, height: Olcu.tus)
            .scaleEffect(x: 1 + 0.035 * ses, y: 1 + 0.07 * ses)
            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
        }
    }
}

/// Kare kare yumuşatma: hedefe kare süresine göre üstel yaklaşır (yükselirken hızlı, inerken yavaş).
final class Yumusatici: ObservableObject {
    private var deger = 0.0
    private var son = 0.0

    func ilerle(_ hedef: Double, _ t: Double) -> Double {
        let dt = son == 0 ? 0 : min(0.1, max(0, t - son))
        son = t
        let k = hedef > deger ? 9.0 : 3.5
        deger += (hedef - deger) * (1 - exp(-k * dt))
        return deger
    }
}

/// Damlanın ortasındaki Siri çizgileri: görseldeki renklerde, uçlara doğru incelen, yavaşça akan ince dalgalar.
/// Sessizken neredeyse düz; konuştukça her renk biraz farklı yükselir.
struct SiriDalga: View {
    let t: Double
    let ses: Double

    private static let renkler: [Color] = [Color(hex: 0xFF6A3D), Color(hex: 0x3D8BFF), Color(hex: 0x9B5CFF),
                                           Color(hex: 0x34D399), .white]

    var body: some View {
        Canvas { ctx, boyut in
            let yollar = SiriDalga.renkler.indices.map { yol(i: $0, boyut: boyut) }
            ctx.blendMode = .plusLighter
            ctx.drawLayer { k in
                k.addFilter(.blur(radius: 2.5))
                for (i, p) in yollar.enumerated() { k.stroke(p, with: .color(SiriDalga.renkler[i].opacity(0.75)), lineWidth: 2.6) }
            }
            for (i, p) in yollar.enumerated() {
                ctx.stroke(p, with: .color(SiriDalga.renkler[i].opacity(i == 4 ? 0.7 : 1)), lineWidth: i == 4 ? 0.8 : 1.2)
            }
        }
    }

    private func yol(i: Int, boyut: CGSize) -> Path {
        let d = Double(i)
        // her çizgi kendi yavaş ritmiyle; sesle hepsi yükselir
        let ritim = 0.55 + 0.45 * sin(t * (0.9 + 0.17 * d) + d * 1.7)
        let genlik = boyut.height * 0.42 * (0.05 + 0.95 * ses) * ritim
        let siklik = 1.1 + d * 0.35, faz = t * (1.6 + d * 0.35) + d
        var p = Path()
        for x in stride(from: 0.0, through: boyut.width, by: 1) {
            let zarf = pow(sin(.pi * x / boyut.width), 2.2)
            let y = boyut.height / 2 + sin(x / boyut.width * .pi * 2 * siklik + faz) * genlik * zarf
            x == 0 ? p.move(to: .init(x: x, y: y)) : p.addLine(to: .init(x: x, y: y))
        }
        return p
    }
}

/// Damlanın camı: macOS 26'da Apple'ın gerçek Liquid Glass'ı (arkasını büyütüp kırar), öncesinde hafif buzlu cam.
struct CamDamla: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(.white.opacity(0.04)))
        }
    }
}

/// Kürenin damla gibi sağdaki Siri tuşundan süzülüp gelmesi.
struct Damla: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 0.06 + 0.94 * p, y: 0.7 + 0.3 * p, anchor: .trailing)
            .offset(x: (1 - p) * 220)
            .blur(radius: (1 - p) * 5)
            .opacity(min(1, p * 1.6))
    }
}

extension AnyTransition {
    static var damla: AnyTransition { .modifier(active: Damla(p: 0), identity: Damla(p: 1)) }
}
