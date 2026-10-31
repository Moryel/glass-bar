# GlassBar roadmap

GlassBar is growing from a Touch Bar replacement into a **free, open-source Touch Bar hub**: an alternative to BetterTouchTool that focuses only on the Touch Bar. Anyone will be able to make a theme that looks like anything, build their own buttons and widgets, set up a bar for any app, and share all of it through a store inside the app.

Everything here is free. Plans can change; ideas and feedback are welcome in the issues.

| Version | Focus | Status |
|---|---|---|
| 1.0 | Touch Bar replacement with a Liquid Glass look | Released |
| 2.0 | Theme engine 2 | In progress |
| 2.1 | GlassBar Hub window + Theme Studio | Next |
| 2.2 | Store | Planned |
| 2.3 | Bar Layout + widgets | Planned |
| 2.4 | Script widgets | Planned |
| Later | Ideas | Open |

---

## 2.0 — Theme engine 2

A theme will no longer be just a glass color: it will be able to draw every part of the bar its own way.

- **Skins.** Buttons without glass: a fill or gradient; borders that are solid, dashed, pixel-art (with a bevel), ASCII brackets (`[esc]`) or hand-drawn; corner radius, glow and shadow; a separate pressed look, or inverted colors.
- **The bar itself.** A color or gradient, patterns (stars, grid) and overlays such as CRT scanlines.
- **Roles.** Every built-in bar uses roles instead of fixed colors: *active* (a switched-on button, the current space), *primary* (Done, Send), *accent*, *operator* (Calculator's ÷ × − + =) and *suggestions*. One theme restyles every bar — Safari, Calculator, Mail, Finder, Music, emoji, sliders. A theme that leaves a role out falls back to its normal button, so nothing is ever unstyled.
- **Icon map.** Apple's symbols can be shown as text (`chevron.left` → `<`) or as the theme's own images.
- **Text.** A font shipped with the theme, a size scale, upper or lower case, letter spacing.
- **Press effects.** Liquid glass, pop, shake, wobble or none.
- **Theme sounds.** A tap sound per theme (built-in click, blip and tick, or the theme's own file). Off unless you turn on *Play Theme Sounds*.
- **Theme packages.** A `.glasstheme` folder holds `theme.json` plus its fonts, images and sounds. Double-click to install.
- **New built-in themes.** *Terminal* (green phosphor, ASCII brackets, scanlines, key clicks) and *8-Bit Arcade* (pixel font, pixel keys, a starfield).

## 2.1 — GlassBar Hub + Theme Studio

One window for everything, instead of a long menu.

- **GlassBar Hub window.** A sidebar with *Themes*, *Theme Studio*, *Settings* and, from 2.2, *Store*. The menu bar menu keeps quick switches and the theme picker.
- **Themes page.** Your installed themes as cards with a live mini preview of the bar. Apply, duplicate, export, delete, and import with drag and drop.
- **Theme Studio.** A visual editor for skins, so making a theme needs no JSON:
  - *Parts:* bar background, button, button group, slider, text, icons, press effect, transitions, sounds.
  - *States:* normal, pressed, active and disabled, side by side.
  - *Roles:* the look of primary actions, Calculator operators, suggestions and the rest.
  - *Icon map:* pick an Apple symbol and type what to show instead, or choose an image.
  - *Assets:* add fonts, images and sounds; a single-file theme becomes a package automatically.
  - *Live preview* at the real width, and on your Touch Bar at the same time.
  - *Export* a `.glasstheme` package to share.
- **Settings page.** Everything that is in the menu today — what the bar shows, fn behavior, Control Strip buttons, typing suggestions, esc, color temperature, background, the Spotify player, theme sounds, open at login, updates — in one place.

## 2.2 — Store

Themes, layouts and widgets from other people, one click away. Free, with no accounts.

- **Hosted on GitHub.** The store reads a public repository (`glassbar-hub`). Each item is a folder; an index lists them all.
- **Like the App Store.** Sections at the top (*Themes*, *Widgets*, *Layouts*), and on the left *List by*: Featured, New, Most installed, Recently updated, Name. Shelves of cards ("New themes", "Retro & games"), each with a live preview of the bar and a *Get* button. Categories per section, plus *Installed* and *Updates*.
- **Install, update, remove.** Items install into your library; when a new version is published, *Update* appears.
- **Bundles.** A theme can come with its own layouts and widgets, labelled for example **Theme + 3 Layouts**. *Get* offers: everything, the theme only, the layouts only, or choose parts. Someone who likes only the theme gets only the theme.
- **Publishing.** *Publish to store…* packages your theme, layout or widget and walks you through opening a pull request. Every submission is reviewed before it appears.

## 2.3 — Bar Layout + widgets

Decide exactly what the bar shows, for all apps or one app.

- **Built-in bars become layouts.** GlassBar's own bars (Safari, Calculator, Mail, Finder, Notes…) open as editable layouts. See the default Calculator bar, move or remove keys, add new ones; *Reset to default* brings it back.
- **App rules.** Make a key set for any app — Xcode, Figma, Zoom, your own tools — with a rule such as "when this app is in front" or "while fn is held". Choose what happens when the app has its own Touch Bar: your layout, the app's bar, or the app's bar on fn.
- **Drag-and-drop editor.** A library on the left, the bar in the middle (app area and Control Strip), the selected item's settings on the right. The bar is drawn with your current theme.
- **Action buttons.** Keyboard shortcut, open an app, open a link, a menu command, press a button in the app (like Calculator's), AppleScript (only for things you make yourself).
- **Built-in widgets.** Clock, battery, system monitor (CPU, memory), next calendar event, now playing, world clock, clipboard and more.
- **Widgets follow the theme.** A widget only says *what* to show — text, an icon, a value, a state; the theme decides *how* it looks. The same battery widget is a glass capsule in Liquid Glass, `[bat 87%]` in Terminal and a pixel key in 8-Bit Arcade. States map to roles (low battery → *warning*, a running timer → *active*), with new *warning*, *danger* and *success* roles. A theme may give a widget its own look (`widget.battery`); widgets that draw graphs get the theme's colors, so they can never clash with it.
- **Sharing.** Layouts can be exported, shipped inside a theme, or published to the store on their own.

## 2.4 — Script widgets

Widgets anyone can write and share safely.

- **JavaScript widgets** run in a sandbox with a small GlassBar API: show text, icons and values, refresh on a timer, react to taps.
- **Permissions.** A widget declares what it needs — network, opening links, sending keys — and you see that before installing.
- **Store-ready.** Script widgets can be published like themes. AppleScript and shell commands stay local-only and never come from the store.

## Later — ideas

- Theme Studio on the web, for people without a Touch Bar.
- Accounts, likes and comments in the store.
- Touch Bar Zoom and VoiceOver support.
- Drag-and-drop reordering on the Touch Bar itself.
- Features from the original Touch Bar that are still missing (see [FEATURES.md](FEATURES.md)).
