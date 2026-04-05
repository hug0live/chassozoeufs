const STORAGE_KEYS = {
  deviceLabel: 'egg-hunt.device-label',
  hostGameId: 'egg-hunt.host-game-id',
  playerClaims: 'egg-hunt.player-claims',
};

const appEl = document.querySelector('#app');

const state = {
  hideSpots: [],
  hideSpotMap: new Map(),
  groupedHideSpots: new Map(),
  game: null,
  socket: null,
  socketGameId: null,
  socketStatus: 'idle',
  reconnectTimer: null,
  loading: false,
  notice: null,
  trackedEggId: null,
  hintStartedAt: null,
  deviceLabel: loadDeviceLabel(),
  hostGameId: localStorage.getItem(STORAGE_KEYS.hostGameId) || '',
  playerClaims: loadPlayerClaims(),
  create: null,
};

state.create = createDefaultDraft();

boot().catch((error) => {
  console.error(error);
  showNotice(error.message || String(error), 'error');
});

appEl.addEventListener('click', (event) => {
  const target = event.target.closest('[data-action]');
  if (!target) {
    return;
  }
  const { action } = target.dataset;
  void handleAction(action, target);
});

appEl.addEventListener('change', (event) => {
  const target = event.target;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLSelectElement)) {
    return;
  }
  handleFieldChange(target);
});

window.addEventListener('beforeunload', () => {
  disconnectSocket();
});

setInterval(() => {
  updateHuntTimer();
}, 1000);

async function boot() {
  await loadCatalog();
  await refreshActiveGame();
  render();
}

async function handleAction(action, target) {
  switch (action) {
    case 'refresh':
      await refreshActiveGame();
      break;
    case 'add-player':
      addPlayer();
      break;
    case 'remove-player':
      removePlayer(target.dataset.playerName || '');
      break;
    case 'add-egg':
      addEggDraft();
      break;
    case 'remove-egg':
      removeEggDraft(Number(target.dataset.eggId));
      break;
    case 'create-game':
      await createGame();
      break;
    case 'claim-player':
      await claimPlayer(target.dataset.playerId || '');
      break;
    case 'leave-player':
      await leaveCurrentPlayer();
      break;
    case 'mark-found':
      await markCurrentEggFound();
      break;
    case 'close-game':
      await closeCurrentGame();
      break;
    default:
      break;
  }
}

function handleFieldChange(target) {
  if (target.id === 'device-label') {
    state.deviceLabel = target.value.trim() || state.deviceLabel;
    localStorage.setItem(STORAGE_KEYS.deviceLabel, state.deviceLabel);
    render();
    return;
  }

  if (target.id === 'game-title') {
    state.create.title = target.value;
    return;
  }

  if (target.id === 'host-name') {
    state.create.hostName = target.value;
    return;
  }

  if (!target.dataset.eggId) {
    return;
  }

  const eggId = Number(target.dataset.eggId);
  const draft = state.create.eggs.find((item) => item.id === eggId);
  if (!draft) {
    return;
  }

  if (target.dataset.field === 'player') {
    draft.playerName = target.value;
  }

  if (target.dataset.field === 'area') {
    draft.area = target.value;
    const options = hideSpotsForArea(draft.area);
    draft.hideSpotId = options[0]?.id || '';
  }

  if (target.dataset.field === 'hideSpotId') {
    draft.hideSpotId = target.value;
  }

  render();
}

async function loadCatalog() {
  const payload = await requestJson('/api/catalog/hide-spots');
  state.hideSpots = payload.hideSpots || [];
  state.hideSpotMap = new Map(state.hideSpots.map((spot) => [spot.id, spot]));
  state.groupedHideSpots = new Map();
  for (const spot of state.hideSpots) {
    const group = state.groupedHideSpots.get(spot.area) || [];
    group.push(spot);
    state.groupedHideSpots.set(spot.area, group);
  }
}

async function refreshActiveGame() {
  setLoading(true);
  try {
    const payload = await requestJson('/api/games/active');
    applyGameSnapshot(payload.game || null);
    clearNotice('error');
  } catch (error) {
    showNotice(error.message || String(error), 'error');
  } finally {
    setLoading(false);
  }
}

function applyGameSnapshot(game) {
  const previousGameId = state.game?.id || '';
  state.game = game && game.status === 'active' ? game : null;

  if (!state.game) {
    if (previousGameId) {
      clearSessionForGame(previousGameId);
    }
    state.hostGameId = '';
    localStorage.removeItem(STORAGE_KEYS.hostGameId);
    state.trackedEggId = null;
    state.hintStartedAt = null;
    disconnectSocket();
    render();
    return;
  }

  if (state.hostGameId && state.hostGameId !== state.game.id) {
    localStorage.removeItem(STORAGE_KEYS.hostGameId);
    state.hostGameId = '';
  }

  const claimedPlayerId = getClaimedPlayerId(state.game.id);
  if (claimedPlayerId) {
    const player = state.game.players.find((item) => item.id === claimedPlayerId);
    if (!player || player.claimedBy !== state.deviceLabel) {
      setClaimedPlayerId(state.game.id, null);
    }
  }

  syncHintTimer();
  connectSocket(state.game.id);
  render();
}

function createDefaultDraft() {
  const areas = [...state.groupedHideSpots.keys()];
  const firstArea = areas[0] || '';
  const firstSpot = hideSpotsForArea(firstArea)[0];
  return {
    title: 'Chasse du dimanche',
    hostName: 'Maitre du jeu',
    players: [],
    eggs: [],
    nextEggId: 1,
    playerInput: '',
    area: firstArea,
    hideSpotId: firstSpot?.id || '',
  };
}

function resetCreateDraft() {
  state.create = createDefaultDraft();
}

function addPlayer() {
  const input = document.querySelector('#new-player');
  if (!(input instanceof HTMLInputElement)) {
    return;
  }
  const value = input.value.trim();
  if (!value) {
    return;
  }
  if (state.create.players.some((name) => name.toLowerCase() === value.toLowerCase())) {
    input.value = '';
    return;
  }
  state.create.players.push(value);
  input.value = '';
  if (state.create.eggs.length === 0) {
    addEggDraft(false);
  }
  render();
}

function removePlayer(playerName) {
  state.create.players = state.create.players.filter((name) => name !== playerName);
  state.create.eggs = state.create.eggs.filter((egg) => egg.playerName !== playerName);
  if (state.create.players.length > 0) {
    for (const egg of state.create.eggs) {
      if (!state.create.players.includes(egg.playerName)) {
        egg.playerName = state.create.players[0];
      }
    }
  }
  render();
}

function addEggDraft(shouldRender = true) {
  if (state.create.players.length === 0) {
    return;
  }
  const areas = [...state.groupedHideSpots.keys()];
  const area = areas[0] || '';
  const firstSpot = hideSpotsForArea(area)[0];
  state.create.eggs.push({
    id: state.create.nextEggId++,
    playerName: state.create.players[0],
    area,
    hideSpotId: firstSpot?.id || '',
  });
  if (shouldRender) {
    render();
  }
}

function removeEggDraft(eggId) {
  state.create.eggs = state.create.eggs.filter((egg) => egg.id !== eggId);
  render();
}

async function createGame() {
  if (state.create.players.length === 0 || state.create.eggs.length === 0) {
    showNotice('Ajoute au moins un joueur et un oeuf.', 'error');
    return;
  }

  setLoading(true);
  try {
    const payload = await requestJson('/api/games', {
      method: 'POST',
      body: JSON.stringify({
        title: state.create.title.trim(),
        hostName: state.create.hostName.trim(),
        players: state.create.players,
        eggs: state.create.eggs.map((egg) => ({
          playerName: egg.playerName,
          hideSpotId: egg.hideSpotId,
        })),
      }),
    });
    state.hostGameId = payload.game.id;
    localStorage.setItem(STORAGE_KEYS.hostGameId, state.hostGameId);
    resetCreateDraft();
    applyGameSnapshot(payload.game);
    showNotice('La partie est ouverte. Les autres appareils peuvent rejoindre la meme URL.', 'info');
  } catch (error) {
    showNotice(error.message || String(error), 'error');
  } finally {
    setLoading(false);
  }
}

async function claimPlayer(playerId) {
  if (!state.game) {
    return;
  }
  setLoading(true);
  try {
    const payload = await requestJson(`/api/games/${state.game.id}/join`, {
      method: 'POST',
      body: JSON.stringify({
        playerId,
        claimedBy: state.deviceLabel,
      }),
    });
    setClaimedPlayerId(state.game.id, playerId);
    applyGameSnapshot(payload.game);
    showNotice('Le joueur est reserve sur cet appareil.', 'info');
  } catch (error) {
    showNotice(error.message || String(error), 'error');
  } finally {
    setLoading(false);
  }
}

async function leaveCurrentPlayer() {
  const game = state.game;
  const playerId = game ? getClaimedPlayerId(game.id) : null;
  if (!game || !playerId) {
    return;
  }
  setLoading(true);
  try {
    const payload = await requestJson(`/api/games/${game.id}/leave`, {
      method: 'POST',
      body: JSON.stringify({
        playerId,
        claimedBy: state.deviceLabel,
      }),
    });
    setClaimedPlayerId(game.id, null);
    state.trackedEggId = null;
    state.hintStartedAt = null;
    applyGameSnapshot(payload.game);
  } catch (error) {
    showNotice(error.message || String(error), 'error');
  } finally {
    setLoading(false);
  }
}

async function markCurrentEggFound() {
  const game = state.game;
  const playerId = game ? getClaimedPlayerId(game.id) : null;
  const egg = currentEgg();
  if (!game || !playerId || !egg) {
    return;
  }
  setLoading(true);
  try {
    const payload = await requestJson(
      `/api/games/${game.id}/eggs/${egg.id}/found`,
      {
        method: 'POST',
        body: JSON.stringify({ playerId }),
      },
    );
    applyGameSnapshot(payload.game);
  } catch (error) {
    showNotice(error.message || String(error), 'error');
  } finally {
    setLoading(false);
  }
}

async function closeCurrentGame() {
  if (!state.game) {
    return;
  }
  if (!window.confirm('Clore la partie en cours ?')) {
    return;
  }
  setLoading(true);
  try {
    await requestJson(`/api/games/${state.game.id}/close`, {
      method: 'POST',
      body: JSON.stringify({}),
    });
    clearSessionForGame(state.game.id);
    state.hostGameId = '';
    localStorage.removeItem(STORAGE_KEYS.hostGameId);
    disconnectSocket();
    await refreshActiveGame();
  } catch (error) {
    showNotice(error.message || String(error), 'error');
    setLoading(false);
  }
}

function connectSocket(gameId) {
  if (state.socketGameId === gameId && state.socket) {
    return;
  }

  disconnectSocket(false);
  state.socketStatus = 'connecting';
  state.socketGameId = gameId;

  const url = new URL(`/ws/games/${gameId}`, window.location.href);
  url.protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';

  const socket = new WebSocket(url);
  state.socket = socket;

  socket.addEventListener('open', () => {
    state.socketStatus = 'open';
    render();
  });

  socket.addEventListener('message', (event) => {
    try {
      const payload = JSON.parse(event.data);
      if (payload.type === 'snapshot') {
        applyGameSnapshot(payload.game || null);
      }
    } catch (error) {
      console.error(error);
    }
  });

  socket.addEventListener('close', () => {
    if (state.socket === socket) {
      state.socket = null;
      state.socketStatus = state.game ? 'closed' : 'idle';
      render();
      scheduleReconnect(gameId);
    }
  });

  socket.addEventListener('error', () => {
    state.socketStatus = 'closed';
    render();
  });
}

function disconnectSocket(resetStatus = true) {
  if (state.reconnectTimer) {
    clearTimeout(state.reconnectTimer);
    state.reconnectTimer = null;
  }
  if (state.socket) {
    state.socket.close();
    state.socket = null;
  }
  state.socketGameId = null;
  if (resetStatus) {
    state.socketStatus = 'idle';
  }
}

function scheduleReconnect(gameId) {
  if (!state.game || state.game.id !== gameId || state.reconnectTimer) {
    return;
  }
  state.reconnectTimer = window.setTimeout(() => {
    state.reconnectTimer = null;
    if (state.game && state.game.id === gameId) {
      connectSocket(gameId);
    }
  }, 2500);
}

function currentView() {
  if (!state.game) {
    return 'create';
  }
  if (state.hostGameId === state.game.id) {
    return 'host';
  }
  if (getClaimedPlayerId(state.game.id)) {
    return 'hunt';
  }
  return 'picker';
}

function currentPlayer() {
  if (!state.game) {
    return null;
  }
  const playerId = getClaimedPlayerId(state.game.id);
  return state.game.players.find((player) => player.id === playerId) || null;
}

function currentEgg() {
  const player = currentPlayer();
  if (!state.game || !player) {
    return null;
  }
  const eggs = eggsForPlayer(player.id);
  return eggs.find((egg) => !egg.foundAt) || null;
}

function eggsForPlayer(playerId) {
  if (!state.game) {
    return [];
  }
  return [...state.game.eggs]
    .filter((egg) => egg.playerId === playerId)
    .sort((left, right) => left.order - right.order);
}

function syncHintTimer() {
  const egg = currentEgg();
  if (!egg) {
    state.trackedEggId = null;
    state.hintStartedAt = null;
    return;
  }
  if (state.trackedEggId !== egg.id) {
    state.trackedEggId = egg.id;
    state.hintStartedAt = Date.now();
  }
}

function updateHuntTimer() {
  if (currentView() !== 'hunt') {
    return;
  }
  const timerEl = document.querySelector('[data-role="hint-timer"]');
  const hintEl = document.querySelector('[data-role="hint-box"]');
  const egg = currentEgg();
  if (!timerEl || !hintEl || !egg) {
    return;
  }

  const unlocked = isHintUnlocked();
  timerEl.textContent = unlocked
    ? "L'indice est maintenant disponible."
    : `Indice dans ${remainingHintLabel()}.`;

  hintEl.innerHTML = unlocked
    ? `<strong>Indice :</strong> ${escapeHtml(hideSpotById(egg.hideSpotId)?.hint || '')}`
    : "Tiens bon encore un peu : l'indice s'affichera automatiquement apres 5 minutes.";
  hintEl.className = unlocked ? 'hint' : 'hint hint--locked';
}

function render() {
  appEl.innerHTML = `
    ${renderHero()}
    <section class="stack">
      ${state.notice ? renderNotice() : ''}
      ${renderBody()}
    </section>
  `;
  updateHuntTimer();
}

function renderHero() {
  const activeLabel = state.game
    ? `${state.game.title} · ${currentViewLabel()}`
    : 'Aucune partie active';
  const deviceLocked = Boolean(
    state.game &&
      (state.hostGameId === state.game.id || getClaimedPlayerId(state.game.id)),
  );
  return `
    <section class="hero">
      <div class="hero__top">
        <span class="pill">Une seule URL pour tous les joueurs</span>
        <span class="pill">${escapeHtml(activeLabel)}</span>
        <span class="pill">${escapeHtml(socketLabel())}</span>
      </div>
      <div class="hero__body">
        <div>
          <h1>Chasse aux oeufs monolithique</h1>
          <p>
            Le Raspberry heberge directement l'application complete : interface web,
            API et synchronisation temps reel. Chaque appareil ouvre la meme adresse.
          </p>
        </div>
        <div class="hero__controls">
          <div class="field">
            <label for="device-label">Nom de cet appareil</label>
            <input
              id="device-label"
              value="${escapeHtml(state.deviceLabel)}"
              ${deviceLocked ? 'disabled' : ''}
            />
          </div>
          <div class="footer-note">
            ${deviceLocked
              ? "Le nom de l'appareil reste fige pendant la partie pour eviter les conflits de reservation."
              : "Choisis un nom simple. Il sera utilise pour reserver un joueur dans la partie."}
          </div>
        </div>
      </div>
    </section>
  `;
}

function renderNotice() {
  return `
    <div class="banner banner--${state.notice.type}">
      ${escapeHtml(state.notice.text)}
    </div>
  `;
}

function renderBody() {
  switch (currentView()) {
    case 'host':
      return renderHostView();
    case 'picker':
      return renderPickerView();
    case 'hunt':
      return renderHuntView();
    default:
      return renderCreateView();
  }
}

function renderCreateView() {
  return `
    <section class="grid grid--two">
      <article class="card">
        <div class="card__header">
          <div>
            <h2 class="card__title">Nouvelle partie</h2>
            <p class="card__subtitle">
              Le maitre du jeu prepare la liste des joueurs, puis configure les cachettes.
              Tous les autres appareils rejoindront ensuite la meme URL.
            </p>
          </div>
          <button class="button button--secondary" data-action="refresh" ${disabledAttr()}>
            Actualiser
          </button>
        </div>
        <div class="grid">
          <div class="field">
            <label for="game-title">Nom de la partie</label>
            <input id="game-title" value="${escapeHtml(state.create.title)}" />
          </div>
          <div class="field">
            <label for="host-name">Nom du maitre du jeu</label>
            <input id="host-name" value="${escapeHtml(state.create.hostName)}" />
          </div>
        </div>
        <div class="card__header" style="margin-top: 22px;">
          <div>
            <h3 class="card__title">Joueurs</h3>
            <p class="card__subtitle">
              Ajoute les enfants ou joueurs qui auront chacun leurs enigmes.
            </p>
          </div>
        </div>
        <div class="row">
          <div class="field grow">
            <label for="new-player">Ajouter un joueur</label>
            <input id="new-player" placeholder="Ex. Zoe" />
          </div>
          <button class="button button--primary" data-action="add-player">Ajouter</button>
        </div>
        <div class="chip-list" style="margin-top: 14px;">
          ${state.create.players.length
            ? state.create.players
                .map(
                  (player) => `
                    <span class="chip">
                      ${escapeHtml(player)}
                      <button data-action="remove-player" data-player-name="${escapeHtml(player)}">
                        retirer
                      </button>
                    </span>
                  `,
                )
                .join('')
            : '<div class="empty">Aucun joueur ajoute pour le moment.</div>'}
        </div>
      </article>
      <article class="card card--soft">
        <div class="card__header">
          <div>
            <h2 class="card__title">Oeufs et cachettes</h2>
            <p class="card__subtitle">
              Chaque oeuf est lie a un joueur et a une enigme difficile predefinie.
            </p>
          </div>
          <button
            class="button button--secondary"
            data-action="add-egg"
            ${state.create.players.length ? '' : 'disabled'}
          >
            Ajouter un oeuf
          </button>
        </div>
        ${
          state.create.eggs.length
            ? `<div class="draft-list">${state.create.eggs.map(renderEggDraft).join('')}</div>`
            : '<div class="empty">Ajoute d abord au moins un joueur puis configure une premiere cachette.</div>'
        }
        <div class="row" style="margin-top: 18px;">
          <button
            class="button button--primary"
            data-action="create-game"
            ${state.create.players.length && state.create.eggs.length ? '' : 'disabled'}
          >
            Ouvrir la partie
          </button>
        </div>
      </article>
    </section>
  `;
}

function renderEggDraft(draft) {
  const areas = [...state.groupedHideSpots.keys()];
  const spots = hideSpotsForArea(draft.area);
  const currentSpot = hideSpotById(draft.hideSpotId);
  return `
    <article class="draft">
      <div class="draft__head">
        <div>
          <strong>Oeuf a cacher</strong>
          <div class="muted">Attribue un joueur et une cachette precise.</div>
        </div>
        <button class="button button--ghost" data-action="remove-egg" data-egg-id="${draft.id}">
          Retirer
        </button>
      </div>
      <div class="grid">
        <div class="field">
          <label>Pour quel joueur ?</label>
          <select data-egg-id="${draft.id}" data-field="player">
            ${state.create.players
              .map(
                (player) => `
                  <option value="${escapeHtml(player)}" ${player === draft.playerName ? 'selected' : ''}>
                    ${escapeHtml(player)}
                  </option>
                `,
              )
              .join('')}
          </select>
        </div>
        <div class="field">
          <label>Piece ou zone</label>
          <select data-egg-id="${draft.id}" data-field="area">
            ${areas
              .map(
                (area) => `
                  <option value="${escapeHtml(area)}" ${area === draft.area ? 'selected' : ''}>
                    ${escapeHtml(area)}
                  </option>
                `,
              )
              .join('')}
          </select>
        </div>
        <div class="field">
          <label>Objet ou cachette</label>
          <select data-egg-id="${draft.id}" data-field="hideSpotId">
            ${spots
              .map(
                (spot) => `
                  <option value="${spot.id}" ${spot.id === draft.hideSpotId ? 'selected' : ''}>
                    ${escapeHtml(spot.objectLabel)}
                  </option>
                `,
              )
              .join('')}
          </select>
        </div>
      </div>
      <div class="muted"><strong>Enigme :</strong> ${escapeHtml(currentSpot?.riddle || '')}</div>
      <div class="muted"><strong>Indice apres 5 minutes :</strong> ${escapeHtml(currentSpot?.hint || '')}</div>
    </article>
  `;
}

function renderHostView() {
  const game = state.game;
  if (!game) {
    return '';
  }
  return `
    <article class="card">
      <div class="card__header">
        <div>
          <h2 class="card__title">${escapeHtml(game.title)}</h2>
          <p class="card__subtitle">
            Partie ouverte par ${escapeHtml(game.hostName)}. Les autres appareils rejoignent la meme URL.
          </p>
        </div>
        <div class="row">
          <button class="button button--secondary" data-action="refresh" ${disabledAttr()}>
            Actualiser
          </button>
          <button class="button button--danger" data-action="close-game" ${disabledAttr()}>
            Clore la partie
          </button>
        </div>
      </div>
      <div class="summary">
        <div class="summary__item">${game.players.length} joueur(s)</div>
        <div class="summary__item">${game.eggs.length} oeuf(s)</div>
        <div class="summary__item">Synchronisation ${escapeHtml(socketLabel())}</div>
      </div>
    </article>
    <section class="grid grid--two">
      <article class="card">
        <div class="card__header">
          <div>
            <h2 class="card__title">Suivi des joueurs</h2>
            <p class="card__subtitle">
              Les progres se mettent a jour automatiquement.
            </p>
          </div>
        </div>
        <div class="tile-list">
          ${game.players.map(renderHostPlayerTile).join('')}
        </div>
      </article>
      <article class="card card--soft">
        <div class="card__header">
          <div>
            <h2 class="card__title">Cachettes configurees</h2>
            <p class="card__subtitle">
              Chaque ligne rappelle pour quel joueur l'oeuf a ete cache.
            </p>
          </div>
        </div>
        <div class="tile-list">
          ${game.eggs.map(renderHostEggTile).join('')}
        </div>
      </article>
    </section>
  `;
}

function renderHostPlayerTile(player) {
  const eggs = eggsForPlayer(player.id);
  const foundCount = eggs.filter((egg) => egg.foundAt).length;
  const ratio = eggs.length ? (foundCount / eggs.length) * 100 : 0;
  return `
    <article class="tile">
      <div style="flex: 1 1 auto;">
        <h3 class="tile__title">${escapeHtml(player.name)}</h3>
        <div class="tile__meta">
          ${player.claimedBy ? `Reserve par ${escapeHtml(player.claimedBy)}.` : 'Pas encore reserve.'}
        </div>
        <div class="progress" style="margin-top: 12px;">
          <span style="width: ${ratio}%;"></span>
        </div>
      </div>
      <div class="tile__aside">${foundCount} / ${eggs.length}</div>
    </article>
  `;
}

function renderHostEggTile(egg) {
  const player = state.game.players.find((item) => item.id === egg.playerId);
  const spot = hideSpotById(egg.hideSpotId);
  const tileClass = egg.foundAt ? 'tile tile--success' : 'tile tile--pending';
  return `
    <article class="${tileClass}">
      <div>
        <h3 class="tile__title">${escapeHtml(spot?.area || 'Cachette')} · ${escapeHtml(spot?.objectLabel || 'Inconnue')}</h3>
        <div class="tile__meta">Attribue a ${escapeHtml(player?.name || 'Inconnu')}</div>
      </div>
      <div class="tile__aside">${egg.foundAt ? 'Trouve' : 'Cache'}</div>
    </article>
  `;
}

function renderPickerView() {
  const game = state.game;
  if (!game) {
    return '';
  }
  return `
    <article class="card">
      <div class="card__header">
        <div>
          <h2 class="card__title">${escapeHtml(game.title)}</h2>
          <p class="card__subtitle">
            Choisis le nom prepare par le maitre du jeu pour commencer la chasse.
          </p>
        </div>
        <button class="button button--secondary" data-action="refresh" ${disabledAttr()}>
          Actualiser
        </button>
      </div>
      <div class="tile-list">
        ${game.players.map(renderPickerTile).join('')}
      </div>
    </article>
  `;
}

function renderPickerTile(player) {
  const eggs = eggsForPlayer(player.id);
  const foundCount = eggs.filter((egg) => egg.foundAt).length;
  const lockedByOther = player.claimedBy && player.claimedBy !== state.deviceLabel;
  return `
    <article class="tile ${lockedByOther ? '' : 'tile--pending'}">
      <div>
        <h3 class="tile__title">${escapeHtml(player.name)}</h3>
        <div class="tile__meta">
          ${eggs.length} oeuf(s) a chercher, ${foundCount} deja trouves.
          ${player.claimedBy ? `<br />Reserve par ${escapeHtml(player.claimedBy)}.` : ''}
        </div>
      </div>
      <div class="tile__aside">
        <button
          class="button ${lockedByOther ? 'button--ghost' : 'button--primary'}"
          data-action="claim-player"
          data-player-id="${player.id}"
          ${lockedByOther ? 'disabled' : disabledAttr()}
        >
          ${lockedByOther ? 'Occupe' : 'Choisir'}
        </button>
      </div>
    </article>
  `;
}

function renderHuntView() {
  const game = state.game;
  const player = currentPlayer();
  if (!game || !player) {
    return '';
  }
  const eggs = eggsForPlayer(player.id);
  const foundCount = eggs.filter((egg) => egg.foundAt).length;
  const egg = currentEgg();
  const spot = egg ? hideSpotById(egg.hideSpotId) : null;
  return `
    <article class="card">
      <div class="card__header">
        <div>
          <h2 class="card__title">Tour de ${escapeHtml(player.name)}</h2>
          <p class="card__subtitle">
            Progression : ${foundCount} / ${eggs.length} oeuf(s) trouves.
          </p>
        </div>
        <div class="row">
          <button class="button button--secondary" data-action="refresh" ${disabledAttr()}>
            Synchroniser
          </button>
          <button class="button button--ghost" data-action="leave-player" ${disabledAttr()}>
            Changer de joueur
          </button>
        </div>
      </div>
      <div class="progress">
        <span style="width: ${eggs.length ? (foundCount / eggs.length) * 100 : 0}%;"></span>
      </div>
    </article>
    ${
      egg && spot
        ? `
          <article class="card card--soft">
            <div class="card__header">
              <div>
                <h2 class="card__title">Enigme en cours</h2>
                <p class="card__subtitle" data-role="hint-timer">${remainingHintLine()}</p>
              </div>
            </div>
            <div class="riddle">${escapeHtml(spot.riddle)}</div>
            <div class="${isHintUnlocked() ? 'hint' : 'hint hint--locked'}" data-role="hint-box" style="margin-top: 16px;">
              ${
                isHintUnlocked()
                  ? `<strong>Indice :</strong> ${escapeHtml(spot.hint)}`
                  : "Tiens bon encore un peu : l'indice s'affichera automatiquement apres 5 minutes."
              }
            </div>
            <div class="row" style="margin-top: 18px;">
              <button class="button button--primary" data-action="mark-found" ${disabledAttr()}>
                Trouve !
              </button>
            </div>
          </article>
        `
        : `
          <article class="card card--soft">
            <div class="card__header">
              <div>
                <h2 class="card__title">Tous les oeufs sont trouves</h2>
                <p class="card__subtitle">
                  Bravo, ce joueur a termine sa chasse.
                </p>
              </div>
            </div>
          </article>
        `
    }
    <article class="card">
      <div class="card__header">
        <div>
          <h2 class="card__title">Journal du joueur</h2>
          <p class="card__subtitle">
            Les cachettes ne sont revelees qu'une fois l'oeuf valide.
          </p>
        </div>
      </div>
      <div class="tile-list">
        ${eggs.map(renderHistoryTile).join('')}
      </div>
    </article>
  `;
}

function renderHistoryTile(egg) {
  const spot = hideSpotById(egg.hideSpotId);
  const done = Boolean(egg.foundAt);
  return `
    <article class="tile ${done ? 'tile--success' : ''}">
      <div>
        <h3 class="tile__title">
          ${done ? `${escapeHtml(spot?.area || '')} · ${escapeHtml(spot?.objectLabel || '')}` : 'Enigme a venir'}
        </h3>
        <div class="tile__meta">${done ? 'Cachette revelee.' : 'Le secret reste entier.'}</div>
      </div>
      <div class="tile__aside">${done ? 'Trouve' : 'En attente'}</div>
    </article>
  `;
}

function currentViewLabel() {
  switch (currentView()) {
    case 'host':
      return 'Tableau maitre du jeu';
    case 'picker':
      return 'Choix du joueur';
    case 'hunt':
      return 'Enigme en cours';
    default:
      return 'Creation de partie';
  }
}

function socketLabel() {
  switch (state.socketStatus) {
    case 'open':
      return 'WebSocket connecte';
    case 'connecting':
      return 'Connexion en cours';
    case 'closed':
      return 'Reconnexion prochaine';
    default:
      return 'Attente';
  }
}

function remainingHintLine() {
  return isHintUnlocked()
    ? "L'indice est maintenant disponible."
    : `Indice dans ${remainingHintLabel()}.`;
}

function remainingHintLabel() {
  if (!state.hintStartedAt) {
    return '05:00';
  }
  const elapsedMs = Date.now() - state.hintStartedAt;
  const remainingMs = Math.max(0, 5 * 60 * 1000 - elapsedMs);
  const minutes = String(Math.floor(remainingMs / 60000)).padStart(2, '0');
  const seconds = String(Math.floor((remainingMs % 60000) / 1000)).padStart(2, '0');
  return `${minutes}:${seconds}`;
}

function isHintUnlocked() {
  return Boolean(state.hintStartedAt) && Date.now() - state.hintStartedAt >= 5 * 60 * 1000;
}

function hideSpotsForArea(area) {
  return state.groupedHideSpots.get(area) || [];
}

function hideSpotById(hideSpotId) {
  return state.hideSpotMap.get(hideSpotId) || null;
}

function loadDeviceLabel() {
  const existing = localStorage.getItem(STORAGE_KEYS.deviceLabel);
  if (existing && existing.trim()) {
    return existing;
  }
  const generated = `Appareil ${100 + Math.floor(Math.random() * 900)}`;
  localStorage.setItem(STORAGE_KEYS.deviceLabel, generated);
  return generated;
}

function loadPlayerClaims() {
  try {
    const raw = localStorage.getItem(STORAGE_KEYS.playerClaims);
    if (!raw) {
      return {};
    }
    const parsed = JSON.parse(raw);
    return typeof parsed === 'object' && parsed ? parsed : {};
  } catch {
    return {};
  }
}

function getClaimedPlayerId(gameId) {
  return state.playerClaims[gameId] || null;
}

function setClaimedPlayerId(gameId, playerId) {
  if (!gameId) {
    return;
  }
  if (playerId) {
    state.playerClaims[gameId] = playerId;
  } else {
    delete state.playerClaims[gameId];
  }
  localStorage.setItem(STORAGE_KEYS.playerClaims, JSON.stringify(state.playerClaims));
}

function clearSessionForGame(gameId) {
  if (!gameId) {
    return;
  }
  setClaimedPlayerId(gameId, null);
  if (state.hostGameId === gameId) {
    state.hostGameId = '';
    localStorage.removeItem(STORAGE_KEYS.hostGameId);
  }
}

function showNotice(text, type = 'info') {
  state.notice = { text, type };
  render();
}

function clearNotice(type) {
  if (!state.notice) {
    return;
  }
  if (!type || state.notice.type === type) {
    state.notice = null;
    render();
  }
}

function setLoading(value) {
  state.loading = value;
  render();
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });

  const raw = await response.text();
  const payload = raw ? JSON.parse(raw) : {};
  if (!response.ok) {
    throw new Error(payload.error || `Erreur ${response.status}`);
  }
  return payload;
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function disabledAttr() {
  return state.loading ? 'disabled' : '';
}
