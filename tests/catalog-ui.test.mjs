import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const program = html.match(/<script>([\s\S]+?)<\/script>/)[1];

function element(tagName) {
  return {
    tagName,
    children: [],
    textContent: '',
    disabled: false,
    get firstElementChild() { return this.children[0]; },
    append(...children) { this.children.push(...children); },
    replaceChildren(...children) { this.children = children; },
    addEventListener(type, listener) { this[type] = listener; },
  };
}

async function openWith(response) {
  const list = element('div');
  list.append(element('p'));
  const previous = element('button');
  const shuffle = element('button');
  previous.disabled = shuffle.disabled = true;
  const selected = element('div');
  const ids = { trackList: list, previousTrack: previous, shuffleTracks: shuffle, nowPlaying: selected };
  const window = {};
  runInNewContext(program, {
    window,
    document: { createElement: element, getElementById: id => ids[id] },
    fetch: async () => response,
  });
  await window.onload();
  return { list, previous, shuffle, selected };
}

test('pistes et navigation utilisent des boutons et conservent le titre littéral', async () => {
  const tracks = [
    { title: "L'art & <le son>", artist: 'Artiste', duration: '04:08' },
    { title: 'Deuxième morceau', artist: 'Autre', duration: '01:32' },
  ];
  const { list, previous, shuffle, selected } = await openWith({ ok: true, json: async () => ({ tracks }) });
  const [first, second] = list.children;
  assert.equal(first.tagName, 'button');
  assert.equal(first.children[0].children[0].textContent, tracks[0].title);
  assert.equal(shuffle.disabled, false);
  second.click();
  assert.equal(selected.textContent, tracks[1].title);
  assert.equal(previous.disabled, false);
  previous.click();
  assert.equal(selected.textContent, tracks[0].title);
  assert.equal(previous.disabled, true);
});

test('le catalogue vide et le serveur indisponible ont des messages distincts', async () => {
  const empty = await openWith({ ok: true, json: async () => ({ tracks: [] }) });
  assert.match(empty.list.firstElementChild.textContent, /Aucune piste/);
  assert.equal(empty.shuffle.disabled, true);
  const failed = await openWith({ ok: false });
  assert.match(failed.list.firstElementChild.textContent, /Impossible de charger/);
  assert.equal(failed.shuffle.disabled, true);
});
