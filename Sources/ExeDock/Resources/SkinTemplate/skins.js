// Ten Playdocks - real per-skin card/topbar markup, ported from the original HTML mockups
// (ten-playdocks.html) and parameterized on real library data instead of the mockup's fake GAMES
// array. skins.css is the CSS half of the same port. Swift calls window.PlaydockRender(skinKey,
// gamesJSON, meta) after every load and whenever the underlying data changes; clicks route back to
// Swift through window.webkit.messageHandlers.playdock.postMessage(...) - the app's own established
// "tap a card opens the full Game Detail view" convention, not the mockup's own inline Launch button
// (that was a deliberate, hard-won fix from live feedback, kept intact here rather than reverted).
'use strict';

function esc(s) {
  return (s || '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

// Deterministic placeholder gradient for a game with no fetched artwork - keyed off its id so the
// same game always gets the same color, matching the native SwiftUI layouts' own placeholderTile.
function hueForID(id) {
  let h = 0;
  for (let i = 0; i < id.length; i++) { h = (h * 31 + id.charCodeAt(i)) >>> 0; }
  return h % 360;
}
function tile(hue, sat, angle) {
  return `linear-gradient(${angle || 135}deg, hsl(${hue} ${sat}% 38%), hsl(${(hue + 40) % 360} ${sat}% 20%))`;
}
function artStyle(gm, sat, angle) {
  if (gm.art) return `background-image:url('${gm.art}')`;
  return `background-image:${tile(hueForID(gm.id), sat || 45, angle)}`;
}

function postClick(id) {
  try { window.webkit.messageHandlers.playdock.postMessage({ id: id, action: 'open' }); } catch (e) {}
}

// Every card in every design below carries data-id + onclick="postClick('...')" - a single,
// consistent bridge point no matter which skin's markup wraps it.
const click = (id) => `onclick="postClick('${id}')"`;

/* ================= 1. Quiet Luxury ================= */
function design_luxury(games, meta) {
  const cards = games.map(gm => `
    <div class="card" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 45, 135)}">
        ${gm.custom ? '<span class="badge">Custom</span>' : ''}
      </div>
      <div class="body">
        <p class="title">${esc(gm.title)}</p>
        <p class="genre">${esc(gm.genre)}</p>
        <p class="desc">${esc(gm.desc)}</p>
        ${gm.running ? '<div class="run"><span class="dot"></span>Running</div>' : '<button class="cta">View Details</button>'}
      </div>
    </div>`).join('');
  return `
    <div class="lux">
      <div class="topbar">
        <div class="avatar"></div>
        <div><div class="who">${esc(meta.user)}</div><div class="count">${games.length} games</div></div>
        <div class="spacer"></div>
        <div class="search">Search your games</div>
      </div>
      <main>
        <h1>Your Library</h1>
        <p class="kicker">Installed and ready to play</p>
        <div class="grid">${cards}</div>
      </main>
    </div>`;
}

/* ================= 2. Glass ================= */
function design_glass(games, meta) {
  const cards = games.map(gm => `
    <div class="card" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 60, 120)}">${gm.custom ? '<span class="badge">Custom</span>' : ''}</div>
      <div class="body">
        <p class="title">${esc(gm.title)}</p>
        <p class="genre">${esc((gm.genre || '').toUpperCase())}</p>
        <p class="desc">${esc(gm.desc)}</p>
        ${gm.running ? '<div class="run"><span class="pulse"></span>Running</div>' : '<button class="cta">Launch</button>'}
      </div>
    </div>`).join('');
  return `
    <div class="glass">
      <div class="topbar">
        <div><div class="who">${esc(meta.user)}’s Library</div><div class="count">${games.length} games installed</div></div>
        <div class="spacer"></div>
        <div class="search">Search…</div>
      </div>
      <main><h1>Continue Playing</h1><div class="grid">${cards}</div></main>
    </div>`;
}

/* ================= 3. Neobrutalist ================= */
function design_brutal(games, meta) {
  const cards = games.map(gm => `
    <div class="card" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 80, 60)}">${gm.custom ? '<span class="badge">Custom</span>' : ''}</div>
      <div class="body">
        <p class="title">${esc(gm.title)}</p>
        <span class="genre">${esc(gm.genre)}</span>
        <p class="desc">${esc(gm.desc)}</p>
        ${gm.running ? '<button class="cta run">● Running</button>' : '<button class="cta">Launch →</button>'}
      </div>
    </div>`).join('');
  return `
    <div class="brut">
      <div class="topbar"><div class="who">PLAYDOCK</div><div class="count">${games.length} GAMES</div><div class="search">SEARCH YOUR GAMES_</div></div>
      <main><h1>Library</h1><div class="grid">${cards}</div></main>
    </div>`;
}

/* ================= 4. Cyberpunk terminal ================= */
function design_cyber(games, meta) {
  const runningCount = games.filter(g => g.running).length;
  const customCount = games.filter(g => g.custom).length;
  const cards = games.map(gm => `
    <div class="card" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 70, 140)}">${gm.custom ? '<span class="badge">CUSTOM</span>' : ''}</div>
      <div class="body">
        <p class="title">${esc(gm.title)}</p>
        <p class="genre">${esc(gm.genre)}</p>
        <p class="desc">${esc(gm.desc)}</p>
        ${gm.running ? '<button class="cta run">● RUNNING</button>' : '<button class="cta">LAUNCH ▸</button>'}
      </div>
    </div>`).join('');
  // A real status line instead of invented "connection secure" flavor text - the actual counts a
  // library owner would want at a glance, not stock hacker-movie dialogue.
  const kicker = runningCount > 0
    ? `${runningCount} running now`
    : `${games.length} games${customCount ? ` · ${customCount} custom` : ''}`;
  return `
    <div class="cyber">
      <div class="topbar"><span class="who">PLAY//DOCK</span><span class="count">${esc(meta.user)} · ${games.length} games</span><div class="spacer"></div><div class="search">&gt; search_<span class="cursor"></span></div></div>
      <main><h1>LIBRARY.SYS</h1><p class="kicker">${esc(kicker)}</p><div class="grid">${cards}</div></main>
    </div>`;
}

/* ================= 5. Neumorphic soft UI ================= */
function design_neu(games, meta) {
  const cards = games.map(gm => `
    <div class="card" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 25, 100)}">${gm.custom ? '<span class="badge">Custom</span>' : ''}</div>
      <p class="title">${esc(gm.title)}</p>
      <p class="genre">${esc(gm.genre)}</p>
      <p class="desc">${esc(gm.desc)}</p>
      ${gm.running ? '<button class="cta run">● Running</button>' : '<button class="cta">Launch</button>'}
    </div>`).join('');
  return `
    <div class="neu">
      <div class="topbar"><div class="avatar"></div><div><div class="who">${esc(meta.user)}</div><div class="count">${games.length} games</div></div><div class="spacer"></div><div class="search">Search your games</div></div>
      <main><h1>Your Library</h1><div class="grid">${cards}</div></main>
    </div>`;
}

/* ================= 6. Editorial magazine ================= */
function design_editorial(games, meta) {
  const feature = games[0];
  const rest = games.slice(1);
  const cards = rest.map(gm => `
    <div class="card" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 30, 80)}"></div>
      <p class="title">${esc(gm.title)}</p>
      <p class="genre">${esc(gm.genre)}${gm.custom ? ' · <span class="badge">Custom</span>' : ''}</p>
      <p class="desc dropcap">${esc(gm.desc)}</p>
      ${gm.running ? '<span class="run">Currently playing</span>' : ''}
    </div>`).join('');
  if (!feature) return `<div class="edit"><div class="topbar"><span class="who">The Library</span></div><main><h2>No games yet</h2></main></div>`;
  return `
    <div class="edit">
      <div class="topbar"><span class="who">The Library, No.${games.length}</span><span class="count">Curated for ${esc(meta.user)}</span></div>
      <main>
        <div class="feature" ${click(feature.id)}>
          <div class="art" style="${artStyle(feature, 35, 150)}"></div>
          <div>
            <p class="eyebrow">Featured${feature.running ? ' — playing now' : ''}</p>
            <h1>${esc(feature.title)}</h1>
            <p class="dropcap">${esc(feature.desc)}</p>
            <button class="cta">Continue Reading →</button>
          </div>
        </div>
        ${rest.length ? '<h2>Also in your collection</h2><div class="grid">' + cards + '</div>' : ''}
      </main>
    </div>`;
}

/* ================= 7. Retro pixel / arcade ================= */
function design_pixel(games, meta) {
  const cards = games.map(gm => `
    <div class="card" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 90, 100)}">${gm.custom ? '<span class="badge">MOD</span>' : ''}</div>
      <div class="body">
        <p class="title">${esc(gm.title)}</p>
        <p class="genre">${esc(gm.genre)}</p>
        <p class="desc">${esc(gm.desc)}</p>
        ${gm.running ? '<button class="cta run">■ LIVE</button>' : '<button class="cta">START ▶</button>'}
      </div>
    </div>`).join('');
  return `
    <div class="pix">
      <div class="topbar"><span class="who">PLAYDOCK</span><span class="count">P1: ${esc(meta.user.toUpperCase())} · ${games.length} CARTS</span><div class="spacer"></div><div class="search">FIND GAME_</div></div>
      <main><h1>SELECT GAME</h1><div class="grid">${cards}</div></main>
      <div class="prompt">PRESS A TO SELECT</div>
    </div>`;
}

/* ================= 8. Skeuomorphic console ================= */
function design_console(games, meta) {
  const screws = '<span class="screw" style="top:6px;left:6px"></span><span class="screw" style="top:6px;right:6px"></span><span class="screw" style="bottom:6px;left:6px"></span><span class="screw" style="bottom:6px;right:6px"></span>';
  const cards = games.map(gm => `
    <div class="card" ${click(gm.id)} style="position:relative">
      ${screws}
      <div class="art" style="${artStyle(gm, 35, 90)}">${gm.custom ? '<span class="badge">Custom</span>' : ''}</div>
      <div class="body">
        <p class="title">${esc(gm.title)}</p>
        <p class="genre">${esc(gm.genre)}</p>
        <p class="desc">${esc(gm.desc)}</p>
        ${gm.running ? '<button class="cta run"><span class="led"></span>Running</button>' : '<button class="cta">▶ Launch</button>'}
      </div>
    </div>`).join('');
  return `
    <div class="con">
      <div class="topbar"><span class="led"></span><span class="who">PLAYDOCK UNIT</span><span class="count">USER 01 · ${games.length} TITLES LOADED</span><div class="spacer"></div><div class="search">SEARCH LIBRARY</div></div>
      <main><h1>■ Game Select</h1><div class="grid">${cards}</div></main>
    </div>`;
}

/* ================= 9. Ultra-minimal list ================= */
function design_list(games, meta) {
  const rows = games.map(gm => `
    <div class="row" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 25, 90)}"></div>
      <div class="title">${esc(gm.title)}${gm.custom ? '<span class="badge">CUSTOM</span>' : ''}</div>
      <div class="genre">${esc(gm.genre)}</div>
      <div class="num">${esc(gm.size || '')}</div>
      <div class="num">${esc(gm.hours || '')}</div>
      <div class="status">${gm.running ? '<span class="run-pill">● Running</span>' : '<button class="launch">Launch →</button>'}</div>
    </div>`).join('');
  return `
    <div class="lst">
      <div class="topbar"><span class="who">Playdock</span><span class="count">${esc(meta.user)} · ${games.length} games</span><div class="spacer"></div><div class="search">Search</div></div>
      <main>
        <h1>Library</h1>
        <p class="sub">Sorted by name</p>
        <div class="head"><span></span><span>Title</span><span>Genre</span><span style="text-align:right">Size</span><span style="text-align:right">Played</span><span></span></div>
        ${rows}
      </main>
    </div>`;
}

/* ================= 10. Maximalist vaporwave ================= */
function design_vapor(games, meta) {
  const cards = games.map(gm => `
    <div class="card" ${click(gm.id)}>
      <div class="art" style="${artStyle(gm, 85, 150)}">${gm.custom ? '<span class="badge">Custom</span>' : ''}</div>
      <div class="body">
        <p class="title">${esc(gm.title)}</p>
        <p class="genre">${esc(gm.genre)}</p>
        <p class="desc">${esc(gm.desc)}</p>
        ${gm.running ? '<button class="cta run">● Running</button>' : '<button class="cta">Launch</button>'}
      </div>
    </div>`).join('');
  return `
    <div class="vap">
      <div class="sun"></div>
      <div class="topbar"><span class="who">PLAYDOCK</span><span class="count">${games.length} games · ${esc(meta.user)}</span><div class="spacer"></div><div class="search">Search…</div></div>
      <main><h1>Your Library</h1><div class="grid">${cards}</div></main>
    </div>`;
}

const DESIGNS = {
  luxury: design_luxury,
  glass: design_glass,
  brutalist: design_brutal,
  cyber: design_cyber,
  soft: design_neu,
  editorial: design_editorial,
  pixel: design_pixel,
  console: design_console,
  minimal: design_list,
  vapor: design_vapor,
};

// Called from Swift via evaluateJavaScript after every load and whenever the underlying data or
// active skin/theme changes - a full re-render each time is simple, correct, and cheap enough for a
// library of even a few hundred games.
window.PlaydockRender = function (skinKey, gamesJSON, metaJSON) {
  const stage = document.getElementById('stage');
  const build = DESIGNS[skinKey] || DESIGNS.luxury;
  let games, meta;
  try { games = JSON.parse(gamesJSON); } catch (e) { games = []; }
  try { meta = JSON.parse(metaJSON); } catch (e) { meta = { user: 'Player', theme: 'light' }; }
  document.documentElement.setAttribute('data-stage-theme', meta.theme === 'dark' ? 'dark' : 'light');
  stage.innerHTML = build(games, meta);
};
