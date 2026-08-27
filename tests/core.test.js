// Minimal unit tests for the pure-logic core (normalize / computeColumns /
// serialize / JSON parsing via loadJSONText / addRecord / sorting).
//
// json-deck.html has no build step and wires its whole IIFE straight into
// real DOM elements at load time (see the "Wire up controls" section), so
// these internals can't be pulled out and run in plain Node. Instead we load
// the actual file in a headless browser and reach into it through a
// test-only hook (window.__TEST__ / window.__jsonLedgerTest, see
// json-deck.html) that stays inert unless a harness explicitly sets
// window.__TEST__ = true first.
//
// Run with: npm test  (requires `npm install` once, for the playwright devDependency)

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { chromium } = require('playwright');

const INDEX_HTML_URL = 'file://' + path.resolve(__dirname, '..', 'json-deck.html');

let browser, page;

test.before(async () => {
  browser = await chromium.launch();
  page = await browser.newPage();
  await page.addInitScript(() => { window.__TEST__ = true; });
  await page.goto(INDEX_HTML_URL);
});

test.after(async () => {
  await browser.close();
});

function callTest(fnName, ...args){
  return page.evaluate(({ fnName, args }) => window.__jsonLedgerTest[fnName](...args), { fnName, args });
}

function getState(){
  return page.evaluate(() => window.__jsonLedgerTest.state);
}

function setState(patch){
  return page.evaluate((patch) => Object.assign(window.__jsonLedgerTest.state, patch), patch);
}

// ---------------- initial state ----------------

test('initial state: view defaults to card', async () => {
  const state = await getState();
  assert.equal(state.view, 'card');
});

// ---------------- normalize() ----------------

test('normalize: top-level array of objects becomes root-array', async () => {
  const result = await callTest('normalize', [{ name: 'A' }, { name: 'B' }]);
  assert.deepEqual(result.wrapper, { type: 'root-array' });
  assert.deepEqual(result.records, [{ name: 'A' }, { name: 'B' }]);
});

test('normalize: object with one array property is "wrapped", other keys preserved as rest', async () => {
  const input = { store: 'My Shop', menu: [{ name: 'Item A' }] };
  const result = await callTest('normalize', input);
  assert.equal(result.wrapper.type, 'wrapped');
  assert.equal(result.wrapper.key, 'menu');
  assert.deepEqual(result.wrapper.rest, input);
  assert.deepEqual(result.records, [{ name: 'Item A' }]);
});

test('normalize: object with no array property is a single-object record', async () => {
  const input = { name: 'Item A', price: 500 };
  const result = await callTest('normalize', input);
  assert.deepEqual(result.wrapper, { type: 'single-object' });
  assert.deepEqual(result.records, [input]);
});

// ---------------- computeColumns() ----------------

test('computeColumns: unions keys across records in first-seen order, no duplicates', async () => {
  await setState({ records: [{ a: 1, b: 2 }, { b: 3, c: 4 }, { a: 5 }], showAddedAt: false });
  await callTest('computeColumns');
  const state = await getState();
  assert.deepEqual(state.columns, ['a', 'b', 'c']);
});

test('computeColumns: _added_at is excluded by default even if present on records', async () => {
  await setState({
    records: [{ name: 'A', _added_at: '2026-08-20T00:00:00.000Z' }],
    showAddedAt: false
  });
  await callTest('computeColumns');
  const state = await getState();
  assert.deepEqual(state.columns, ['name']);
});

test('computeColumns: _added_at is included when showAddedAt is true', async () => {
  await setState({
    records: [{ name: 'A', _added_at: '2026-08-20T00:00:00.000Z' }],
    showAddedAt: true
  });
  await callTest('computeColumns');
  const state = await getState();
  assert.deepEqual(state.columns, ['name', '_added_at']);
  await setState({ showAddedAt: false }); // reset for later tests
});

// ---------------- serialize() ----------------

test('serialize: root-array wrapper returns the records array as-is', async () => {
  await setState({ wrapper: { type: 'root-array' }, records: [{ x: 1 }] });
  const out = await callTest('serialize');
  assert.deepEqual(out, [{ x: 1 }]);
});

test('serialize: wrapped wrapper reassembles the original object shape', async () => {
  await setState({
    wrapper: { type: 'wrapped', key: 'menu', rest: { store: 'My Shop', menu: [] } },
    records: [{ name: 'Item A' }]
  });
  const out = await callTest('serialize');
  assert.deepEqual(out, { store: 'My Shop', menu: [{ name: 'Item A' }] });
});

test('serialize: single-object wrapper returns just the first record', async () => {
  await setState({ wrapper: { type: 'single-object' }, records: [{ name: 'Item A' }] });
  const out = await callTest('serialize');
  assert.deepEqual(out, { name: 'Item A' });
});

// ---------------- loadJSONText() (JSON parsing) ----------------

test('loadJSONText: valid JSON populates state and returns true', async () => {
  const ok = await callTest('loadJSONText', '[{"name":"Item A"}]', 'sample.json');
  assert.equal(ok, true);
  const state = await getState();
  assert.deepEqual(state.records, [{ name: 'Item A' }]);
  assert.equal(state.fileName, 'sample.json');
  assert.equal(state.dirty, false);
});

test('loadJSONText: malformed JSON returns false and does not touch state.records', async () => {
  await setState({ records: [{ keep: 'me' }] });
  const ok = await callTest('loadJSONText', '{ not valid json', 'broken.json');
  assert.equal(ok, false);
  const state = await getState();
  assert.deepEqual(state.records, [{ keep: 'me' }]);
});

test('loadJSONText: records missing _added_at are left as-is, not backfilled', async () => {
  await callTest('loadJSONText', '[{"name":"Item A"}]', 'no-added-at.json');
  const state = await getState();
  assert.equal('_added_at' in state.records[0], false);
});

// ---------------- addRecord() ----------------

test('addRecord: stamps the new record with an ISO8601 _added_at', async () => {
  await callTest('loadJSONText', '[{"name":"Item A"}]', 'for-add.json');
  await setState({ wrapper: { type: 'root-array' } });
  await callTest('addRecord');
  const state = await getState();
  const added = state.records[state.records.length - 1]._added_at;
  assert.equal(typeof added, 'string');
  assert.ok(!isNaN(Date.parse(added)), '_added_at parses as a valid date: ' + added);
  assert.ok(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(added), '_added_at looks like toISOString() output: ' + added);
});

// ---------------- Sorting (getDisplayOrder / compareSortValues) ----------------

test('getDisplayOrder: sortKey null returns original index order', async () => {
  await setState({ records: [{ v: 3 }, { v: 1 }, { v: 2 }], sortKey: null });
  const order = await callTest('getDisplayOrder');
  assert.deepEqual(order, [0, 1, 2]);
});

test('getDisplayOrder: sorts numbers ascending and descending without mutating state.records', async () => {
  await setState({ records: [{ v: 3 }, { v: 1 }, { v: 2 }], sortKey: 'v', sortDir: 'asc' });
  let order = await callTest('getDisplayOrder');
  assert.deepEqual(order, [1, 2, 0]); // records[1].v=1, records[2].v=2, records[0].v=3

  await setState({ sortDir: 'desc' });
  order = await callTest('getDisplayOrder');
  assert.deepEqual(order, [0, 2, 1]);

  const state = await getState();
  assert.deepEqual(state.records, [{ v: 3 }, { v: 1 }, { v: 2 }], 'state.records order is untouched by sorting');
});

test('getDisplayOrder: sorts ISO8601 date strings chronologically, not lexicographically by locale', async () => {
  await setState({
    records: [
      { d: '2026-08-20T00:00:00.000Z' },
      { d: '2024-01-01T00:00:00.000Z' },
      { d: '2025-06-15T00:00:00.000Z' }
    ],
    sortKey: 'd', sortDir: 'asc'
  });
  const order = await callTest('getDisplayOrder');
  assert.deepEqual(order, [1, 2, 0]);
});

test('getDisplayOrder: sorts plain strings via localeCompare', async () => {
  await setState({ records: [{ s: 'banana' }, { s: 'apple' }, { s: 'cherry' }], sortKey: 's', sortDir: 'asc' });
  const order = await callTest('getDisplayOrder');
  assert.deepEqual(order, [1, 0, 2]);
});

test('getDisplayOrder: records missing the sort key always sort last, in both directions', async () => {
  await setState({
    records: [{ v: 5 }, {}, { v: 1 }, {}],
    sortKey: 'v', sortDir: 'asc'
  });
  let order = await callTest('getDisplayOrder');
  assert.deepEqual(order, [2, 0, 1, 3], 'ascending: defined values first (1, 5), then the two missing ones');

  await setState({ sortDir: 'desc' });
  order = await callTest('getDisplayOrder');
  assert.deepEqual(order, [0, 2, 1, 3], 'descending: defined values first (5, 1), missing ones still last');
});

test('compareSortValues: both missing compares equal', async () => {
  const result = await callTest('compareSortValues', undefined, undefined, 'asc');
  assert.equal(result, 0);
});

// ---------------- formatAddedAt() (display-only formatting) ----------------

test('formatAddedAt: formats a valid ISO8601 UTC string as JST, distinct from the raw string', async () => {
  const raw = '2026-08-20T11:25:15.000Z'; // 20:25:15 JST
  const formatted = await callTest('formatAddedAt', raw);
  assert.notEqual(formatted, raw, 'display string differs from the stored raw ISO string');
  assert.ok(formatted.includes('2026'), 'formatted string mentions the year: ' + formatted);
  assert.ok(formatted.includes('20:25:15') || formatted.includes('8:20'), 'formatted string reads as JST wall-clock time: ' + formatted);
});

test('formatAddedAt: empty/undefined values pass through unchanged', async () => {
  assert.equal(await callTest('formatAddedAt', ''), '');
  assert.equal(await callTest('formatAddedAt', undefined), undefined);
});

test('formatAddedAt: unparseable strings pass through unchanged rather than becoming "Invalid Date"', async () => {
  const junk = 'not a date';
  assert.equal(await callTest('formatAddedAt', junk), junk);
});

// ---------------- isTagLikeArray() / arrayCellKind() (tag vs. list threshold) ----------------

test('isTagLikeArray: true when every element is at or under TAG_MAX_CHARS (20)', async () => {
  assert.equal(await callTest('isTagLikeArray', ['官民ファンド', '歴史的類似事例']), true);
});

test('isTagLikeArray: false when even one element exceeds TAG_MAX_CHARS', async () => {
  const longItem = 'CJ機構：政策目標達成、点の個別投資、政治・官僚の思惑、官僚と有識者懇談会が運用';
  assert.equal(await callTest('isTagLikeArray', ['短いタグ', longItem]), false);
});

test('arrayCellKind: an array of short strings is "tag"', async () => {
  assert.equal(await callTest('arrayCellKind', ['人気', '定番'], 'tags'), 'tag');
});

test('arrayCellKind: an array containing one long string is "list", even with short elements mixed in', async () => {
  const longItem = 'これは20文字を大きく超える長い説明文の要素です、以上、テスト用の文言です';
  assert.equal(await callTest('arrayCellKind', ['短い', longItem], 'keyPoints'), 'list');
});

// ---------------- UI: tag chips vs. plain list rendering, and tagFilter interaction ----------------

test('UI: a short-string array renders as tag chips; clicking one sets state.tagFilter and filters rows', async () => {
  await setState({ view: 'table' });
  await callTest('loadJSONText', JSON.stringify([
    { name: 'Item A', tags: ['人気', '定番'] },
    { name: 'Item B', tags: ['季節限定'] }
  ]), 'tag-ui.json');

  const tagChipCount = await page.$$eval('#tbody .tag', els => els.length);
  assert.equal(tagChipCount, 3, 'renders one .tag chip per tag value across both rows');

  await page.click('#tbody .tag .tag-text >> text=人気');
  let state = await getState();
  assert.equal(state.tagFilter, '人気', 'clicking a tag chip sets state.tagFilter');

  const visibleRows = await page.$$eval('#tbody tr', rows => rows.length);
  assert.equal(visibleRows, 1, 'only the matching record row is shown');

  await setState({ tagFilter: null });
});

test('UI: an array with a long element renders as a plain list; clicking it does not touch state.tagFilter', async () => {
  await setState({ view: 'table' });
  const longItem = 'これは20文字を大きく超える長い説明文の要素です、以上、テスト用の文言です';
  await callTest('loadJSONText', JSON.stringify([
    { name: 'Item C', keyPoints: ['短い', longItem] }
  ]), 'list-ui.json');

  const listItemCount = await page.$$eval('#tbody .plain-list-item', els => els.length);
  assert.equal(listItemCount, 2, 'renders one .plain-list-item per element (the whole array is list-kind)');

  const tagChipCount = await page.$$eval('#tbody .tag', els => els.length);
  assert.equal(tagChipCount, 0, 'no .tag chips are rendered for a list-kind array');

  await page.click('#tbody .plain-list-item .plain-list-text >> nth=0');
  const state = await getState();
  assert.equal(state.tagFilter, null, 'clicking list text does not set state.tagFilter');
});

// ---------------- updateFileTag() record count (query + tagFilter combined) ----------------

test('fileTagText: tag-only filtering shows "filtered / total", matching the visible rows', async () => {
  await setState({ view: 'table' });
  await callTest('loadJSONText', JSON.stringify([
    { name: 'Apple Pie', tags: ['Popular'] },
    { name: 'Apple Tart', tags: ['Seasonal'] },
    { name: 'Banana Split', tags: ['Popular'] },
    { name: 'Cherry Cake', tags: ['Seasonal'] }
  ]), 'filetag-count.json');

  await setState({ tagFilter: 'Popular' });
  await callTest('render');
  let text = await page.textContent('#fileTagText');
  assert.match(text, /2\s*\/\s*4件/, 'tag-only filter shows 2 / 4件: ' + text);

  let visibleRows = await page.$$eval('#tbody tr', rows => rows.length);
  assert.equal(visibleRows, 2, 'table shows exactly the 2 matching rows');

  await setState({ tagFilter: null });
});

test('fileTagText: search-only filtering still shows "filtered / total" (regression check)', async () => {
  await setState({ query: 'Cherry' });
  await callTest('render');
  const text = await page.textContent('#fileTagText');
  assert.match(text, /1\s*\/\s*4件/, 'search-only filter shows 1 / 4件: ' + text);

  const visibleRows = await page.$$eval('#tbody tr', rows => rows.length);
  assert.equal(visibleRows, 1, 'table shows exactly the 1 matching row');

  await setState({ query: '' });
});

test('fileTagText: search + tag combined counts only records matching both, matching the visible rows', async () => {
  await setState({ query: 'Apple', tagFilter: 'Popular' });
  await callTest('render');
  const text = await page.textContent('#fileTagText');
  assert.match(text, /1\s*\/\s*4件/, 'combined filters narrow to the single record matching both: ' + text);

  const visibleRows = await page.$$eval('#tbody tr', rows => rows.length);
  assert.equal(visibleRows, 1, 'table shows exactly the 1 row matching both filters');

  await setState({ query: '', tagFilter: null });
});

test('fileTagText: clearing all filters restores the plain total count', async () => {
  await callTest('render');
  const text = await page.textContent('#fileTagText');
  assert.match(text, /4件$/, 'no filters active: shows the plain total, no "x /": ' + text);
  assert.ok(!text.includes('/'), 'no "/" in the unfiltered count: ' + text);

  const visibleRows = await page.$$eval('#tbody tr', rows => rows.length);
  assert.equal(visibleRows, 4, 'all 4 rows are visible again');
});

// ---------------- Record-level JSON view/edit ("{ }" button) ----------------
// openJsonModalGeneric's overlay is created fresh (never gets a "hidden" class) and removed on
// close, unlike the always-present static modals (#pasteModalOverlay etc.) which stay in the DOM
// with "hidden" toggled. ".modal-overlay:not(.hidden)" reliably targets just this dynamic modal.

test('table: the "{ }" button opens a modal pre-filled with that record\'s JSON', async () => {
  await callTest('loadJSONText', JSON.stringify([
    { name: 'Item A', price: 100 },
    { name: 'Item B', price: 200 }
  ]), 'record-json.json');
  await setState({ view: 'table' });
  await callTest('render');

  await page.click('#tbody tr:nth-child(1) button[title="レコードのJSONを表示・編集"]');
  const ta = page.locator('.modal-overlay:not(.hidden) textarea');
  assert.equal(await ta.inputValue(), JSON.stringify({ name: 'Item A', price: 100 }, null, 2));
  await page.click('.modal-overlay:not(.hidden) >> text=キャンセル');
});

test('card: the "{ }" button opens a modal pre-filled with that record\'s JSON', async () => {
  await setState({ view: 'card' });
  await callTest('render');

  await page.click('#cardGrid .rec-card:nth-child(2) button[title="レコードのJSONを表示・編集"]');
  const ta = page.locator('.modal-overlay:not(.hidden) textarea');
  assert.equal(await ta.inputValue(), JSON.stringify({ name: 'Item B', price: 200 }, null, 2));
  await page.click('.modal-overlay:not(.hidden) >> text=キャンセル');
  await setState({ view: 'table' });
  await callTest('render');
});

test('record JSON modal: saving valid JSON replaces the record and adds new keys as columns', async () => {
  await page.click('#tbody tr:nth-child(1) button[title="レコードのJSONを表示・編集"]');
  const ta = page.locator('.modal-overlay:not(.hidden) textarea');
  await ta.fill(JSON.stringify({ name: 'Item A', price: 150, note: 'on sale' }, null, 2));
  await page.click('.modal-overlay:not(.hidden) >> text=保存');
  await page.waitForTimeout(100);

  const state = await getState();
  assert.deepEqual(state.records[0], { name: 'Item A', price: 150, note: 'on sale' });
  assert.ok(state.columns.includes('note'), 'new key from the pasted JSON becomes a column: ' + JSON.stringify(state.columns));
});

test('record JSON modal: invalid JSON shows an error and does not close the modal', async () => {
  await page.click('#tbody tr:nth-child(1) button[title="レコードのJSONを表示・編集"]');
  const ta = page.locator('.modal-overlay:not(.hidden) textarea');
  await ta.fill('{ not valid json');
  await page.click('.modal-overlay:not(.hidden) >> text=保存');
  await page.waitForTimeout(50);

  assert.equal(await page.locator('.modal-overlay:not(.hidden)').count(), 1, 'modal stays open on invalid JSON');
  const err = await page.textContent('.modal-overlay:not(.hidden) .modal-err');
  assert.match(err, /⚠/);
  await page.click('.modal-overlay:not(.hidden) >> text=キャンセル');
});

// ---------------- Nested object field: always-expanded code block instead of a collapsed "{...} 編集" chip ----------------

test('table: a nested object field renders as an always-expanded JSON code block, not a collapsed "{...}" chip', async () => {
  await setState({ view: 'table' });
  await callTest('loadJSONText', JSON.stringify([
    { name: 'Item A', dimensions: { w: 10, h: 20, d: 5 } }
  ]), 'nested-obj.json');
  await callTest('render');

  const blockText = await page.textContent('#tbody .obj-json-block');
  assert.equal(blockText, JSON.stringify({ w: 10, h: 20, d: 5 }, null, 2),
    'shows the object as pretty-printed JSON, matching JSON.stringify(value, null, 2)');

  const collapsedChipCount = await page.locator('#tbody >> text=/^\\{\\.\\.\\.\\}/').count();
  assert.equal(collapsedChipCount, 0, 'no collapsed "{...}" chip remains for a nested object');
});

test('table: the "編集" chip next to a nested object opens the existing edit modal, pre-filled, and saving updates the always-expanded view', async () => {
  await page.click('#tbody .obj-json-wrap >> text=編集');
  const ta = page.locator('.modal-overlay:not(.hidden) textarea');
  assert.equal(await ta.inputValue(), JSON.stringify({ w: 10, h: 20, d: 5 }, null, 2),
    'modal is pre-filled with the nested object\'s current JSON, same as before this change');

  await ta.fill(JSON.stringify({ w: 99, h: 20, d: 5 }, null, 2));
  await page.click('.modal-overlay:not(.hidden) >> text=保存');
  await page.waitForTimeout(100);

  const state = await getState();
  assert.deepEqual(state.records[0].dimensions, { w: 99, h: 20, d: 5 }, 'saving from the modal still updates the record');

  const blockText = await page.textContent('#tbody .obj-json-block');
  assert.equal(blockText, JSON.stringify({ w: 99, h: 20, d: 5 }, null, 2),
    'the always-expanded view reflects the saved value without needing to re-expand anything');
});

test('card: a nested object field renders the same always-expanded code block as table view', async () => {
  await setState({ view: 'card' });
  await callTest('render');

  const blockText = await page.textContent('#cardGrid .obj-json-block');
  assert.equal(blockText, JSON.stringify({ w: 99, h: 20, d: 5 }, null, 2));

  await setState({ view: 'table' });
  await callTest('render');
});

test('nested object display change does not affect tag chip rendering on the same record', async () => {
  await callTest('loadJSONText', JSON.stringify([
    { name: 'Item A', tags: ['人気', '定番'], dimensions: { w: 1, h: 2, d: 3 } }
  ]), 'nested-obj-with-tags.json');
  await callTest('render');

  const tagChipCount = await page.$$eval('#tbody .tag', els => els.length);
  assert.equal(tagChipCount, 2, 'tags still render as tag chips, unaffected by the nested-object display change');

  const objBlockCount = await page.locator('#tbody .obj-json-block').count();
  assert.equal(objBlockCount, 1, 'the nested object field still gets its own always-expanded code block');
});
