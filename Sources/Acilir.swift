import SwiftUI

// Açılır çubuk (orijinaldeki popover): tuşa dokununca ya da basılı tutup kaydırınca kendi çubuğunu
// diğer öğelerin üstüne açar. Basılı tut + kaydır + bırak tek harekette seçim yapar.
struct AcilirOge {
    var simge: String? = nil
    var yazi: String? = nil
    var nokta: Color? = nil
    var secili = false
    let eylem: () -> Void
}

struct Acilir {
    var baslik: String? = nil
    var ogeler: [AcilirOge]
    /// öğe yokken gösterilen yazı ("Okunuyor…" gibi)
    var bilgi: String? = nil
}

struct AcilirGorunum: View {
    @ObservedObject var d: Durum
    let a: Acilir

    var body: some View {
        HStack(spacing: Olcu.ara) {
            Tus("xmark", genislik: Olcu.dar, eylem: d.acilirKapat)
            if let b = a.baslik {
                Yazi(b, boyut: 12).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 4)
            }
            if a.ogeler.isEmpty {
                Text(L(a.bilgi ?? "")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            } else if a.ogeler.count > 8 {
                // uzun listeler (posta kutuları) kayan şeritte; parmakla kaydırarak seçim yalnız kısa listelerde
                KaydirmaSeridi {
                    ForEach(Array(a.ogeler.enumerated()), id: \.offset) { _, o in
                        Tus(genislik: nil, vurgu: o.secili ? .white.opacity(0.28) : nil, eylem: { d.acilirKapat(); o.eylem() }) {
                            Text(L(o.yazi ?? "")).lineLimit(1).frame(maxWidth: 160)
                        }
                        .seritte()
                    }
                }
                .onAppear { d.acilirAlan = .zero }
            } else {
                Grup(tuslar: a.ogeler.enumerated().map { i, o in
                    GrupTus(simge: o.simge, yazi: o.yazi, nokta: o.nokta,
                            vurgu: o.secili || d.acilirParmak == i ? .white.opacity(0.28) : nil) { d.acilirKapat(); o.eylem() }
                })
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { d.acilirAlan = g.frame(in: .named("cubuk")) }
                        .onChange(of: g.frame(in: .named("cubuk"))) { _, r in d.acilirAlan = r }
                })
            }
        }
    }
}

final class TusYeri: ObservableObject { var x: CGFloat = 0 }

/// Açılır çubuğu olan tuş. `dokununca` verilirse dokunmak onu yapar, açılır çubuk yalnız basılı tutup kaydırınca
/// gelir (Mail'deki Yanıtla gibi); verilmezse ikisi de açar ve tuşun köşesinde orijinaldeki gibi küçük bir ok olur.
struct AcilirTus<Etiket: View>: View {
    @ObservedObject var d: Durum
    var genislik: CGFloat? = Olcu.simge
    var vurgu: Color? = nil
    let acilir: () -> Acilir
    var dokununca: (() -> Void)? = nil
    @ViewBuilder var etiket: () -> Etiket
    @StateObject private var yer = TusYeri()

    var body: some View {
        Tus(genislik: genislik, vurgu: vurgu, eylem: { if let dokununca { dokununca() } else { d.acilirAc(acilir()) } }) {
            HStack(spacing: 3) {
                etiket()
                if dokununca == nil {
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .kaydirinca({ dx in d.acilirKaydir(yer.x + dx, acilir) }, bitince: d.acilirBirak)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { yer.x = g.frame(in: .named("cubuk")).midX }
                .onChange(of: g.frame(in: .named("cubuk"))) { _, r in yer.x = r.midX }
        })
    }
}
