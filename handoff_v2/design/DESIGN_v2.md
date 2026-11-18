# Starting Again v2: viewer design spec

Six screens in `design/v2/` (390×844, design-tool HTML). Read them for layout, copy and values; don't run them. `{{holes}}`, `<sc-for>` and `<sc-if>` are template syntax, and the numbers inside each file's `<script>` are the real 11–17 Nov values the screen was drawn from.

| File | Tab | What it answers |
|---|---|---|
| `V2Day.dc.html` | Day | "What did my day look like?" KPI tiles vs my 7-day average, a 24-hour ribbon (tap a mark → detail), untimed items, chronological list. ‹ › switches days. |
| `V2Week.dc.html` | Week | "Do my days repeat?" Seven ribbons stacked (small multiples) + weekly totals + 2 written takeaways. |
| `V2Smoking.dc.html` | Trends › Smoking | Daily bars + average line, time-of-day histogram, tea pairing, office vs off days, estimated cost. |
| `V2Sleep.dc.html` | Trends › Sleep & body | Sleep-window chart (bed → wake per night) with the usual-bedtime band, stats, weight (fixed axis + avg line), steps. |
| `V2Money.dc.html` | Money | Day-to-day burn bars (one-offs excluded and flagged ◆), ranked categories, pay-later total. |
| `V2Insights.dc.html` | Insights | Pattern cards with confidence dots, plus a coverage grid (what's logged, partial, missing). |

## Tokens (unchanged from v1 DESIGN.md)
bg `#0E1012` · surface `#171A1E` · surface2 `#1F2329` · border `#2A2F36` · divider `#22262C` · text `#EDEEF0` · textMuted `#A3AAB4` · textDim `#7D858F` · accent (UI only) `#C8F169`. Space Grotesk for headings and numbers, Inter for body.

## Data colours: validated, use exactly these
Checked with a palette validator on the dark surface `#171A1E`: lightness band, chroma, colour-blind separation (worst adjacent ΔE 8.4), normal-vision separation and ≥ 3:1 contrast all pass.

| Series | Hex | Used for |
|---|---|---|
| Sleep | `#3987e5` | sleep bars, steps bars, usual-bedtime band (14% alpha) |
| Smoking | `#d95926` | cigarette ticks/bars, untimed badges (dashed border) |
| Food & tea | `#199e70` | meal/snack/tea dots (meal 12px, others 8px) |
| Money | `#c98500` | spend dots (size ∝ √amount), money bars |
| Commute | `#5D646E` | bus bars (context, neutral) |

Rules:
1. **Text never wears a series colour.** Numbers and labels use the text tokens; a small swatch beside them carries identity.
2. **≥ 2 series → a legend.** A single series needs none (the title names it).
3. **One axis per chart**, never dual axes.
4. **Missing ≠ 0:** draw a gap or a dim placeholder (`#2A2F36`), never a zero-height bar that reads as "zero".
5. **Fixed, honest axes:** weight on 86–90 kg (≥ 4 kg span), never auto-zoomed to the min/max.
6. **Tap targets ≥ 24px around every mark** (the marks themselves stay thin); tapping shows a detail line, not a floating tooltip.
7. The accent lime is for navigation and UI state only, never data.

## Components to build (CustomPainter where noted)
1. **DayRibbon** (CustomPainter + GestureDetector hit-testing): lanes Sleep / Bus / Smoke / Food / ₹ on a 00:00–24:00 axis, with tick labels 00/06/12/18/24. The selected mark's detail goes in a line under the ribbon.
2. **WeekRibbons:** seven compact DayRibbons (sleep top, bus middle, smoke ticks from the bottom, food dots), each with a right-hand column (cigs, ₹) and a "+N no time" dashed badge when cigarettes lack times.
3. **BarsWithAverage:** daily bars, value label on each bar, dashed average line labelled at the right.
4. **HourHistogram:** 18 columns, 06–24; empty hours as 2px dim stubs.
5. **SleepWindows:** one row per night, bar from bed to wake on a 20:00–12:00 axis, a shaded band for mean bedtime ± 1 SD.
6. **RankedBars:** one hue, largest first, amount + % right-aligned.
7. **ConfidenceDots:** 5 dots, filled = confidence level; `aria-label` "Confidence n of 5".
8. **CoverageGrid:** metric × 7 days; filled = logged, dashed = partial, dim = missing.

## Copy tone
Facts first, then one plain sentence of meaning. No caveat paragraphs. Small sample sizes are said in the card itself ("Too few days to trust yet"), plus the confidence dots.
