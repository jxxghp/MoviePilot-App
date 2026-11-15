import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../../ios/MoviePilot/Resources/LanguageBootstrap.js', import.meta.url), 'utf8');

/** Execute the shipped bootstrap with isolated storage and DOM mutation callbacks. */
function page({ saved, selected = null, fallback = 'zh-CN', origin = 'https://example.test', child = false, denied = false } = {}) {
  const messages = [];
  const values = new Map(saved ? [['MP_LOCALE', saved]] : []);
  let mutation;
  const document = { documentElement: { lang: 'en' } };
  const window = { webkit: { messageHandlers: { moviepilotLanguage: { postMessage: message => messages.push(message) } } } };
  window.top = child ? {} : window;
  runInNewContext(source.replace('/*__MOVIEPILOT_LANGUAGE__*/', JSON.stringify({ origin: 'https://example.test:443', selected, fallback })), {
    window, document, location: { origin }, URL,
    localStorage: {
      getItem: key => { if (denied) throw new Error('disabled'); return values.get(key) ?? null; },
      setItem: (key, value) => { if (denied) throw new Error('disabled'); values.set(key, value); },
    },
    MutationObserver: class {
      constructor(callback) { mutation = callback; }
      observe() {}
    },
  });
  return { values, messages, change(locale, persist = true) {
    if (persist) values.set('MP_LOCALE', locale);
    document.documentElement.lang = locale;
    mutation?.();
  } };
}

test('keeps an existing web preference and reports web changes without duplicates', () => {
  const current = page({ saved: 'zh-TW', fallback: 'en-US' });
  assert.equal(current.values.get('MP_LOCALE'), 'zh-TW');
  assert.equal(current.messages[0].locale, 'zh-TW');
  current.change('en-US');
  current.change('en-US');
  assert.equal(current.messages.length, 2);
  assert.equal(current.messages[1].locale, 'en-US');
  current.change('zh-CN', false);
  assert.equal(current.messages.length, 2);
});

test('only an explicit selection overrides the instance and missing settings inherit the App', () => {
  assert.equal(page({ saved: 'zh-TW', selected: 'en-US' }).values.get('MP_LOCALE'), 'en-US');
  assert.equal(page({ saved: 'unsupported', fallback: 'zh-TW' }).values.get('MP_LOCALE'), 'zh-TW');
  assert.equal(page({ fallback: 'en-US' }).messages[0].locale, 'en-US');
  assert.equal(page({ saved: 'zh-TW', selected: 'javascript:bad' }).values.get('MP_LOCALE'), 'zh-TW');
});

test('rejects other origins, subframes, storage failure and unsupported live values', () => {
  for (const settings of [{ origin: 'https://other.test' }, { child: true }, { denied: true }]) {
    const current = page(settings);
    assert.equal(current.messages.length, 0);
    assert.equal(current.values.size, 0);
  }
  const current = page();
  current.change('fr-FR');
  assert.equal(current.messages.length, 1);
});
