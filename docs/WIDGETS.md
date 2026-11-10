# Widgets

GlassBar has two kinds of widgets. The built-in ones (clock, battery, CPU and so on) are switched on in GlassBar Hub > Widgets. Script widgets are small JavaScript files you write yourself, and this page is mostly about those.

A widget only gives a value. The theme draws it, so the same widget is a glass capsule in Classic and `[bat 87%]` in Terminal.

## Built-in widgets

| Id | Shows | Tap |
|---|---|---|
| `clock` | The time. | |
| `date` | Today's date. | |
| `battery` | Charge. Green while plugged in, the warning color at 20% or less, a yellow icon in Low Power Mode. Follows the charger the moment it's plugged in or pulled. | Battery settings |
| `headphones` | Lowest charge of the connected AirPods or headphones. Hidden while none are connected. | Bluetooth settings |
| `cpu` | Processor use. | Activity Monitor |
| `memory` | Memory in use. | Activity Monitor |
| `disk` | Free space. | Storage settings |
| `network` | Download speed. | |
| `timer` | A countdown. | Start or stop |
| `focus` | Whether a Focus is on. Needs Full Disk Access, without it the widget only opens Focus settings. | Focus settings |
| `worldClock` | The time in another city. | |
| `clipboard` | What's on the clipboard. | |
| `nowPlaying` | The current track. | |
| `dock` | Your Dock. | |

Widgets sit left of the Control Strip, or inside a layout with `{ "type": "widget", "widget": "cpu" }` (see [LAYOUTS.md](LAYOUTS.md#widgets)). They read their values only while they are on the bar.

In the Original theme the first widget sits in Apple's Control Strip. Tap it and the others slide in over the app area.

## Script widgets

A script widget is a folder with two files: `widget.json` says what it is, and a JavaScript file gives the value. GlassBar runs the script in JavaScriptCore, without a browser. There is no `document`, no `window` and no `XMLHttpRequest`, only plain JavaScript and the `glassbar` object described below.

### Your first widget in five minutes

1. Open GlassBar Hub > Widgets and press **New Script Widget**. GlassBar makes a folder `my-widget` with a working example and shows it in Finder.
2. Switch the widget on with its switch on the Widgets page. It appears on the bar and counts the days left in the year.
3. Open `main.js` in any text editor and change what `update()` shows.
4. Press **Reload** on the Widgets page, then switch the widget off and on.
5. If it shows `?` or nothing, look in `~/Library/Logs/GlassBar.log`. Script errors are written there with the widget's id.

**Add Weather** on the same page writes a finished weather widget into your folder. It's a good one to read, since it uses the network and picks an icon.

### Where they live

```
~/Library/Application Support/GlassBar/Widgets/<id>/
```

The folder name and the `id` in `widget.json` are the same. **Install…** on the Widgets page copies a folder from anywhere on your Mac into it, after showing you what the widget may do.

### widget.json

```json
{
  "id": "weather",
  "name": "Weather",
  "author": "your-github-name",
  "version": 1,
  "description": "Temperature where you are.",
  "script": "main.js",
  "refresh": 600,
  "permissions": ["network"]
}
```

| Field | Notes |
|---|---|
| `id` | Same as the folder name. Lowercase letters, numbers and dashes. |
| `name` | Shown on the Widgets page. |
| `author`, `version`, `description` | For the store and for people who install it. |
| `script` | The JavaScript file. Default `main.js`. It has to be inside the widget's folder. |
| `refresh` | Seconds between `update()` calls. At least 1, default 60. Pick the slowest that still looks right: weather is fine at 600. |
| `permissions` | Any of `network`, `openLinks`, `keys`. Leave it empty if the widget needs none. |
| `shortcuts` | With `keys`: the shortcuts the widget presses, like `["cmd+shift+b"]`. Anything else is refused, and people see the list before they install. Without it they are told the widget can press any shortcut. |

### The script

GlassBar calls `update()` when the widget appears and then every `refresh` seconds, and `tap()` when it's tapped. Both are optional.

| Call | Does |
|---|---|
| `glassbar.show({ text, icon, role })` | What the widget shows. `icon` is an Apple symbol name, `role` one of the theme roles (`warning`, `success`, `danger`, `active`, `primary`, `accent`). All three are optional. |
| `glassbar.store.get(key)` / `glassbar.store.set(key, value)` | Small text values that stay between launches. Up to 50 keys, each value under 2000 characters. |
| `glassbar.log(text)` | Writes to `~/Library/Logs/GlassBar.log`. |
| `glassbar.fetch(url, callback)` | Needs `network`. Calls `callback(text)` with the response, or `null` if it failed. See the limits below. |
| `glassbar.open(link)` | Needs `openLinks`. An http or https link, or an app's bundle identifier. |
| `glassbar.key("cmd+shift+b")` | Needs `keys`. The same shortcut names as [layouts](LAYOUTS.md#actions). |

A value with an icon:

```js
function update() {
  const now = new Date()
  const days = Math.ceil((new Date(now.getFullYear() + 1, 0, 1) - now) / 86400000)
  glassbar.show({ text: days + "d", icon: "calendar" })
}
```

From the network:

```js
function update() {
  glassbar.fetch("https://wttr.in/?format=%t", t => {
    glassbar.show({ text: t ? t.trim() : "–", icon: "thermometer.medium" })
  })
}
```

Something that remembers and reacts to taps:

```js
let count = Number(glassbar.store.get("count") || 0)

function update() {
  glassbar.show({ text: String(count), icon: "hand.tap", role: count >= 10 ? "success" : null })
}

function tap() {
  count += 1
  glassbar.store.set("count", String(count))
  update()
}
```

### Limits

These are on purpose. A widget is code from someone else, running on your Mac all day.

- **Half a second per call.** An `update()` or `tap()` that runs longer is stopped, and the widget shows "stopped" until it's shown again. Do slow work with `fetch` and its callback.
- **Only while visible.** The script doesn't run when the widget isn't on the bar.
- **No files, no shell, no AppleScript.** A script can't read or write anything on disk except its own `store`. This won't change for widgets from the store.
- **`fetch` goes to public https addresses only.** No http, no `localhost`, no IP addresses (in any spelling), no `.local` names, no ports, no user names in the address. A site that redirects to one of those is cut off at the redirect, so a widget can't be used to reach your router or something running on your Mac. No cookies are sent or kept. One request at a time per widget, 10 seconds at most, answers over 1 MB are dropped.
- **Unknown permissions are ignored**, with a line in the log.

### How a theme draws your widget

You don't choose colors. `role` says what the value means, and the theme decides how that looks. Use `warning` for something that needs attention, `success` for good news, `danger` for a real problem, and nothing for the normal state.

Symbol names follow the theme's icon map too. If a theme draws `thermometer.medium` as text, your widget shows that text.

### Sharing

**Publish…** next to your widget checks it (id, name, author, description, only text, image, font and sound files), lists every file that would become public and writes the package. Hidden files and symlinks are left out. It then opens the pull request page for this repo.

Before you publish, ask for as little as you can. A widget with no permissions installs without a second thought. One with `keys` and no `shortcuts` list tells people it can press anything, and many won't install it.
