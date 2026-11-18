"""Build Events rows for 11–17 Nov 2026 from the legacy tabs.

Sources: sheets.pkl (export, rows unchanged since) + rows fetched later for 17 Nov.
Output: events.json (list of row lists in EVENT_COLUMNS order) + a reconciliation report.
"""
import json
import pickle
import re
import sys
from collections import defaultdict

COLS = ['id', 'date', 'time', 'end_time', 'type', 'qty', 'unit', 'label',
        'amount_inr', 'category', 'approx', 'source', 'note', 'created_at']
CREATED = '2026-11-17T20:45:00.000Z'

sheets = pickle.load(open(sys.argv[1], 'rb'))
extra = json.load(open(sys.argv[2]))  # {"timeline":[rows from 160], "spending":[rows from 50]}

timeline = [r + [''] * 11 for r in sheets['Timeline'][1:159]]  # sheet rows 2..159
timeline += [r + [''] * 11 for r in extra['timeline']]          # sheet rows 160..
spending = [r + [''] * 9 for r in sheets['Spending'][1:49]]     # sheet rows 2..49
spending += [r + [''] * 9 for r in extra['spending']]           # sheet rows 50..

events = []
seq = defaultdict(int)


def clock(text):
    """First HH:MM in text -> ('HH:MM', approx). Vague text -> ('', True)."""
    t = (text or '').strip()
    if not t:
        return '', False
    m = re.search(r'(\d{1,2}):(\d{2})', t)
    if not m:
        return '', True
    h, mi = int(m.group(1)), int(m.group(2))
    if 'PM' in t.upper() and h < 12:
        h += 12
    if h == 24:
        h = 0
    approx = bool(re.search(r'~|inferred|screensh|receipt|–|unconfirm|period|outing', t))
    return f'{h:02d}:{mi:02d}', approx


def add(date, etype, *, time='', end='', qty='', unit='', label='', amount='',
        category='', approx=False, source='chat', note=''):
    seq[date] += 1
    events.append({
        'id': f'bf-{date}-{seq[date]:03d}', 'date': date, 'time': time, 'end_time': end,
        'type': etype, 'qty': qty, 'unit': unit, 'label': label, 'amount_inr': amount,
        'category': category, 'approx': approx, 'source': source, 'note': note,
        'created_at': CREATED,
    })


# ---------- sleep (from Daily Summary, the numbers Sumit trusts) ----------
SLEEP = [  # bed date, bed time, wake time, hours, approx
    ('2026-11-11', '00:00', '06:00', 6, True),
    ('2026-11-12', '00:30', '08:06', 7.6, False),
    ('2026-11-13', '00:00', '06:00', 6, True),
    ('2026-11-14', '00:00', '06:00', 6, True),
    ('2026-11-15', '04:00', '10:07', 6.1, True),
    ('2026-11-16', '02:00', '08:00', 6, True),
    ('2026-11-16', '22:30', '06:00', 7.5, True),  # night into 17 Nov
]
for d, bed, wake, hrs, ap in SLEEP:
    add(d, 'sleep', time=bed, end=wake, qty=hrs, unit='h', label='Overnight sleep', approx=ap,
        note='backfill from Daily Summary; date = bedtime date, end_time = wake')

# ---------- timeline consumption & activity ----------
SKIP_CATS = {'Sleep', 'Wake', 'Sleep routine', 'Sleep / bedtime', 'Purchase', 'Plan',
             'Supplement status', 'Commute', 'Outing / travel'}
NOTE_CATS = {'Hygiene', 'Hygiene / grooming', 'Social', 'Learning', 'Screen time', 'Rest',
             'Food photo', 'Food quality', 'Health', 'Health / energy', 'Wellbeing',
             'Sleep quality', 'Activity / daily assessment', 'Food / preparation',
             'Food / purchases', 'Health / hydration'}
LUNCH_11 = set(range(16, 25))   # itemised 11 Nov lunch rows
BKFST_12 = {55, 56, 58, 59}      # itemised 12 Nov breakfast rows (coffee row 57 separate)
COMBOS = {  # sheet row -> list of (type, qty, label)
    146: [('tea', 1, 'Tea'), ('cigarette', 1, '')],
    153: [('tea', 1, 'Lemon tea'), ('cigarette', 1, '')],
    154: [('tea', 1, 'Tea'), ('cigarette', 1, '')],
    157: [('cigarette', 1, ''), ('snack', 1, 'Lahori Jeera'), ('snack', 2, 'Pani puri (2 plates)')],
    166: [('cigarette', 1, ''), ('tea', 1, 'Tea')],
    171: [('cigarette', 1, ''), ('tea', 1, 'Tea')],
    172: [('cigarette', 1, ''), ('tea', 1, 'Tea')],
    175: [('cigarette', 1, ''), ('snack', 1, 'Lahori Jeera')],
}
MEAL_WORDS = re.compile(r'lunch|dinner|breakfast|pizza|litti|meal', re.I)

for idx, r in enumerate(timeline, start=2):
    d, st, et, cat, item, qty, unit = r[0], r[1], r[2], r[3], r[4], r[5], r[6]
    t, ap = clock(st)
    e_t, ap2 = clock(et)
    vague = st if st and not t else ''
    note = f'time: {vague}' if vague else ''
    if idx in LUNCH_11:
        if idx == 16:
            add(d, 'meal', label='Lunch: palak soup, chhole, mixed veg, dal rice, 2 chapati, mosambi, curd, salad, sweet',
                qty=1, unit='meal', note='~950–1,350 kcal estimated from photo')
        continue
    if idx in BKFST_12:
        if idx == 55:
            add(d, 'meal', label='Breakfast: 2 bananas, 2 egg rolls, 3 chapatis, 1 bread', qty=1, unit='meal')
        continue
    if idx in COMBOS:
        for et_, q, lab in COMBOS[idx]:
            add(d, et_, time=t, qty=q, unit='cig' if et_ == 'cigarette' else '', label=lab,
                approx=ap, note=note)
        continue
    if cat in SKIP_CATS:
        continue
    if cat == 'Weight':
        add(d, 'weight', time=t, qty=float(qty), unit='kg', approx=ap, note=note)
    elif cat.startswith('Smoking'):
        add(d, 'cigarette', time=t, qty=float(qty), unit='cig', approx=ap, note=note)
    elif cat.startswith('Supplement') or cat == 'Supplements':
        if idx == 155:
            add(d, 'supplement', label='Omega-3', note='time unknown')
            add(d, 'supplement', label='Vitamin D3 + K2', note='time unknown')
        elif idx in (141, 170):
            continue  # absence, not an event
        else:
            lab = re.sub(r'\s+after almonds.*', '', item)
            add(d, 'supplement', time=t, label=lab, approx=ap, note=note)
    elif cat in NOTE_CATS:
        add(d, 'note', time=t, end=e_t, label=f'{cat}: {item}'[:160], approx=ap or ap2, note=note)
    elif idx == 83:
        add(d, 'meal', time=t, end=e_t, label=item[:160], qty=1, unit='meal', approx=ap, note=note)
    elif cat == 'Food / supplements' or (cat == 'Food — breakfast' and 'whey' in item.lower()):
        add(d, 'meal', time=t, label='Whey shake + coffee', qty=1, unit='meal', approx=ap, note=note)
        add(d, 'supplement', time=t, label='Creatine', approx=True, note='~5–8 g in shake')
    elif cat in ('Drink', 'Drink — breakfast'):
        low = item.lower()
        if 'tea' in low:
            add(d, 'tea', time=t, qty=float(qty or 1), unit='cup', label=item, approx=ap, note=note)
        elif 'coffee' in low:
            add(d, 'coffee', time=t, qty=float(qty or 1), unit='cup', approx=ap, note=note)
        else:
            add(d, 'snack', time=t, qty=qty, unit=unit, label=item, approx=ap, note=note)
    elif cat.startswith('Food'):
        etype = 'meal' if (MEAL_WORDS.search(cat) or MEAL_WORDS.search(item)) and 'snack' not in cat.lower() else 'snack'
        add(d, etype, time=t, qty=qty, unit=unit, label=item[:120], approx=ap, note=note)
    elif cat in ('Exercise', 'Movement', 'Steps'):
        if 'steps' in item.lower():
            add(d, 'steps', qty=float(qty), unit='steps', approx=(r[9] == 'Approximate'))
        elif 'badminton' in item.lower():
            add(d, 'exercise', time='09:30', end='12:30', qty=60, unit='min', label='Badminton',
                approx=True, note='1 h play inside 09:30–12:30 outing; ~1.5 h travel')
        else:
            add(d, 'exercise', time=t, label=item, approx=True, note=note)
    elif cat == 'Work':
        add(d, 'work', time=t, label=item[:160], approx=ap, note=note)
    elif cat == 'Health / subjective scores':
        add(d, 'energy', qty=6, unit='/10', note='mood 6/10; headache 2/10')
    elif cat in NOTE_CATS:
        add(d, 'note', time=t, end=e_t, label=f'{cat}: {item}'[:160], approx=ap or ap2, note=note)
    else:
        print('UNMAPPED', idx, cat, item, file=sys.stderr)

# ---------- commute legs (board / arrive) ----------
LEGS = [  # date, board, arrive, approx, note
    ('2026-11-11', '09:20', '10:20', False, 'to office'),
    ('2026-11-11', '20:00', '21:30', True, 'home'),
    ('2026-11-12', '09:20', '10:25', False, 'to office'),
    ('2026-11-12', '20:30', '21:50', True, 'home'),
    ('2026-11-13', '09:00', '10:15', False, 'to office'),
    ('2026-11-13', '20:15', '21:20', False, 'home'),
    ('2026-11-16', '09:20', '10:50', False, 'to office'),
    ('2026-11-16', '20:15', '21:40', False, 'home'),
    ('2026-11-17', '09:20', '10:40', False, 'to office'),
    ('2026-11-17', '20:15', '21:45', True, 'home; app note says reached 22:00, Daily Summary says ~21:45'),
]
for d, b, a, ap, n in LEGS:
    add(d, 'bus_board', time=b, label='Bus', approx=ap, note=n)
    add(d, 'bus_arrive', time=a, label='Bus', approx=ap, note=n)

# ---------- spending ----------
QC = {2, 15, 16, 17, 18, 19, 36, 41, 47, 48}  # quick-commerce order lines


def spend_cat(idx, merchant, item):
    low = f'{merchant} {item}'.lower()
    if idx in QC:
        return 'quick_commerce'
    if 'google play' in low:
        return 'one_off'
    if 'electricity' in low:
        return 'bills'
    if 'cigarette' in low:
        return 'tobacco'
    if 'beard' in low or 'barber' in low:
        return 'personal_care'
    if 'milk' in low:
        return 'groceries'
    if 'transport' in low or 'ride' in low:
        return 'transport'
    if re.search(r'\btea\b', low):
        return 'tea'
    return 'food_out'


for idx, r in enumerate(spending, start=2):
    d, tm, merchant, item, method, amount = r[0], r[1], r[2], r[3], r[4], r[5]
    if not amount.strip():
        continue  # unpriced (17 Nov ~22:00) — not confirmed spend
    t, ap = clock(tm)
    note = ''
    if idx == 22:
        t, ap, note = '', False, 'bank time 01:18 is posting time, not meal time'
    if idx == 50:
        item = 'Tea (₹20 confirmed for tea only; cigarette cost unknown)'
    src = 'lazypay' if 'lazypay' in method.lower() else ('bank' if re.search(r'ICICI|HDFC', method) else 'chat')
    label = item if merchant.lower().startswith(('unreported', 'vendor', 'tea vendor', 'lunch vendor', 'order merchant')) or 'unreported' in merchant.lower() or 'unknown' in merchant.lower() else f'{merchant}: {item}'
    add(d, 'spend', time=t, label=label[:120], amount=float(amount), category=spend_cat(idx, merchant, item),
        approx=ap, source=src, note=note)

rows = [[e[c] for c in COLS] for e in events]
json.dump(rows, open('events.json', 'w'), ensure_ascii=False)

# ---------- reconciliation vs Daily Summary ----------
DS = {  # date: cigs, tea, spend, weight, steps
    '2026-11-11': (13, 5, 1654, 87.1, 6500), '2026-11-12': (5, 2, 2572.51, 88, 6500),
    '2026-11-13': (11, 3, 1010, 88.5, 16000), '2026-11-14': (6, None, 1467.14, 88.1, None),
    '2026-11-15': (5, None, 3120.14, 88.5, 2096), '2026-11-16': (4, 3, 515, 88.7, 12576),
    '2026-11-17': (6, 3, 404, 87.91, 15000),
}
agg = defaultdict(lambda: defaultdict(float))
for e in events:
    d = e['date']
    if e['type'] in ('cigarette', 'tea', 'steps'):
        agg[d][e['type']] += float(e['qty'] or 0)
    if e['type'] == 'weight':
        agg[d]['weight'] = float(e['qty'])
    if e['amount_inr'] != '':
        agg[d]['spend'] += e['amount_inr']
ok = True
for d, (c, tea, spend, w, steps) in DS.items():
    got = agg[d]
    checks = [('cigs', c, got['cigarette']), ('tea', tea, got['tea']), ('spend', spend, round(got['spend'], 2)),
              ('steps', steps, got['steps'])]
    for name, want, have in checks:
        if want is None:
            continue
        flag = 'OK' if abs(want - have) < 0.01 else 'MISMATCH'
        ok &= flag == 'OK'
        print(f'{d} {name:6} want {want:>9} got {have:>9} {flag}')
types = defaultdict(int)
for e in events:
    types[e['type']] += 1
print('rows', len(events), dict(types))
print('ALL OK' if ok else 'HAS MISMATCHES')
