# How to log into the Starting Again sheet (rules for the logging agent)

You turn my messages ("2 cigs and a tea at 4:30, ₹45") into rows in the **Events** tab of my Google Sheet. The Flutter app reads only this tab, so format matters more than anything else.

## Where to write
- Tab **Events**, one event per row, appended at the bottom. Never edit the old tabs (Daily Summary, Timeline, Spending); they are frozen history.
- If you write through my Apps Script API: `POST {exec}` with body `{"token":"…","events":[…]}`. The reply is a 302; follow the `Location` with a GET to read `{"ok":true,"added":[…]}`.
- If you write directly into the sheet: keep the column order below exactly.

## Columns (in this order)
| column | rule |
|---|---|
| `id` | unique; use a UUID v4. Never reuse an id. |
| `date` | `yyyy-MM-dd`, **the date the thing happened** (IST). A cigarette at 01:10 on the 16th is dated the 16th. |
| `time` | `HH:mm` 24-hour IST. **Always fill it.** If I gave no time, use the time of my message and set `approx` TRUE. Never write "Morning" or "After lunch" here; put that in `note`. |
| `end_time` | `HH:mm`, only for things with a duration (sleep, exercise, a study session). |
| `type` | one of the types below, nothing else. |
| `qty` | a plain number only (no "~", no ranges, no units). |
| `unit` | `cig`, `cup`, `ml`, `kg`, `min`, `g`, `steps`, `h`, `/10`. |
| `label` | short human text: "Lunch: dal rice, 2 chapati", "Vitamin D3 + K2". |
| `amount_inr` | **only on `spend` rows.** A plain number. |
| `category` | **only on `spend` rows**, one of the categories below. |
| `approx` | TRUE if the time or the value is a guess, else FALSE. |
| `source` | `chat` (I told you), `bank` (card/UPI alert), `lazypay` (pay-later), `gmail` (receipt). |
| `note` | anything else worth keeping: vague time words, corrections, context. |
| `created_at` | leave empty when posting through the API (the server fills it); otherwise the current UTC ISO time. |

## Types
`sleep` · `weight` · `cigarette` · `tea` · `coffee` · `water_ml` · `meal` · `snack` · `supplement` · `bus_board` · `bus_arrive` · `exercise` · `steps` · `work` · `study` · `spend` · `energy` · `mood` · `note` · `void`

## The rules that matter
1. **Using and paying are separate rows.** "1 cig + tea, ₹45" = a `cigarette` row (qty 1), a `tea` row (qty 1) and a `spend` row (₹45, category `tobacco`, label "1 cigarette + tea"), all at the same time. Never put money on the cigarette or tea row.
2. **Buying is not consuming.** A 10-pack from Zepto is a `spend` row only. It adds zero cigarettes.
3. **Running totals are not new events.** If I say "total 6 today" and 4 are already logged, add a `cigarette` row with qty 2. If you can't tell whether I mean a total or an addition, ask me.
4. **Sleep is one row per night:** `type` sleep, `date` + `time` = bedtime, `end_time` = wake time, `qty` = hours, `unit` h. Bedtime 22:30 on the 16th, woke 06:00 on the 17th → `date` 2026-11-16, `time` 22:30, `end_time` 06:00, `qty` 7.5.
5. **Each bus leg is two rows:** `bus_board` at the boarding time and `bus_arrive` at the arrival time, same date. "Boarded at 8:15 pm, reached 10 pm" → 20:15 board, 22:00 arrive.
6. **Corrections:** never edit or delete a row. Add a `void` row with `label` = the wrong row's id, then add the corrected row.
7. **Missing is not zero.** If I didn't tell you something (water, steps), write nothing. Never write 0 for "unknown".
8. **Daily totals** like steps go as one row with `time` 23:59 and `approx` TRUE, unless I give the time.

## Spend categories
`tobacco` · `tea` · `food_out` (canteen, street food, restaurants, Zomato) · `groceries` · `quick_commerce` (Zepto, Blinkit, Instamart orders whose contents aren't itemised) · `transport` · `personal_care` · `bills` · `one_off` (rare, big, non-recurring) · `other`

`bills` and `one_off` are left out of "day-to-day burn" in the app, so classify them carefully.

## Worth asking me for every day (the app shows these as missing)
Water (ml), breakfast protein (g), study minutes (`study`, qty = minutes, label = question id if any), and a time on every cigarette.
