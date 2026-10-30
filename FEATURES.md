# Original Touch Bar features and their status in GlassBar

Sources: Apple Support "Use the Touch Bar" and "Customize the Touch Bar", the MacRumors customization guide, iMore "What you can do with the Touch Bar", the 9to5Mac gallery of Apple apps (2016), WWDC17 session 211 (AVKit), and the WebKit source code (`generateTouchBarThumbnailsForTimes`). On 2026-10-30 the app bars were compared on a 13" M2 (macOS 26) with the originals: GlassBar was turned off, each app was brought to the front, and its bar was captured with `screencapture -b`.

Status: ✅ available · 🟡 partial · ❌ missing · ⛔ not possible (only the app itself provides the data)

## Layout
| Feature | Status |
|---|---|
| esc / app area / Control Strip layout | ✅ |
| Shorter bar without esc on models with a physical esc key | ✅ |
| Touch ID (hardware; not touched) | ✅ |
| Dims when idle, wakes on touch (done by the system) | ✅ system |
| esc changing with context ("Done" in Contacts) | ❌ |
| Hiding buttons by priority when space runs out | ❌ |
| White point following ambient light (True Tone) | ❌ |

## Control Strip
| Feature | Status |
|---|---|
| Collapsed: expand, brightness, volume, mute, Siri | ✅ |
| Expanded: brightness ±, Mission Control, Launchpad/Apps, keyboard backlight ±, media, volume ±/mute, Siri | ✅ |
| Touch a button and **slide without lifting** (brightness/volume) | ✅ |
| Slider opens on touch, with a close button | ✅ |
| **Now Playing** button (in the strip while media plays) | ✅ Music, Spotify, QuickTime (other apps ⛔: MediaRemote is closed) |
| Customizing the strip | ✅ up to 5 of 19 buttons from the menu, in the order picked · drag and drop ❌ |
| Buttons that can be added | ✅ Spotlight, Notification Center, Night Shift, Screenshot, Input Sources, Show Desktop, Screen Saver, Lock Screen, Sleep, Play/Pause, Mission Control, Apps, Keyboard Brightness, Dictation, Quick Actions (the front app's Services menu) · ❌ Do Not Disturb, AirPlay (no public API) |

## Settings (Keyboard → Touch Bar Settings)
| Feature | Status |
|---|---|
| "Touch Bar shows": App Controls / Expanded Control Strip / F1, F2 / Quick Actions / Spaces | ✅ except Quick Actions |
| "Press and hold fn to": the same 5 options | ✅ except Quick Actions |
| Show/hide the Control Strip | ✅ |
| Always show F keys in specific apps | ✅ |
| Show typing suggestions | ✅ |
| fn + ⌃/⌥/⇧/⌘ + F key | ✅ held modifiers are added to the F key |
| Not in the original: Theme (Classic / Simple Liquid Glass) | ✅ |
| Not in the original: Background: Off, App color, Aurora, Sunset, Ocean, Siri colors, Wallpaper (the Mac's desktop picture), Choose image… | ✅ (`ArkaPlan.swift`) |
| Not in the original: the Siri pill is a clear glass drop like Apple's new Siri, with colorful waves that follow your voice through the microphone; background noise is filtered out (microphone permission on first use; nothing is recorded) | ✅ (`Siri.swift`, `Mikrofon.swift`) |
| Language | ✅ GlassBar's text follows the system language (Turkish, English; English for other languages): `Resources/<language>.lproj/Localizable.strings`. Menu commands are found by identifier, shortcut letter, or Turkish/English title |

## App-specific content

For apps marked ⛔, use "Show its own Touch Bar for …" in the menu (or press and hold the app icon): the app's own bar appears.

Menu commands run from the front app's menu through Accessibility (`AXYardim.swift`): by language-independent identifiers in Mail and Messages, by title elsewhere. ⌘ shortcuts are also looked up in the menu first (on the Turkish Q layout ⌘[ becomes ⌘Ğ).

| App | Status |
|---|---|
| **Safari** | ✅ back/forward, address bar, new tab, window and tab strip (with titles), show all tabs · tab thumbnails ⛔ · Favorites ❌ (the bookmarks file needs Full Disk Access) · web video ✅ play/pause, ±10 s, scrubber, time; on YouTube, thumbnails come from the site's storyboard images (no thumbnails on other sites). Requires Safari → Develop → "Allow JavaScript from Apple Events" |
| **Finder** | ✅ original layout: back/forward, view (popover: icon/list/column/gallery), Quick Look, Share, Tags (popover color palette) |
| **Mail** | ✅ original layout: New Message, Reply (press and slide for Reply All / Forward), Archive, Move to… (mailboxes from the menu), Delete, Flag (colors from the menu) · Send bar while composing ❌ |
| **Calculator** | ✅ original layout: ± % , and orange ÷ × − + = (presses Calculator's buttons) · Scientific mode buttons ❌ |
| **Calendar** | ✅ Today and month scrubber (the shown month framed in red) · unit change with day/week view ❌ (always months) · buttons for a selected event ❌ |
| **Reminders** | ✅ new reminder |
| **Contacts** | ✅ new contact; message, call, FaceTime and email the selected contact by name; Edit, Share (Automation permission for Contacts on first use) |
| **Preview** | ✅ tools (popover: Markup, Adjust Color, Adjust Size), rotate left/right, flip horizontal/vertical |
| **Photos** | ✅ Favorite, Auto Enhance, Rotate (toolbar buttons) · while a video is open: play/pause, scrubber with thumbnails from the video's frames, times (the video is exported to a temp folder; Automation permission on first use) · photo thumbnail strip of the library ⛔ |
| **Messages** | ✅ new message, Tapback (popover: ❤️ 👍 👎 😂 ‼️ ❓), emoji, suggestions |
| **Notes** | ✅ original layout when not typing (new note, checklist, delete, list); while typing: checklist, Aa (heading styles, bold/italic/underline), list types, emoji, suggestions |
| **TextEdit** | ✅ format (popover: bold/italic/underline, alignment), emoji, suggestions · color picker ⛔ |
| **Music / Spotify** | ✅ play/pause, previous/next, scrubbing in the track bar, like · Add to Up Next ✅ (Music) |
| **Spotify integration** | 🔜 coming soon: sign in with a Spotify account (Web API), playlists, search, Add to Queue, like, device selection with Spotify Connect |
| **QuickTime / AVKit video** | ✅ QuickTime (15 s forward/back, filmstrip with thumbnails, glass-lens playhead) · other players ⛔ |
| **⇧⌘5 screenshot** | ✅ original layout: three capture modes, three recording modes, "Save to" (presses the tool's buttons) |
| Typing suggestions (QuickType) | 🟡 word completion, blue correction, original look (blue-grey group, "‹ ⌨") · contact suggestions ⛔ |
| Emoji | ✅ the original 9 categories: Frequently Used, Smileys & People, Animals & Nature, Food & Drink, Activity, Travel & Places, Objects, Symbols, Flags; momentum scrolling |
| Color picker (color/shade, Simple/Grayscale/RGB/CMYK/HSB) | ⛔ only the app can apply the color |
| Maps, System Settings | empty in the original too (tested on macOS 26) |
| Books progress bar, Calendar event details, Keynote slides, FaceTime | ⛔ |
| Pages, Numbers, Keynote, iMovie, GarageBand, Final Cut, Logic, Xcode, third-party apps | the app's own bar via "show its own Touch Bar" |
| Touch ID / Apple Pay prompts, incoming calls | ⛔ the system's own bar |
| "Customize Touch Bar" inside apps | ⛔ |

## Touch behavior
| Feature | Status |
|---|---|
| Tap-and-lift buttons | ✅ |
| Popover bar: opens over the other items on tap or press-and-slide, with a small arrow in the corner | ✅ (`Acilir.swift`) |
| Press, slide and release to pick in one gesture | ✅ in popovers (up to 8 items) and brightness/volume |
| Alternative action on press-and-hold (Mail Reply) | ✅ |
| Momentum scrolling and snapping in strips (scrubber) | ✅ emoji, Safari tabs, Calendar months, long popover lists |
| Slider dragging | ✅ |

## Accessibility
| Feature | Status |
|---|---|
| Touch Bar Zoom | ❌ |
| VoiceOver | not tested |
