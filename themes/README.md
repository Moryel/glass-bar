# Community themes

Themes made by GlassBar users. To try one, download its folder, rename it to `<id>.glasstheme` and double-click it, or copy the folder into `~/Library/Application Support/GlassBar/Themes/` and choose **Theme > Reload Themes**.

How to write a theme: [docs/THEMES.md](../docs/THEMES.md).

## Submitting a theme

Open a pull request that adds one folder here:

```
themes/
  retro-amber/
    theme.json
    preview.png        (optional, a screenshot of the bar)
    SomeFont.ttf       (if the theme uses one)
    OFL.txt            (the font's license)
```

- The folder name is the theme's `id`. Lowercase letters, numbers and dashes, and not already taken by another folder here or a built-in theme.
- `theme.json` needs `id`, `name` and `author` (your name or GitHub handle).
- Add only fonts, images and sounds you're allowed to share. For fonts that usually means the SIL Open Font License (OFL) or similar, and the license file goes in the folder. Fonts that come with macOS or that you bought can't be included; use the font's name in `theme.json` instead and say in the PR which font it needs.
- Keep it small. A few hundred KB is plenty.
- Check `~/Library/Logs/GlassBar.log` after loading it. It should have no lines about your theme.
- A screenshot helps a lot: `screencapture -b preview.png` saves the Touch Bar.

One theme per pull request please. I'll look at contrast and whether it reads well on the real bar, and may ask for small changes before merging.

The theme format is still alpha, so a theme may need small updates later. I'll try to fix the ones here myself when the format changes.
