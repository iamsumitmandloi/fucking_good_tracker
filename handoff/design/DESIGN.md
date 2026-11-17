# Starting Again: design spec

The 6 files in `screens/` are the design source (390×844 phone frames). They are HTML from a design tool, so treat them as a visual spec and build the Flutter version yourself. They will not render correctly in a browser: `{{holes}}`, `<sc-for>` and `<sc-if>` are template syntax, and `support.js` is not included.

| File | Screen | Notes |
|---|---|---|
| `Today.dc.html` | Today (home) | Interactive in the source: +1 tiles, bus toggle. In-file links say `Main.dc.html`, which means this file. |
| `LogSheet.dc.html` | Quick log bottom sheet | Opens from a FAB or a long-press on a tile |
| `Study.dc.html` | Study tab | |
| `BusMode.dc.html` | Bus mode (full screen) | Interactive: reveal → rate → next card → summary |
| `Trends.dc.html` | Week tab | Bar chart, sleep-window chart, weight dots + average line |
| `Money.dc.html` | Money tab | |

If `screens/png/` exists, those screenshots are the source of truth for looks. Use the HTML for exact values.

## Tokens

### Colour (dark only for v1)
| Token | Hex | Use |
|---|---|---|
| bg | `#0E1012` | scaffold |
| bgBus | `#0B1218` | Bus mode scaffold |
| surface | `#171A1E` | cards |
| surface2 | `#1F2329` | chips, inner tiles, icon wells |
| border | `#2A2F36` | card border, 1px |
| borderStrong | `#3A414A` | outlined buttons, dashed "not logged yet" tiles |
| divider | `#22262C` | list dividers, nav top border |
| text | `#EDEEF0` | primary text |
| textMuted | `#A3AAB4` | secondary text, labels |
| textDim | `#7D858F` | tertiary text, units, axis labels |
| accent | `#C8F169` | brand lime: primary buttons, active nav, good trend |
| onAccent | `#0E1012` | text on lime |
| info | `#7CC4FF` | bus/commute, water, Bus mode |
| warn | `#FFA94D` | over budget, missing data, deadline countdown |
| busCard | `#121C25` / border `#22394A` | Bus mode cards |

Rule: blue vs orange for good vs bad, never red vs green alone.

### Type
- Display and numbers: **Space Grotesk** 500/600/700 (google_fonts). H1 32/700, letter-spacing −0.02em. Big stat 28–34/600–700.
- Body: **Inter** 400/500/600. Body 13–15, labels 12, nav 11.
- Tabular feel on numbers; no serif anywhere.

### Shape and spacing
- Card radius 18 (hero cards 20, sheet top 28), chip radius 8–12, pill 18–20.
- Screen padding 18 horizontal, ~28 top. Gap between cards 10–12.
- Touch targets ≥ 44px. Primary button height 48–56.
- Icons: stroke icons, 1.8 stroke, 20–22px (lucide or Material Symbols Outlined are fine). No emoji.

## Components
1. **QuickTile**: surface card, 104 tall, 3 per row. Icon top-left, lime `+` top-right, big number, a one-line caption. Tapping the whole tile logs +1 and shows an undo line ("Logged 1 cigarette · 18:02 · ₹25 · Undo"). A dashed border means the metric has never been logged.
2. **BusCard**: one button cycling Board → Arrived → Done, which writes `bus_board` and `bus_arrive` events. Shows duration.
3. **UpNextCard**: lime background, dark text. Question id, topic, next action, "Start 25 min" plus an outlined "Bus mode".
4. **StatCard**: label, big number, caption.
5. **BottomNav**: 4 tabs (Today, Study, Week, Money), 76 tall, lime when active.
6. **SleepWindowRow**: day label, track 21:00→11:00, bar from bed to wake. Orange if bedtime is after 02:00, blue otherwise; hours on the right.
7. **FlashCard**: Bus mode card. Chips (id, level·tier·type), topic, question (22/600), follow-ups, revealed answer points with lime bullets. Rating row: Blank (orange), Shaky (neutral), Nailed it (lime).
8. **StackedBar**: Money split (delivery orange / everything else blue / one-offs grey) with a legend.

## Copy rules
- Facts, not disclaimers. One small "est." or "~" marks an estimate; never a paragraph of caveats.
- Missing data reads "—", or a dashed tile plus "Not logged" in the Week card. Never 0.
