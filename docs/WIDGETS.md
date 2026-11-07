# Script widgets (beta)

A script widget is a small JavaScript file that puts a value on the Touch Bar. GlassBar runs it in JavaScriptCore, without a browser: it can't read your files, and it can only use the network, open links or press keys if it asks for that permission. You see the permissions before you install it.

A widget only runs while it's on the bar. Each call to its script gets half a second; a script that takes longer is stopped and shows "stopped" until it's shown again.

## Make one

GlassBar Hub > Widgets > **New Script Widget** makes a folder with an example and opens it in Finder. Widgets live in

```
~/Library/Application Support/GlassBar Beta/Widgets/<id>/
```

Put it on the bar with its switch on the Widgets page, or in a layout with `{ "type": "widget", "widget": "script:<id>" }`. After changing the script, press **Reload** on the Widgets page and switch the widget off and on.

## widget.json

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
| `id` | Same as the folder name. Lowercase with dashes. |
| `script` | The JavaScript file. Default `main.js`. |
| `refresh` | Seconds between `update()` calls. At least 1, default 60. |
| `permissions` | Any of `network`, `openLinks`, `keys`. Leave it empty if the widget needs none. |

## The script

GlassBar calls `update()` when the widget appears and then every `refresh` seconds, and `tap()` when it's tapped. Both are optional.

| Call | Does |
|---|---|
| `glassbar.show({ text, icon, role })` | What the widget shows. `icon` is an Apple symbol name, `role` one of the theme roles (`warning`, `success`, `danger`, `active`…). The theme draws it. |
| `glassbar.store.get(key)` / `glassbar.store.set(key, value)` | Small text values that stay between launches. |
| `glassbar.log(text)` | Writes to `~/Library/Logs/GlassBar Beta.log`. |
| `glassbar.fetch(url, callback)` | Needs `network`. Calls `callback(text)` with the response, or `null`. http and https only. |
| `glassbar.open(link)` | Needs `openLinks`. A link, or an app's bundle identifier. |
| `glassbar.key("cmd+shift+b")` | Needs `keys`. The same shortcut names as layouts. |

```js
function update() {
  glassbar.fetch("https://wttr.in/?format=%t", t => {
    glassbar.show({ text: t ? t.trim() : "–", icon: "thermometer.medium" })
  })
}
```

AppleScript and shell commands are not available to script widgets, and they never will be for widgets from the store.
