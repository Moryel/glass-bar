import SwiftUI

// Liquid Glass parçaları: cam kapsül zemini, sıvı basma davranışı, tuş grubu, mercek topuzlu kaydırıcı.
extension Color {
    init(hex: UInt32, _ o: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: o)
    }
}

enum Olcu {
    static let yukseklik: CGFloat = 30
    static let tus: CGFloat = 26
    static let ara: CGFloat = 4
    static let simge: CGFloat = 40
    static let dar: CGFloat = 32
    static let esc: CGFloat = 64
}

/// Görünüm teması (menüde "Tema"). Klasik: belirgin cam, parlak şerit, ışık halkası.
/// Sade: macOS 26'ya yakın Liquid Glass; kenarda kırılan ışık, kenara doğru kalınlaşan cam, halka yok. Ortam ışığı temadan ayrı bir seçenek.
enum Tema: String, CaseIterable {
    case klasik, sade

    var ad: String { L(adTr) }

    private var adTr: String {
        switch self {
        case .klasik: "Klasik"
        case .sade: "Sade Liquid Glass"
        }
    }
}

private struct TemaAnahtari: EnvironmentKey {
    static let defaultValue = Tema.klasik
}

extension EnvironmentValues {
    var tema: Tema {
        get { self[TemaAnahtari.self] }
        set { self[TemaAnahtari.self] = newValue }
    }
}

enum Yay {
    /// basınca: hızlı, biraz taşan
    static let bas = Animation.spring(response: 0.3, dampingFraction: 0.58)
    /// bırakınca: yaylanarak, salınımla geri gelir
    static let birak = Animation.spring(response: 0.48, dampingFraction: 0.42)
    /// sade temada daha az taşan yaylar
    static let sadeBas = Animation.spring(response: 0.24, dampingFraction: 0.66)
    static let sadeBirak = Animation.spring(response: 0.5, dampingFraction: 0.58)

    static func bas(_ t: Tema) -> Animation { t == .sade ? sadeBas : bas }
    static func birak(_ t: Tema) -> Animation { t == .sade ? sadeBirak : birak }
    /// parmağı takip ederken
    static let takip = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.7)
}

/// Bir tuşa dokunuşun anlık durumu (SwiftUI @State bu araç zincirinde makro olduğu için sınıf).
final class Basma: ObservableObject {
    @Published var basili = false
    @Published var konum: CGPoint = .zero
    @Published var cekme: CGSize = .zero
    @Published var dalga: CGFloat = 1
    @Published var parilti: Double = 0
    var boyut: CGSize = .zero
    var cerceve: CGRect = .zero
    /// basılı tutup kaydırma sürüyor
    var kayiyor = false
}

/// Dokunulan yerde camın arkasındaki ortam ışığı da yanar.
final class Isik: ObservableObject {
    static let ortak = Isik()
    @Published var konum: CGPoint = .zero
    @Published var guc: Double = 0
}

/// Cam zemin. `b` verilirse dokunuşa tepki verir: parmağın altında ışık, yayılan halka, parlayan kenar.
struct CamZemin: View {
    var vurgu: Color? = nil
    @ObservedObject var b: Basma = Basma()
    @Environment(\.tema) private var tema

    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width), h = max(1, g.size.height)
            let merkez = UnitPoint(x: b.konum.x / w, y: b.konum.y / h)
            if tema == .sade { sade(merkez) } else { klasik(w: w, merkez: merkez) }
        }
    }

    /// Sade Liquid Glass: ortası berrak, kenara doğru kalınlaşan cam; kenarda üstte parlak, altta yansıyan ışık.
    private func sade(_ merkez: UnitPoint) -> some View {
        let p = b.parilti
        return ZStack {
            Capsule().fill(EllipticalGradient(stops: [.init(color: .white.opacity(0.07 - 0.03 * p), location: 0.55),
                                                      .init(color: .white.opacity(0.16 + 0.06 * p), location: 1)]))
            if let vurgu {
                Capsule().fill(EllipticalGradient(stops: [.init(color: vurgu.opacity(0.82), location: 0.55),
                                                          .init(color: vurgu.opacity(0.95), location: 1)]))
            }
            // camın kalınlığı
            Capsule().strokeBorder(.white.opacity(0.06 + 0.1 * p), lineWidth: 2).blur(radius: 1.5).clipShape(Capsule())
            // parmağın altından yayılan ışık
            Capsule()
                .fill(RadialGradient(colors: [.white.opacity(0.32 * p), .white.opacity(0.08 * p), .clear],
                                     center: merkez, startRadius: 0, endRadius: 30))
                .blendMode(.plusLighter)
            // kırılan kenar
            Capsule().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.55 + 0.35 * p), location: 0),
                                                          .init(color: .white.opacity(0.10 + 0.15 * p), location: 0.38),
                                                          .init(color: .white.opacity(0.06 + 0.12 * p), location: 0.62),
                                                          .init(color: .white.opacity(0.30 + 0.3 * p), location: 1)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 0.5)
    }

    private func klasik(w: CGFloat, merkez: UnitPoint) -> some View {
            ZStack {
                Capsule().fill(LinearGradient(colors: [.white.opacity(b.basili ? 0.26 : 0.18), .white.opacity(b.basili ? 0.1 : 0.05),
                                                       .white.opacity(b.basili ? 0.16 : 0.10)],
                                              startPoint: .top, endPoint: .bottom))
                if let vurgu {
                    Capsule().fill(LinearGradient(colors: [vurgu.opacity(0.85), vurgu.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                }
                // üst kenardaki parlama
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                    .padding(.horizontal, 4).padding(.top, 0.8).padding(.bottom, 11)
                // parmağın altındaki ışık
                Capsule()
                    .fill(RadialGradient(colors: [.white.opacity(0.75 * b.parilti), .white.opacity(0.18 * b.parilti), .clear],
                                         center: merkez, startRadius: 0, endRadius: 14 + 26 * b.parilti))
                    .blendMode(.plusLighter)
                // dokunuşta yayılan ışık halkası
                Circle()
                    .strokeBorder(.white.opacity(0.7 * (1 - b.dalga)), lineWidth: 2.5)
                    .blur(radius: 1.5)
                    .frame(width: 8 + w * 1.6 * b.dalga, height: 8 + w * 1.6 * b.dalga)
                    .position(b.konum)
                    .blendMode(.plusLighter)
                    .clipShape(Capsule())
                // kenar: basılıyken ışığı yakalar
                Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.42 + 0.45 * b.parilti), .white.opacity(0.08 + 0.3 * b.parilti),
                                                               .white.opacity(0.2 + 0.4 * b.parilti)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.7 + 0.4 * b.parilti)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.55), radius: 2.5, y: 1)
            .shadow(color: .white.opacity(0.35 * b.parilti), radius: 6)
    }
}

/// Sıvı cam basma davranışı: dokununca tuş büyür ve ışır, parmağı esneyerek takip eder,
/// bırakınca yaylanıp salınarak yerine oturur; parmak tuşun üstünde kalkarsa eylem çalışır.
struct SiviBasma: ViewModifier {
    enum Tur { case kapsul, kabarcik }
    var tur: Tur = .kapsul
    var vurgu: Color? = nil
    /// şeritteki öğe: esnemez, parmak kayarsa eylem çalışmaz
    var kaydirilabilir = false
    /// basılı tutup yana kaydırınca (parlaklık/ses gibi) yatay yer değiştirmeyle çağrılır
    var kaydir: ((CGFloat) -> Void)? = nil
    var kaydirBitti: (() -> Void)? = nil
    /// gruptaki konum: ilk/son öğenin vurgusu kapsülün yuvarlak ucuna uyar
    var solUc = false
    var sagUc = false
    let eylem: () -> Void
    @StateObject private var b = Basma()
    @Environment(\.tema) private var tema

    func body(content: Content) -> some View {
        let tx = b.cekme.width, ty = b.cekme.height
        let esne = abs(tanh(tx / 60))
        let sade = tema == .sade
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity)
            .background {
                switch tur {
                case .kapsul:
                    CamZemin(vurgu: vurgu, b: b)
                case .kabarcik:
                    ZStack {
                        if let vurgu {
                            let r = Olcu.tus / 2
                            UnevenRoundedRectangle(topLeadingRadius: solUc ? r : 0, bottomLeadingRadius: solUc ? r : 0,
                                                   bottomTrailingRadius: sagUc ? r : 0, topTrailingRadius: sagUc ? r : 0)
                                .fill(vurgu.opacity(0.7))
                        }
                        // grubun içinden kabarıp çıkan cam damla
                        CamZemin(b: b)
                            .padding(.horizontal, sade ? -2 : -3).padding(.vertical, -1)
                            .scaleEffect(b.basili ? 1 : (sade ? 0.82 : 0.6))
                            .opacity(b.basili ? 1 : 0)
                    }
                }
            }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear {
                        b.boyut = g.size
                        b.cerceve = g.frame(in: .named("cubuk"))
                        // ekran görüntüsü denemesi: -tb2basili YES → tuşlar basılı görünür
                        if UserDefaults.standard.bool(forKey: "tb2basili") {
                            b.basili = true; b.parilti = 1; b.dalga = 0.45
                            b.konum = CGPoint(x: g.size.width * 0.35, y: g.size.height * 0.4)
                        }
                    }
                    .onChange(of: g.frame(in: .named("cubuk"))) { _, c in b.boyut = c.size; b.cerceve = c }
            })
            .contentShape(Rectangle())
            .scaleEffect(b.basili ? (tur == .kapsul ? (sade ? 1.08 : 1.1) : (sade ? 1.05 : 1.04)) : 1)
            .scaleEffect(x: 1 + (sade ? 0.06 : 0.12) * esne, y: 1 - (sade ? 0.035 : 0.07) * esne)
            .offset(x: (sade ? 4 : 7) * tanh(tx / 45), y: (sade ? 1 : 2) * tanh(ty / 25))
            .animation(Yay.takip, value: b.cekme)
            .animation(b.basili ? Yay.bas(tema) : Yay.birak(tema), value: b.basili)
            .zIndex(b.basili ? 1 : 0)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    if !b.basili {
                        b.basili = true
                        b.dalga = 0
                        withAnimation(.easeOut(duration: 0.6)) { b.dalga = 1 }
                        withAnimation(.easeOut(duration: 0.12)) { b.parilti = 1 }
                        Isik.ortak.konum = CGPoint(x: b.cerceve.minX + e.location.x, y: b.cerceve.midY)
                        withAnimation(.easeOut(duration: 0.18)) { Isik.ortak.guc = 1 }
                    }
                    b.konum = e.location
                    if let kaydir, b.kayiyor || abs(e.translation.width) > 6 {
                        b.kayiyor = true
                        b.cekme = .zero
                        kaydir(e.translation.width)
                    } else if !kaydirilabilir {
                        b.cekme = e.translation
                    }
                    withAnimation(Yay.takip) { Isik.ortak.konum.x = b.cerceve.minX + e.location.x }
                }
                .onEnded { e in
                    var icinde = CGRect(origin: .zero, size: b.boyut).insetBy(dx: -14, dy: -24).contains(e.location)
                    if kaydirilabilir && abs(e.translation.width) > 8 { icinde = false }
                    if b.kayiyor { b.kayiyor = false; kaydirBitti?(); icinde = false }
                    b.basili = false
                    b.cekme = .zero
                    withAnimation(.easeOut(duration: 0.55)) { b.parilti = 0 }
                    withAnimation(.easeOut(duration: 0.7)) { Isik.ortak.guc = 0 }
                    if icinde { eylem() }
                })
    }
}

/// Tek satırlık düğme yazısı. Touch Bar'da Text kendi ölçtüğü genişliğe sığmayıp sonunu kesiyor ("Tod…");
/// genişlik AppKit'le ölçülüp biraz payla verilir.
struct Yazi: View {
    let metin: String
    var boyut: CGFloat = 13
    var kalinlik: NSFont.Weight = .medium
    init(_ metin: String, boyut: CGFloat = 13, kalinlik: NSFont.Weight = .medium) {
        self.metin = L(metin); self.boyut = boyut; self.kalinlik = kalinlik
    }
    var body: some View {
        let w = (metin as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: boyut, weight: kalinlik)]).width
        Text(metin).font(.system(size: boyut, weight: Font.Weight(kalinlik))).lineLimit(1).frame(width: ceil(w) + 6)
    }
}

extension Font.Weight {
    init(_ w: NSFont.Weight) {
        switch w {
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .regular: self = .regular
        default: self = .medium
        }
    }
}

struct Tus<Etiket: View>: View {
    var genislik: CGFloat? = Olcu.simge
    var vurgu: Color? = nil
    let eylem: () -> Void
    @ViewBuilder var etiket: () -> Etiket
    var kaydirilabilir = false
    var kaydir: ((CGFloat) -> Void)? = nil
    var kaydirBitti: (() -> Void)? = nil

    var body: some View {
        etiket()
            .padding(.horizontal, genislik == nil ? 12 : 0)
            .frame(width: genislik)
            .frame(height: Olcu.tus)
            .modifier(SiviBasma(vurgu: vurgu, kaydirilabilir: kaydirilabilir, kaydir: kaydir, kaydirBitti: kaydirBitti, eylem: eylem))
            .frame(height: Olcu.tus)
    }

    /// Basılı tutup kaydırınca değer değişsin (orijinaldeki parlaklık/ses davranışı).
    func kaydirinca(_ k: @escaping (CGFloat) -> Void, bitince: @escaping () -> Void) -> Tus {
        var t = self
        t.kaydir = k
        t.kaydirBitti = bitince
        return t
    }

    /// Kaydırılan şeritte durur; parmak kayarsa basılmış sayılmaz.
    func seritte() -> Tus {
        var t = self
        t.kaydirilabilir = true
        return t
    }
}

extension Tus where Etiket == Image {
    init(_ simge: String, genislik: CGFloat? = Olcu.simge, vurgu: Color? = nil, eylem: @escaping () -> Void) {
        self.genislik = genislik
        self.vurgu = vurgu
        self.eylem = eylem
        self.etiket = { Image(systemName: simge) }
    }
}

struct GrupTus: Identifiable {
    let id = UUID()
    var simge: String? = nil
    var yazi: String? = nil
    var nokta: Color? = nil
    var vurgu: Color? = nil
    let eylem: () -> Void
}

struct Grup: View {
    let tuslar: [GrupTus]
    var tusGenisligi: CGFloat? = nil
    /// verilirse grubun camı bu renge boyanır (yazma önerileri orijinalde koyu mavi-gri)
    var zemin: Color? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tuslar.enumerated()), id: \.offset) { i, t in
                if i > 0 { Rectangle().fill(.white.opacity(0.13)).frame(width: 0.6).padding(.vertical, 5) }
                Group {
                    if let n = t.nokta {
                        Circle().fill(n).frame(width: 13, height: 13)
                            .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                                  startPoint: .top, endPoint: .center)))
                    } else if let s = t.simge { Image(systemName: s) } else { Text(L(t.yazi ?? "")).lineLimit(1) }
                }
                .frame(maxWidth: tusGenisligi == nil ? .infinity : nil)
                .frame(width: tusGenisligi)
                .modifier(SiviBasma(tur: .kabarcik, vurgu: t.vurgu, solUc: i == 0, sagUc: i == tuslar.count - 1, eylem: t.eylem))
            }
        }
        .frame(height: Olcu.tus)
        .background(CamZemin(vurgu: zemin).clipShape(Capsule()))
    }
}

/// Kaydırıcı; topuz sürüklenirken iOS 26'daki gibi şeffaf bir cam merceğe dönüşür.
struct CamKaydirici: View {
    @Binding var deger: Float
    var ince = false
    /// verilirse dolu kısım bu renkte (orijinal parlaklık/ses kaydırıcısındaki mavi)
    var dolgu: Color? = nil
    var degisti: (Float) -> Void = { _ in }
    @StateObject private var b = Basma()
    @Environment(\.tema) private var tema

    var body: some View {
        if tema == .sade { sade } else { klasik }
    }

    /// Sade tema: dururken beyaz kapsül topuz; sürüklerken altındaki rayı büyüten berrak bir merceğe döner.
    private var sade: some View {
        GeometryReader { g in
            let w = max(1, g.size.width), v = CGFloat(deger)
            let topuz: CGSize = ince ? .init(width: 12, height: 12) : .init(width: 30, height: 20)
            let ray: CGFloat = 4
            let mercek = b.basili
            let x = min(max(0, w * v - topuz.width / 2), w - topuz.width)
            let renk = dolgu ?? .white
            let rayGorunum = ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: ray)
                Capsule().fill(renk).frame(width: max(ray, w * v), height: ray)
            }
            ZStack(alignment: .leading) {
                rayGorunum
                ZStack {
                    Capsule().fill(mercek ? Color.white.opacity(0.06) : Color(hex: 0xF2F2F7))
                    if mercek {
                        // mercek: topuzun altındaki ray %30 büyük görünür
                        rayGorunum
                            .frame(width: w, height: topuz.height)
                            .scaleEffect(1.3, anchor: UnitPoint(x: (x + topuz.width / 2) / w, y: 0.5))
                            .offset(x: -x)
                            .frame(width: topuz.width, height: topuz.height, alignment: .leading)
                            .clipShape(Capsule())
                        Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 2).blur(radius: 1.5).clipShape(Capsule())
                        Capsule().strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.85), location: 0),
                                                                      .init(color: .white.opacity(0.25), location: 0.4),
                                                                      .init(color: .white.opacity(0.4), location: 1)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                    }
                }
                .frame(width: topuz.width, height: topuz.height)
                .shadow(color: .black.opacity(mercek ? 0.4 : 0.55), radius: mercek ? 1.5 : 1, y: 0.5)
                .scaleEffect(x: mercek ? 1.32 : 1, y: mercek ? 1.22 : 1)
                .offset(x: x)
                .animation(mercek ? Yay.sadeBas : Yay.sadeBirak, value: mercek)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(surukle(w))
        }
        .frame(height: Olcu.tus)
    }

    private func surukle(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { e in
                if !b.basili { b.basili = true }
                withAnimation(Yay.takip) { deger = Float(min(1, max(0, e.location.x / max(1, w)))) }
                degisti(deger)
            }
            .onEnded { _ in b.basili = false }
    }

    private var klasik: some View {
        GeometryReader { g in
            let w = g.size.width, v = CGFloat(deger)
            let topuz: CGSize = ince ? .init(width: 12, height: 12) : .init(width: 34, height: 22)
            let ray: CGFloat = ince ? 4 : 6
            let mercek = b.basili
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13)).frame(height: ray)
                    .overlay(Capsule().stroke(.black.opacity(0.5), lineWidth: 0.5))
                Capsule().fill(LinearGradient(colors: dolgu.map { [$0.opacity(0.8), $0] } ?? [.white.opacity(0.55), .white],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(ray, w * v), height: ray)
                ZStack {
                    Capsule().fill(LinearGradient(colors: [.white.opacity(mercek ? 0.12 : 0.55), .white.opacity(mercek ? 0.03 : 0.2)],
                                                  startPoint: .top, endPoint: .bottom))
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(mercek ? 0.5 : 0.2), .clear], startPoint: .top, endPoint: .center))
                        .padding(.horizontal, 3).padding(.top, 0.8).padding(.bottom, topuz.height * 0.45)
                    Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(mercek ? 0.25 : 0.5), .white.opacity(0.7)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: mercek ? 1.1 : 0.7)
                }
                .frame(width: topuz.width, height: topuz.height)
                .shadow(color: .black.opacity(mercek ? 0.35 : 0.6), radius: 3, y: 1)
                .shadow(color: .white.opacity(mercek ? 0.35 : 0), radius: 6)
                .scaleEffect(x: mercek ? 1.3 : 1, y: mercek ? 1.18 : 1)
                .offset(x: min(max(0, w * v - topuz.width / 2), w - topuz.width))
                .animation(mercek ? Yay.bas : Yay.birak, value: mercek)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(surukle(w))
        }
        .frame(height: Olcu.tus)
    }
}

/// Panel değişiminde büyüyüp netleşme.
struct Netles: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content.scaleEffect(0.92 + 0.08 * p).blur(radius: (1 - p) * 2.5).opacity(p)
    }
}

extension AnyTransition {
    static var netles: AnyTransition { .modifier(active: Netles(p: 0), identity: Netles(p: 1)) }
}
