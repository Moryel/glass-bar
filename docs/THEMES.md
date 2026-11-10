# Writing GlassBar themes

A GlassBar theme is a JSON file. You can make one in Theme Studio without typing anything, or write the file yourself. This guide covers both and lists every field.

> **The theme format is alpha.** Field names and defaults may still change before it settles. I'll try to keep old files loading, but if something breaks after an update, check this page again.

## Theme Studio

GlassBar Hub > **Theme Studio** edits a theme on a preview of the bar, and on your real Touch Bar at the same time.

1. **Pick a starter**: dark, light, outline, pixel or terminal. Or open one of your installed themes. A built-in theme is saved as a copy with a new id, so the original stays as it was.
2. **Click a part** on the preview: a button, a group, the bar itself, or a button in a role (active, primary, operator…). Its fill, text, border, shape and shadow open next to it. The preview can show any of the app bars, so check Calculator for `operator` and Safari for `accent`.
3. **Quick Colors** recolors the whole theme from a few colors, which is the fast way to get a first version.
4. **The bar background** takes a color, a two or three color gradient (linear or radial), a pattern, or an image from your Mac. The image is copied into the theme.
5. **The Code tab** shows the same theme as JSON. Edits there show on the preview, so you can use a field the other tabs don't have.

Undo works on every change and Revert goes back to the last save. Saving writes the theme into your themes folder, and **Publish…** in the Hub prepares it for the store.

Everything the studio does ends up in `theme.json`. The rest of this page is that file.

## Your first theme by hand

1. Open GlassBar Hub (menu > GlassBar Hub…) and install a theme from the store that's close to what you want, for example Paper.
2. In Hub, go to Installed, open the theme's menu (…) and choose Show in Finder.
3. Copy that folder next to it and rename the copy, for example `my-theme.glasstheme`.
4. Open `theme.json` in the copy with any text editor. Change `id` to `my-theme`, `name` to something of your own, and `author` to your name.
5. Change a few colors (`"fill": "#F4EFE4"` and so on), save, and choose Theme > Reload Themes and Layouts.
6. Pick your theme from the Theme menu. Keep editing and reloading until you like it.
7. If something doesn't change, look in `~/Library/Logs/GlassBar.log`.

The rest of this page explains every field you can use.

## Where themes live

Put your theme in

```
~/Library/Application Support/GlassBar/Themes/
```

The quickest way there is the menu bar icon: **Theme > Open Themes Folder**, or the same button in GlassBar Hub. After you save a change, choose **Theme > Reload Themes and Layouts** and the bar redraws with the new file. Your theme shows up in the Theme menu by its `name`.

A theme can be:

- a single file, `my-theme.json` or `my-theme.glasstheme`
- a folder with a `theme.json` inside, plus any fonts, images or sounds it uses. If the folder is named `my-theme.glasstheme`, Finder shows it as one file and double-clicking it installs it.

Double-clicking a `.glasstheme` file or package anywhere on your Mac copies it into the themes folder and switches to it. That's the easiest way to give a theme to someone else.

Use a folder as soon as your theme needs a font, an image or a sound. File paths in `theme.json` are relative to that folder. A `preview.png` in the folder (a screenshot of the bar, `screencapture -b preview.png`) is shown on the theme's card in GlassBar Hub.

## Look, not behavior

A theme only changes how the bar looks: colors, borders, fonts, what an icon is drawn as, the press animation and the tap sound. It can't add buttons, move them or change what they do. Every bar (Safari, Mail, Calculator, the Control Strip…) keeps working the same way under any theme. This keeps themes safe to share and means one theme covers every app GlassBar supports.

## Two kinds of themes

**Glass themes** use GlassBar's own glass drawing and only tune it: tint, strength of the glass and edge light, corner radius, text color, font. Classic, Minimal Liquid Glass, Graphite and Neon are glass themes.

**Skinned themes** have a `skin` key and draw every button themselves, without glass: flat colors, gradients, ASCII brackets, pixel borders. Terminal and 8-Bit Arcade are skinned themes.

As soon as a theme has `skin`, the glass fields (`style`, `glassColor`, `glass`, `edge`, `glow`, `shadow`, `cornerRadius`) stop mattering.

## A complete example

Copy this into `~/Library/Application Support/GlassBar/Themes/my-paper/theme.json`, then Reload Themes and Layouts and pick "My Paper" from the menu.

```json
{
  "id": "my-paper",
  "name": "My Paper",
  "author": "your-github-name",
  "version": 1,
  "textColor": "#2B2B2B",
  "sliderColor": "#2B2B2B",
  "roles": {
    "active": { "fill": "#D9472B", "text": "#FFFFFF", "borderColor": "#F4EFE4" },
    "primary": { "fill": "#D9472B", "text": "#FFFFFF", "borderColor": "#D9472B" },
    "accent": { "fill": "#D9472B", "text": "#FFFFFF", "borderColor": "#D9472B" },
    "operator": { "fill": "#E8DFCB" }
  },
  "skin": {
    "bar": { "fill": "#3B362E", "pattern": "grid", "patternColor": "#FFFFFF12" },
    "button": {
      "fill": "#F4EFE4",
      "text": "#2B2B2B",
      "border": "sketch",
      "borderWidth": 1.5,
      "borderColor": "#2B2B2B",
      "radius": 8
    },
    "pressed": { "fill": "#E0D6C0" },
    "group": { "fill": "#F4EFE4", "border": "sketch" },
    "text": { "font": "serif", "weight": "semibold" },
    "press": "wobble",
    "sounds": { "tap": "tick" }
  }
}
```

## Top-level fields

| Field | Values | Default | Notes |
|---|---|---|---|
| `id` | text | required | Unique. Lowercase with dashes is best (`paper`, `retro-amber`). Don't reuse a built-in id (`classic`, `minimal`, `graphite`, `neon`, `terminal`, `arcade`, `original`); a theme with a built-in id is skipped. Because the id becomes a folder name, it can't contain `/`, `\\`, `:` or `..`, or start with a dot. |
| `name` | text | `""` | Shown in the Theme menu. |
| `author` | text | `""` | Your name or GitHub handle. |
| `version` | number | `1` | Your own version of the theme. |
| `style` | `classic`, `minimal` | `classic` | Glass themes only. Classic has a bright highlight and a light ring, minimal is closer to macOS 26 Liquid Glass. |
| `glassColor` | hex color | `#FFFFFF` | Glass tint. Glass themes only. |
| `glass` | 0 to 2.5 | `1` | Glass fill strength. 1 is the built-in look. |
| `edge` | 0 to 2.5 | `1` | Edge light. |
| `glow` | 0 to 2.5 | `1` | Glow under your finger. |
| `shadow` | 0 to 2 | `1` | Button shadow. |
| `bounce` | 0 to 2 | `1` | How much a button squishes when pressed (only with the `liquid` press effect). |
| `cornerRadius` | 0 or more | `13` | Button corner radius in points. 13 and up is a capsule. Glass themes only, skins use `radius`. |
| `textColor` | hex color | `#FFFFFF` | Text and icon color. In a skin it's also the default border color. |
| `accent` | hex color or `""` | `""` | Tint of the main action in some bars (the + in Safari). Empty means none. |
| `sliderColor` | hex color or `""` | `""` | Filled part of sliders and the Spotify sound bar. Empty keeps each slider's own color. |
| `fontDesign` | `standard`, `rounded`, `monospaced`, `serif` | `standard` | System font design. A skin's `text.font` wins over this. |
| `fontWeight` | `regular`, `medium`, `semibold`, `bold` | `medium` | A skin's `text.weight` wins over this. |
| `backdrop` | `off`, `app`, `aurora`, `sunset`, `ocean`, `siri`, `wallpaper` or `""` | `""` | Switches the Background menu when the theme is chosen. Empty leaves the user's choice alone. A skin with `bar` covers the background anyway. |
| `roles` | object | `{}` | See [Roles](#roles). |
| `skin` | object | none | See [Skin](#skin). |
| `widget` | object | none | How widgets and the Dock look in this theme. See [Widgets](#widgets). |

Colors are `#RRGGBB` or `#RRGGBBAA` (the last pair is opacity, `80` is about half).

## Roles

Some buttons have a job that the theme can style separately. Built-in bars never use fixed colors, they ask for a role:

| Role | Used for |
|---|---|
| `active` | Something switched on or selected: mute, the current Space, the chosen tab. |
| `primary` | The main action: Done, Send, a spelling correction. |
| `accent` | The theme's accent action, like + in Safari. |
| `operator` | Calculator's ÷ × − + =. |
| `suggestions` | The typing suggestions group. |
| `danger` | Badges on Dock icons. Falls back to `operator` when it isn't set. |
| `warning` | Widget warnings such as low battery. Falls back to `operator`. |
| `success` | Widget good news such as a finished timer. Falls back to `active`. |

Each role takes the same fields as a [layer](#layers).

In a glass theme only `fill` is used. If a role isn't set, GlassBar uses its own color: a light highlight for `active`, blue for `primary`, `accent` for `accent` (nothing if it's empty), orange for `operator`, dark blue for `suggestions`, red for `danger`, orange for `warning`, green for `success`.

In a skinned theme a role is drawn on top of `skin.button`, so you only write what changes. A role you leave out looks like a normal button. `pressed` goes on top of the role, so a pressed primary button gets both.

## Widgets

Widgets never bring their own colors. They give a value and a state, and the theme draws them like any button: low battery and high CPU use `warning`, charging and a finished timer use `success`. So a theme that sets those two roles already covers every widget, script widgets included.

The optional `widget` key changes single widgets:

```json
"widget": {
  "battery": { "label": "bat" },
  "cpu": { "icon": "bolt", "role": "accent" },
  "dock": { "iconStyle": "mono", "iconSize": 18, "spacing": 2 }
}
```

| Field | What it does |
|---|---|
| `label` | A short name shown instead of the icon (`bat`, `cpu`). |
| `icon` | Another symbol in front of the value. Goes through the icon map like any symbol. |
| `role` | Always draw this widget in that role, whatever its state. |

The keys are the widget ids: `clock`, `date`, `battery`, `headphones`, `cpu`, `memory`, `disk`, `network`, `timer`, `focus`, `worldClock`, `clipboard`, `nowPlaying`. Skins with an `ascii` border show short names (`bat`, `cpu`) on their own.

The battery's icon turns yellow in Low Power Mode in every theme, the same yellow the menu bar uses.

**The Dock** uses only roles: the shelf is the group, the front app is `active`, running dots are `accent` and badges are `danger`. `widget.dock` tunes it. `iconStyle` is `color`, `mono`, `text` or `pixel`; without it, skins with an `ascii` border show app names as text and `pixel` skins show pixelated icons. The user can still pick a style in Dock Settings.

## Skin

All skin fields are optional. A skin only says what it changes.

| Field | What it is |
|---|---|
| `bar` | The bar behind the buttons. See [Bar](#bar). |
| `button` | Every button. A [layer](#layers). |
| `pressed` | Changes while a button is held down. A layer. |
| `group` | The background of a button group (back/forward, the media keys). A layer, drawn on top of `button`. |
| `text` | Font and text options. See [Text](#text). |
| `icons` | Replaces Apple's symbols with text or images. See [Icon map](#icon-map). |
| `press` | `liquid`, `pop`, `shake`, `wobble` or `none`. Default `pop` for skins, `liquid` for glass. |
| `sounds` | `{ "tap": "click" }`. See [Sounds](#sounds). |

### Layers

`button`, `pressed`, `group` and every role are layers. Each field is optional.

| Field | Values | Default | Notes |
|---|---|---|---|
| `fill` | hex color or `"none"` | none | `"none"` removes a fill set by a lower layer. |
| `fill2` | hex color | none | Second color for a top-to-bottom gradient from `fill`. |
| `text` | hex color | `textColor` | |
| `border` | `none`, `solid`, `dashed`, `pixel`, `ascii`, `sketch` | `none` | `pixel` has notched corners, `ascii` draws brackets around the label, `sketch` looks hand drawn. |
| `borderWidth` | 0 to 6 | `1` | For `pixel` it's the pixel size. |
| `borderColor` | hex color | `textColor` | |
| `radius` | 0 or more | `6` | Corner radius in points. Capped at half the button height. |
| `glow` | 0 to 12 | `0` | Glow radius around the button. |
| `glowColor` | hex color | white | |
| `shadow` | 0 to 4 | `0` | Drop shadow strength. |
| `bevel` | true / false | false | Pixel borders: light top-left and dark bottom-right inner edges. |
| `chars` | two strings with a space between | `"[ ]"` | ASCII border characters: `"[ ]"`, `"< >"`, `"| |"`, `"( )"`. |
| `invert` | true / false | false | Swaps fill and text colors. Terminal uses it for pressed and active keys. |

Order, from bottom to top: `textColor` → `skin.button` → role → `skin.pressed`. Groups: `skin.button` → `skin.group` → role.

Groups with `ascii` or `pixel` borders are drawn as separate buttons, because brackets and pixel corners can't be shared across a group.

### Bar

| Field | Values | Notes |
|---|---|---|
| `fill` | hex color | Bar color. Default black. |
| `fill2` | hex color | Gradient from `fill`. |
| `fill3` | hex color | A third gradient color after `fill2`. |
| `gradient` | `linear`, `radial` | Default `linear`. `radial` starts at the middle of the bar. |
| `angle` | 0 to 360 | Direction of a linear gradient in degrees: 0 runs left to right, 90 top to bottom. |
| `image` | a file in the theme folder | A picture over the color, under the pattern. The bar is 30 points tall. |
| `imageMode` | `fill`, `stretch`, `tile` | Default `fill` (cropped to cover the bar). |
| `imageOpacity` | 0 to 1 | Default 1. |
| `pattern` | `stars`, `grid`, `dots`, `stripes`, `none` | A static pattern behind the buttons. |
| `patternColor` | hex color | Default half-transparent white. |
| `patternOpacity` | 0 to 1 | Default 1. |
| `patternSize` | 3 to 40 | Distance between the pattern's marks in points. Default 8. |
| `overlay` | `scanlines`, `vignette`, `none` | Drawn over everything: CRT lines, or darker ends. |
| `overlayOpacity` | 0 to 1 | Default 0.4. |

If a skin has `bar`, it replaces the user's Background setting. Without `bar`, the user's background shows behind your buttons.

### Text

| Field | Values | Default | Notes |
|---|---|---|---|
| `font` | `system`, `mono`, `rounded`, `serif`, an installed font name, or a `.ttf`/`.otf` file in the theme folder | system | Font files are loaded only for GlassBar, nothing gets installed. |
| `scale` | 0.5 to 2 | `1` | Multiplies every text size. Pixel fonts usually need less than 1 (Arcade uses 0.62). |
| `weight` | `regular`, `medium`, `semibold`, `bold`, `heavy` | `medium` | Most custom fonts only have one weight, so this mostly affects system fonts. |
| `case` | `upper`, `lower`, `none` | `none` | |
| `tracking` | -6 to 6 | `0` | Letter spacing in points. |

### Icon map

`icons` maps an Apple SF Symbol name to what you want drawn instead:

```json
"icons": {
  "chevron.left": "<",
  "speaker.slash.fill": "mute",
  "heart": "image:heart.png"
}
```

A value is either plain text, or `image:` followed by a file in the theme folder. Images are drawn 16 points high, without smoothing, so pixel art stays sharp. Make them 32 px high for Retina. Symbols you don't list keep Apple's icon.

One special value: `"siri": "orb"` draws GlassBar's coloured Siri orb instead of the word Siri.

The names that matter most:

- Navigation: `chevron.left`, `chevron.right`, `magnifyingglass`, `plus`, `xmark`
- Control Strip: `sun.max.fill`, `sun.min.fill`, `speaker.fill`, `speaker.wave.1.fill`, `speaker.wave.2.fill`, `speaker.wave.3.fill`, `speaker.slash.fill`, `siri`, `moon.stars.fill`, `keyboard`, `light.min`, `light.max`, `lock.fill`, `mic.fill`, `rectangle.3.group`, `square.grid.3x3.fill`, `camera.viewfinder`
- Media: `play.fill`, `pause.fill`, `playpause.fill`, `backward.fill`, `forward.fill`, `gobackward.10`, `goforward.10`, `gobackward.15`, `goforward.15`, `music.note`, `heart`
- Calculator: `plus`, `minus`, `multiply`, `divide`, `equal`, `percent`, `plus.forwardslash.minus`
- Mail and Finder: `square.and.pencil`, `arrowshape.turn.up.left`, `archivebox`, `trash`, `xmark.bin`, `flag.fill`, `paperplane.fill`, `paperclip`, `folder`, `tag`, `eye`, `square.and.arrow.up`
- Typing: `textformat`, `list.bullet`, `checklist`, `face.smiling`, `sparkles`

`siri` isn't a real SF Symbol, it's the Siri button. Terminal's `theme.json` maps about 60 symbols and is the best list to copy from. To find other names, the free SF Symbols app from Apple shows them all.

### Sounds

Sounds play only if the user turns on **Theme > Play Theme Sounds**. Right now there's one event, `tap`.

```json
"sounds": { "tap": "click" }
```

The value is a built-in sound (`click`, `blip`, `tick`, generated in code, no file needed) or a sound file in the theme folder (`"tap": "key.wav"`). Keep files short, under 100 ms feels right for a key.

## Worked examples

Both ship inside the app, in `Resources/Themes` in this repo.

**Terminal** (`Resources/Themes/terminal/theme.json`) is green text on near black with scanlines. Buttons have no fill (`"fill": "none"`), an `ascii` border with `[ ]`, a small green glow and the system mono font in lower case. Pressing a key or turning something on inverts it (`"invert": true`). Operator keys turn amber through the `operator` role. Most of the file is the icon map, which turns symbols into words like `vol+`, `mute` and `rm`.

**8-Bit Arcade** (`Resources/Themes/arcade/`) is a folder with `theme.json`, the Press Start 2P font and its OFL license. Yellow buttons with a 2 px `pixel` border and `bevel`, a purple starry bar, the font at `"scale": 0.62` in upper case, the `pop` press effect and the `blip` sound. Roles make active keys blue and operators red.

A good way to start is copying one of them into your themes folder, changing the `id` and `name`, and editing from there.

## Pitfalls

- **Contrast.** The Touch Bar is small and often seen at an angle. Keep text clearly lighter or darker than its button, and check `active` and `pressed` too, not just the normal state.
- **Font glyphs.** Many fun fonts only cover A to Z. Check that yours has the letters your users will see, including accented and Turkish letters (ç ğ ı İ ö ş ü). App names, track titles and suggestions can contain anything.
- **No endless animations.** The Touch Bar is drawn by a system process, TouchBarServer. Anything that keeps moving makes it redraw at 60 fps and costs real CPU and battery. Themes can't add animations on their own right now, and that's on purpose. Patterns and overlays are static.
- **Text on the Dock's shelf.** The battery and clock at the end of the Dock sit on the shelf when the theme draws one, and straight on the bar when it doesn't. They take the right text color for each case, so check both the Dock and a normal bar.
- **Text straight on the bar.** The app name, track titles and times aren't on a button. They use the button `fill` color (or the button `text` color when buttons have no fill), so the bar `fill` has to contrast with the button fill.
- **ASCII brackets in narrow places.** Brackets take width. Short labels and icon text work best (`<` instead of `back`), long icon text makes buttons wide.
- **`text.scale`** below about 0.6 gets hard to read. Pixel fonts look big, which is why Arcade scales them down.
- **Fill `"none"` with no border** leaves only the label, which is fine for Terminal but can make buttons look like plain text elsewhere.
- **Fonts you ship must be shareable.** See [themes/README.md](../themes/README.md).

## When something looks wrong

GlassBar never crashes on a bad theme, it skips what it can't use. Values out of range are clamped, unknown words and broken colors are ignored, missing font, image and sound files are skipped. Every problem gets one line in

```
~/Library/Logs/GlassBar.log
```

for example

```
theme paper: skin.text.scale 0.0 is out of range 0.5...2, using 0.5
theme paper: skin.button.border "zigzag" is unknown, ignored
theme my-theme.json: could not read it: not valid JSON (Unexpected end of file)
```

The log starts fresh every time GlassBar launches. Open it in Console or with `tail -f` while you edit, then use Reload Themes and Layouts.

If a theme doesn't show up in the menu at all, it usually means the JSON itself is broken (a missing comma or a trailing one) or the `id` clashes with a built-in theme.

If a field has the wrong type (`"scale": "big"` instead of a number), that field is skipped. Inside `skin`, a wrong type currently drops the whole skin, and the log says which field it was.

## What a theme can't do

A theme is data, not code. It can't run anything, and the files it names (fonts, images, sounds) have to be inside its own folder: a path with `../` or a symlink that points elsewhere is skipped. That's what makes a theme from the store safe to install with one click.

## Sharing your theme

Themes are shared through pull requests to this repo. **Publish…** on your theme in GlassBar Hub checks it, lists every file that would become public and opens the pull request page. Every theme in the [themes](../themes) folder shows up in the Store page of GlassBar Hub, where people can install it with one click. See [themes/README.md](../themes/README.md) for how to submit one.
