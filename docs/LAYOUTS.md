# Writing GlassBar layouts

A layout gives one app (or a few) your own buttons on the Touch Bar: keyboard shortcuts, menu commands, links, opening another app. It replaces the middle part of the bar while that app is in front. The Control Strip on the right stays as it is.

There's no editor yet. Like themes, layouts are JSON files you write yourself. A drag-and-drop editor is planned, see the [roadmap](../ROADMAP.md).

> **The layout format is alpha.** Names and options may still change. Old files should keep loading, but check this page after an update if something stops working.

## Your first layout in five minutes

1. Find the app's bundle identifier: `osascript -e 'id of app "Xcode"'` in Terminal.
2. Menu > Theme > Open Layouts Folder. Make a folder `my-layout` there with a file `layout.json` in it.
3. Paste the example below, put your app's identifier in `apps`, and change the buttons to the shortcuts you use most. The app's menus show its shortcuts.
4. Save and choose Theme > Reload Themes and Layouts, then bring the app to the front.
5. If a button doesn't show up or does nothing, look in `~/Library/Logs/GlassBar.log`.

## Where layouts live

```
~/Library/Application Support/GlassBar/Layouts/
```

Menu > Theme > **Open Layouts Folder** takes you there, or the Layouts tab in GlassBar Hub. A layout is either a single `my-layout.json` file or a folder with a `layout.json` inside, plus any images it uses. After saving, choose **Reload Themes and Layouts** from the same menu.

Layouts from other people are in the Layouts tab of GlassBar Hub and install with one click.

## A complete example

`~/Library/Application Support/GlassBar/Layouts/terminal-tabs/layout.json`:

```json
{
  "id": "terminal-tabs",
  "name": "Terminal Tabs",
  "author": "your-github-name",
  "version": 1,
  "description": "Tabs, clear and Ctrl-C without reaching for the keyboard.",
  "apps": ["com.apple.Terminal"],
  "items": [
    { "type": "group", "items": [
      { "icon": "chevron.left", "action": { "shortcut": "cmd+shift+[" } },
      { "icon": "chevron.right", "action": { "shortcut": "cmd+shift+]" } }
    ] },
    { "icon": "plus", "action": { "shortcut": "cmd+t" } },
    { "label": "clear", "action": { "shortcut": "cmd+k" } },
    { "type": "space" },
    { "label": "^C", "role": "operator", "action": { "shortcut": "ctrl+c" } },
    { "icon": "xmark", "action": { "shortcut": "cmd+w" } }
  ]
}
```

## Fields

| Field | Values | Notes |
|---|---|---|
| `id` | text | Unique. Lowercase with dashes. |
| `name` | text | Shown in GlassBar Hub. |
| `author` | text | Your name or GitHub handle. |
| `version` | number | Raise it when you change a shared layout. |
| `description` | text | One line for the store. |
| `apps` | list of bundle identifiers | The apps this layout is for. |
| `items` | list | The buttons, left to right. |

To find an app's bundle identifier, run this in Terminal:

```
osascript -e 'id of app "Xcode"'
```

If two layouts name the same app, the first one by name wins and the log says so.

## Items

Every item is a button unless `type` says otherwise.

| Field | Values | Notes |
|---|---|---|
| `type` | `button`, `group`, `space`, `text`, `widget` | Default `button`. `space` pushes what follows to the right. `text` is a plain label. `widget` is a built-in widget, see below. |
| `label` | text | Text on the button. Shown as written, never translated. |
| `icon` | an SF Symbol name, or `image:file.png` | A button needs a label, an icon, or both. Images come from the layout's folder and are drawn 16 points high. |
| `role` | `active`, `primary`, `accent`, `operator` | Draws the button the way the theme draws that role (see [THEMES.md](THEMES.md#roles)). |
| `width` | 20 to 400 | Points. Leave it out and the button fits its content. |
| `action` | object | What happens on tap. |
| `items` | list | Only for `group`: the buttons inside it. |

Icons follow the theme. If the theme maps `chevron.left` to `<`, your layout shows `<` too.

## Widgets (beta)

`{ "type": "widget", "widget": "cpu" }` puts a built-in widget in the layout. The widgets are `clock`, `battery`, `cpu`, `memory`, `worldClock`, `clipboard`, `nowPlaying` and `dock`. The world clock takes a time zone in `option`: `{ "type": "widget", "widget": "worldClock", "option": "Asia/Tokyo" }`.

Widgets are drawn by the theme like any button. Their states use roles: low battery and high CPU are `warning`, charging is `success`.

## Actions

Each action has one of these:

| Key | Example | What it does |
|---|---|---|
| `shortcut` | `"cmd+shift+p"`, `"f5"`, `"ctrl+`"` | Presses the keys. ⌘ shortcuts are found in the app's menu first, so they work with any keyboard layout. |
| `menu` | `"Show Sidebar"` | Presses the menu item with that title in the front app. Use the title in the language your Mac uses. |
| `open` | `"https://example.com"` or `"com.apple.Terminal"` | Opens a link, or opens the app with that bundle identifier. |

Shortcut names: `cmd`, `shift`, `alt` (or `option`), `ctrl`, then one key: a letter, a digit, punctuation like `[` `]` `-` `=` `/` `\` `` ` ``, or `return`, `tab`, `space`, `delete`, `escape`, `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`, `f1` to `f12`.

Shortcuts and menu commands need the Accessibility permission GlassBar already asks for.

## Examples in the repo

[layouts/](../layouts) has Xcode Basics, VS Code Essentials, Terminal Tabs and Figma Tools. They're short and good to copy from.

## Pitfalls

- **Space is tight.** About 680 points are free between the app icon and the Control Strip. Short labels and icons fit best.
- **App shortcuts change.** Check each one in the app's menus. If nothing happens on tap, look in the log.
- **No scripts.** Layouts can't run code. AppleScript and script widgets may come later, see the roadmap.
- **A layout replaces GlassBar's own buttons** for that app, including Safari or Mail. Remove the layout to get them back.

## When something doesn't work

Bad items are skipped instead of breaking the bar, with one line each in `~/Library/Logs/GlassBar.log`:

```
layout xcode: items[2]: can't read the shortcut "cmd+hammer"
layout my-layout.json: could not read it: not valid JSON (Unexpected end of file)
```

Taps are logged too (`shortcut ⌘K: via menu`, `menu Show Sidebar: not found`), which helps when a button seems to do nothing.

## Sharing

Same as themes: a pull request that adds your layout folder under `layouts/`, with a `preview.png` of the bar. See [layouts/README.md](../layouts/README.md).
