import SwiftUI

// Popover (as in the original): tapping a button, or pressing and sliding, opens its own bar
// over the other items. Press + slide + release picks an item in one gesture.
struct PopoverItem {
    var symbol: String? = nil
    var text: String? = nil
    var dot: Color? = nil
    var isSelected = false
    let action: () -> Void
}

struct Popover {
    var title: String? = nil
    var items: [PopoverItem]
    /// text shown when there are no items (like "Loading…")
    var placeholder: String? = nil
}

struct PopoverView: View {
    @ObservedObject var d: AppState
    let a: Popover

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            GlassButton("xmark", width: Metrics.narrowWidth, action: d.closePopover)
            if let b = a.title {
                BarText(b, size: 12).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 4)
            }
            if a.items.isEmpty {
                Text(L(a.placeholder ?? "")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            } else if a.items.count > 8 {
                // long lists (mailboxes) go in a scrolling strip; slide-to-pick only for short lists
                ScrollingStrip {
                    ForEach(Array(a.items.enumerated()), id: \.offset) { _, o in
                        GlassButton(width: nil, highlight: o.isSelected ? .white.opacity(0.28) : nil, action: { d.closePopover(); o.action() }) {
                            Text(L(o.text ?? "")).lineLimit(1).frame(maxWidth: 160)
                        }
                        .inScrollingStrip()
                    }
                }
                .onAppear { d.popoverFrame = .zero }
            } else {
                ButtonGroup(buttons: a.items.enumerated().map { i, o in
                    GroupButton(symbol: o.symbol, text: o.text, dot: o.dot,
                            highlight: o.isSelected || d.highlightedPopoverItem == i ? .white.opacity(0.28) : nil) { d.closePopover(); o.action() }
                })
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { d.popoverFrame = g.frame(in: .named("bar")) }
                        .onChange(of: g.frame(in: .named("bar"))) { _, r in d.popoverFrame = r }
                })
            }
        }
    }
}

final class ButtonPosition: ObservableObject { var x: CGFloat = 0 }

/// Button with a popover. If `onTap` is given, a tap does that and the popover only appears on press and slide
/// (like Reply in Mail); otherwise both open it and the button gets a small arrow in its corner like the original.
struct PopoverButton<Label: View>: View {
    @ObservedObject var d: AppState
    var width: CGFloat? = Metrics.iconWidth
    var highlight: Color? = nil
    let popover: () -> Popover
    var onTap: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label
    @StateObject private var buttonPosition = ButtonPosition()

    var body: some View {
        GlassButton(width: width, highlight: highlight, action: { if let onTap { onTap() } else { d.showPopover(popover()) } }) {
            HStack(spacing: 3) {
                label()
                if onTap == nil {
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .whenSliding({ dx in d.dragPopover(buttonPosition.x + dx, popover) }, onEnd: d.releasePopoverDrag)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { buttonPosition.x = g.frame(in: .named("bar")).midX }
                .onChange(of: g.frame(in: .named("bar"))) { _, r in buttonPosition.x = r.midX }
        })
    }
}
