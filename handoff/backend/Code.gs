/**
 * Starting Again — tiny JSON API over your Google Sheet.
 * Paste into Extensions > Apps Script of the tracker sheet (bound script).
 *
 * Setup (once):
 *  1. Project Settings > Script properties > add TOKEN = <long random string>.
 *  2. Run setupEventsTab() once from the editor (creates the "Events" tab).
 *  3. Deploy > New deployment > Web app
 *       Execute as: Me    Who has access: Anyone
 *     Copy the /exec URL into the app. The TOKEN is the only lock, so keep it out of git.
 *  4. Every code change needs Deploy > Manage deployments > Edit > New version.
 *
 * GET  {exec}?token=...                 -> all tabs as JSON (header row -> keys)
 * GET  {exec}?token=...&tabs=Events,Daily  -> only those tabs
 * POST {exec}  body: {"token":"...","events":[{...}]}  -> appends to Events, idempotent by id
 *   NOTE: Apps Script answers every POST with a 302. Your doPost has already run;
 *   follow the Location header with a GET to read the JSON reply.
 */

const READ_TABS = [
  'Events', 'Daily', 'Daily Summary', 'Timeline', 'Spending',
  'Start Here', 'Study Bank', 'Study Sessions', 'Supplement Reference'
];

const EVENT_COLUMNS = [
  'id', 'date', 'time', 'end_time', 'type', 'qty', 'unit', 'label',
  'amount_inr', 'category', 'approx', 'source', 'note', 'created_at'
];

// Spend categories. 'bills' and 'one_off' are excluded from "daily burn".
const SPEND_CATEGORIES = [
  'canteen', 'street_food', 'delivery', 'tobacco', 'tea', 'groceries',
  'transport', 'grooming', 'bills', 'one_off', 'other'
];

const EVENT_TYPES = [
  'sleep', 'wake', 'weight', 'cigarette', 'tea', 'coffee', 'water_ml', 'meal',
  'snack', 'supplement', 'bus_board', 'bus_arrive', 'exercise', 'steps',
  'work', 'study', 'spend', 'energy', 'mood', 'note',
  'void' // undo: label = id of the event being cancelled. Rows are never deleted.
];

function doGet(e) {
  if (!authorised_(e.parameter.token)) return json_({ ok: false, error: 'unauthorised' });
  const wanted = e.parameter.tabs ? e.parameter.tabs.split(',') : READ_TABS;
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const out = { ok: true, generatedAt: new Date().toISOString(), tabs: {} };
  wanted.forEach(function (name) {
    const sh = ss.getSheetByName(name.trim());
    if (sh) out.tabs[name.trim()] = readTab_(sh);
  });
  return json_(out);
}

function doPost(e) {
  let body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return json_({ ok: false, error: 'bad json' });
  }
  if (!authorised_(body.token)) return json_({ ok: false, error: 'unauthorised' });
  if (!Array.isArray(body.events)) return json_({ ok: false, error: 'events[] required' });

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const sh = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Events');
    if (!sh) return json_({ ok: false, error: 'run setupEventsTab() first' });

    const last = sh.getLastRow();
    const existing = new Set(
      last > 1 ? sh.getRange(2, 1, last - 1, 1).getValues().map(function (r) { return String(r[0]); }) : []
    );

    const rows = [];
    const added = [];
    const skipped = [];
    body.events.forEach(function (ev) {
      if (!ev.id || existing.has(String(ev.id))) { skipped.push(ev.id || null); return; }
      if (EVENT_TYPES.indexOf(ev.type) === -1) { skipped.push(ev.id); return; }
      rows.push(EVENT_COLUMNS.map(function (c) {
        if (c === 'created_at') return new Date().toISOString();
        if (c === 'approx') return ev.approx === true;
        const v = ev[c];
        return v === undefined || v === null ? '' : v;
      }));
      existing.add(String(ev.id));
      added.push(ev.id);
    });

    if (rows.length) {
      sh.getRange(sh.getLastRow() + 1, 1, rows.length, EVENT_COLUMNS.length).setValues(rows);
    }
    return json_({ ok: true, added: added, skipped: skipped });
  } finally {
    lock.releaseLock();
  }
}

/** Run once from the editor. */
function setupEventsTab() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName('Events');
  if (!sh) sh = ss.insertSheet('Events');
  sh.getRange(1, 1, 1, EVENT_COLUMNS.length).setValues([EVENT_COLUMNS]).setFontWeight('bold');
  sh.setFrozenRows(1);
  // Keep date/time as plain text so the app gets "2026-11-17" / "18:02", not Date objects.
  sh.getRange('B:D').setNumberFormat('@');
  const rule = SpreadsheetApp.newDataValidation().requireValueInList(EVENT_TYPES, true).build();
  sh.getRange('E2:E').setDataValidation(rule);
}

function readTab_(sh) {
  const values = sh.getDataRange().getDisplayValues();
  if (values.length === 0) return [];
  const header = values[0].map(function (h) { return String(h).trim(); });
  const rows = [];
  for (let i = 1; i < values.length; i++) {
    const r = values[i];
    if (r.every(function (c) { return c === ''; })) continue;
    const obj = { _row: i + 1 };
    header.forEach(function (h, j) { if (h) obj[h] = r[j]; });
    rows.push(obj);
  }
  return rows;
}

function authorised_(token) {
  const expected = PropertiesService.getScriptProperties().getProperty('TOKEN');
  return Boolean(expected) && token === expected;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
