const STORAGE_KEYS = {
  deviceLabel: 'egg-hunt.device-label',
  hostGameIds: 'egg-hunt.host-game-ids',
  playerClaims: 'egg-hunt.player-claims',
};

const appEl = document.querySelector('#app');

const state = {
  hideSpots: [],
  hideSpotMap: new Map(),
  groupedHideSpots: new Map(),
  games: [],
  game: null,
  selectedGameId: '',
  socket: null,
  socketGameId: null,
  socketStatus: 'idle',
  reconnectTimer: null,
  loading: false,
  notice: null,
  trackedEggId: null,
  hintStartedAt: null,
  deviceLabel: loadDeviceLabel(),
  hostGameIds: loadHostGameIds(),
  playerClaims: loadPlayerClaims(),
  create: null,
};

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
  if (
    !(
      target instanceof HTMLInputElement ||
      target instanceof HTMLSelectElement ||
      target instanceof HTMLTextAreaElement
    )
  ) {
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
  state.create = createDefaultDraft();
  await refreshGames();
  render();
}

async function handleAction(action, target) {
  switch (action) {
    case 'refresh':
      await refreshGames();
      break;
    case 'go-lobby':
      goLobby();
      break;
    case 'select-game':
      selectGame(target.dataset.gameId || '');
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
    case 'delete-game':
      await deleteGame(target.dataset.gameId || '');
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

  if (!state.create) {
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

  if (target.id === 'game-code') {
    state.create.adminCode = normalizeAdminCode(target.value);
    render();
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
    render();
    return;
  }

  if (target.dataset.field === 'mode') {
    draft.mode = target.value === 'custom' ? 'custom' : 'catalog';
    if (draft.mode === 'catalog' && !draft.hideSpotId) {
      const options = hideSpotsForArea(draft.area);
      draft.hideSpotId = options[0]?.id || '';
    }
    if (draft.mode === 'custom' && !draft.customArea.trim()) {
      draft.customArea = draft.area;
    }
    render();
    return;
  }

  if (target.dataset.field === 'area') {
    draft.area = target.value;
    const options = hideSpotsForArea(draft.area);
    draft.hideSpotId = options[0]?.id || '';
    render();
    return;
  }

  if (target.dataset.field === 'hideSpotId') {
    draft.hideSpotId = target.value;
    render();
    return;
  }

  if (target.dataset.field === 'customArea') {
    draft.customArea = target.value;
    render();
    return;
  }

  if (target.dataset.field === 'customObjectLabel') {
    draft.customObjectLabel = target.value;
    render();
    return;
  }

  if (target.dataset.field === 'customRiddle') {
    draft.customRiddle = target.value;
    render();
    return;
  }

  if (target.dataset.field === 'customHint') {
    draft.customHint = target.value;
    render();
  }
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

async function refreshGames() {
  setLoading(true);
  try {
    const payload = await requestJson('/api/games');
    state.games = (payload.games || [])
      .filter((game) => game.status === 'active')
      .sort((left, right) => new Date(right.updatedAt) - new Date(left.updatedAt));

    pruneLocalSelections();

    const selectedGame = state.games.find((game) => game.id === state.selectedGameId) || null;
    applySelectedGame(selectedGame);
    clearNotice('error');
  } catch (error) {
    showNotice(error.message || String(error), 'error');
  } finally {
    setLoading(false);
  }
}

function pruneLocalSelections() {
  const activeIds = new Set(state.games.map((game) => game.id));

  state.hostGameIds = state.hostGameIds.filter((gameId) => activeIds.has(gameId));
  saveHostGameIds();

  let claimsChanged = false;
  for (const [gameId, playerId] of Object.entries(state.playerClaims)) {
    const game = state.games.find((item) => item.id === gameId);
    const player = game?.players.find((item) => item.id === playerId);
    if (!player || player.claimedBy !== state.deviceLabel) {
      delete state.playerClaims[gameId];
      claimsChanged = true;
    }
  }
  if (claimsChanged) {
    savePlayerClaims();
  }

  if (state.selectedGameId && !activeIds.has(state.selectedGameId)) {
    clearSelectedGame();
  }
}

function applySelectedGame(game) {
  state.game = game;

  if (!game) {
    state.trackedEggId = null;
    state.hintStartedAt = null;
    disconnectSocket();
    render();
    return;
  }

  const claimedPlayerId = getClaimedPlayerId(game.id);
  if (claimedPlayerId) {
    const player = game.players.find((item) => item.id === claimedPlayerId);
    if (!player || player.claimedBy !== state.deviceLabel) {
      setClaimedPlayerId(game.id, null);
    }
  }

  syncHintTimer();
  connectSocket(game.id);
  render();
}

function createDefaultDraft() {
  return {
    title: 'Grande chasse',
    hostName: 'Grand lapin',
    adminCode: '',
    players: [],
    eggs: [],
    nextEggId: 1,
  };
}

function resetCreateDraft() {
  state.create = createDefaultDraft();
}

function createEggDraft(id, playerName = '') {
  const areas = [...state.groupedHideSpots.keys()];
  const area = areas[0] || '';
  const firstSpot = hideSpotsForArea(area)[0];
  return {
    id,
    playerName,
    mode: 'catalog',
    area,
    hideSpotId: firstSpot?.id || '',
    customArea: area,
    customObjectLabel: '',
    customRiddle: '',
    customHint: '',
  };
}

function addPlayer() {
  if (!state.create) {
    return;
  }
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
  if (!state.create) {
    return;
  }
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
  if (!state.create || state.create.players.length === 0) {
    return;
  }
  state.create.eggs.push(
    createEggDraft(state.create.nextEggId++, state.create.players[0]),
  );
  if (shouldRender) {
    render();
  }
}

function removeEggDraft(eggId) {
  if (!state.create) {
    return;
  }
  state.create.eggs = state.create.eggs.filter((egg) => egg.id !== eggId);
  render();
}

function allEggDraftsReady() {
  return Boolean(
    state.create &&
      isAdminCodeReady(state.create.adminCode) &&
      state.create.eggs.length &&
      state.create.eggs.every(isEggDraftReady),
  );
}

function isAdminCodeReady(value) {
  return /^\d{4}$/.test(value || '');
}

function normalizeAdminCode(value) {
  return String(value ?? '')
    .replaceAll(/\D/g, '')
    .slice(0, 4);
}

function isEggDraftReady(draft) {
  if (!draft.playerName) {
    return false;
  }
  if (draft.mode === 'custom') {
    return [
      draft.customArea,
      draft.customObjectLabel,
      draft.customRiddle,
      draft.customHint,
    ].every((value) => value.trim());
  }
  return Boolean(draft.hideSpotId);
}

function previewHideSpotForDraft(draft) {
  if (draft.mode === 'custom') {
    return {
      area: draft.customArea.trim(),
      objectLabel: draft.customObjectLabel.trim(),
      riddle: draft.customRiddle.trim(),
      hint: draft.customHint.trim(),
    };
  }
  return hideSpotById(draft.hideSpotId);
}

async function createGame() {
  if (!state.create || state.create.players.length === 0 || state.create.eggs.length === 0) {
    showNotice('Ajoute au moins un joueur et un oeuf.', 'error');
    return;
  }
  if (!isAdminCodeReady(state.create.adminCode)) {
    showNotice('Ajoute un code a 4 chiffres.', 'error');
    return;
  }
  if (!allEggDraftsReady()) {
    showNotice('Complete chaque cachette.', 'error');
    return;
  }

  setLoading(true);
  try {
    const payload = await requestJson('/api/games', {
      method: 'POST',
      body: JSON.stringify({
        title: state.create.title.trim(),
        hostName: state.create.hostName.trim(),
        adminCode: state.create.adminCode,
        players: state.create.players,
        eggs: state.create.eggs.map((egg) => {
          if (egg.mode === 'custom') {
            return {
              playerName: egg.playerName,
              customHideSpot: {
                area: egg.customArea.trim(),
                objectLabel: egg.customObjectLabel.trim(),
                riddle: egg.customRiddle.trim(),
                hint: egg.customHint.trim(),
              },
            };
          }
          return {
            playerName: egg.playerName,
            hideSpotId: egg.hideSpotId,
          };
        }),
      }),
    });

    addHostGameId(payload.game.id);
    setSelectedGameId(payload.game.id);
    upsertGame(payload.game);
    resetCreateDraft();
    applySelectedGame(payload.game);
    showNotice('Nouvelle partie ouverte !', 'info');
  } catch (error) {
    showNotice(error.message || String(error), 'error');
  } finally {
    setLoading(false);
  }
}

async function deleteGame(gameId) {
  const game = state.games.find((item) => item.id === gameId) || state.game;
  if (!game) {
    return;
  }
  const adminCode = promptForAdminCode(game.title);
  if (adminCode == null) {
    return;
  }

  setLoading(true);
  try {
    await requestJson(`/api/games/${gameId}/close`, {
      method: 'POST',
      body: JSON.stringify({ adminCode }),
    });
    removeHostGameId(gameId);
    clearSessionForGame(gameId);
    if (state.selectedGameId === gameId) {
      goLobby(false);
    }
    await refreshGames();
    showNotice('Partie supprimee.', 'info');
  } catch (error) {
    showNotice(error.message || String(error), 'error');
  } finally {
    setLoading(false);
  }
}

function promptForAdminCode(gameTitle) {
  const value = window.prompt(
    `Code de "${gameTitle}"`,
    '',
  );
  if (value == null) {
    return null;
  }
  const normalized = normalizeAdminCode(value);
  if (!isAdminCodeReady(normalized)) {
    showNotice('Entre 4 chiffres.', 'error');
    return null;
  }
  return normalized;
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
    upsertGame(payload.game);
    applySelectedGame(payload.game);
    showNotice("C'est parti !", 'info');
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
    upsertGame(payload.game);
    applySelectedGame(payload.game);
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
    const payload = await requestJson(`/api/games/${game.id}/eggs/${egg.id}/found`, {
      method: 'POST',
      body: JSON.stringify({ playerId }),
    });
    upsertGame(payload.game);
    applySelectedGame(payload.game);
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
  await deleteGame(state.game.id);
}

function selectGame(gameId) {
  const game = state.games.find((item) => item.id === gameId);
  if (!game) {
    return;
  }
  setSelectedGameId(gameId);
  applySelectedGame(game);
}

function goLobby(shouldRender = true) {
  clearSelectedGame();
  state.game = null;
  state.trackedEggId = null;
  state.hintStartedAt = null;
  disconnectSocket();
  if (shouldRender) {
    render();
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
        mergeGameSnapshot(payload.game || null);
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

function mergeGameSnapshot(game) {
  if (!game || game.status !== 'active') {
    if (game?.id) {
      state.games = state.games.filter((item) => item.id !== game.id);
      removeHostGameId(game.id);
      clearSessionForGame(game.id);
      if (state.selectedGameId === game.id) {
        goLobby(false);
      }
    }
    render();
    return;
  }

  upsertGame(game);
  if (state.selectedGameId === game.id) {
    applySelectedGame(game);
  } else {
    render();
  }
}

function upsertGame(game) {
  const index = state.games.findIndex((item) => item.id === game.id);
  if (index === -1) {
    state.games.push(game);
  } else {
    state.games[index] = game;
  }
  state.games.sort((left, right) => new Date(right.updatedAt) - new Date(left.updatedAt));
}

function currentView() {
  if (!state.selectedGameId || !state.game) {
    return state.games.length > 0 ? 'lobby' : 'create';
  }
  if (isHostGame(state.game.id)) {
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
  return eggsForPlayer(player.id).find((egg) => !egg.foundAt) || null;
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
  timerEl.textContent = unlocked ? 'Indice pret' : `Indice ${remainingHintLabel()}`;
  hintEl.innerHTML = unlocked
    ? `<strong>Indice :</strong> ${escapeHtml(hideSpotById(egg.hideSpotId)?.hint || '')}`
    : "Encore un petit peu...";
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
  const activeLabel = state.selectedGameId && state.game
    ? `${state.game.title} · ${currentViewLabel()}`
    : state.games.length > 0
      ? `${state.games.length} partie(s)`
      : 'Pret a jouer';
  const deviceLocked = Boolean(
    state.game &&
      (isHostGame(state.game.id) || getClaimedPlayerId(state.game.id)),
  );

  return `
    <section class="hero">
      <div class="hero__top">
        <span class="pill">Paques</span>
        <span class="pill">${escapeHtml(activeLabel)}</span>
        <span class="pill">${escapeHtml(socketLabel())}</span>
      </div>
      <div class="hero__layout">
        <div class="hero__content">
          <div>
            <h1>La chasse aux oeufs</h1>
            <p>Choisis une partie, ou cree la tienne.</p>
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
              ${deviceLocked ? 'Nom fige pour cette partie.' : 'Choisis un petit nom simple.'}
            </div>
          </div>
        </div>
        <div class="hero__scene" aria-hidden="true">
          <div class="cloud cloud--a"></div>
          <div class="cloud cloud--b"></div>
          <div class="egg egg--a"></div>
          <div class="egg egg--b"></div>
          <div class="egg egg--c"></div>
          <div class="bunny">
            <span class="bunny__ear bunny__ear--left"></span>
            <span class="bunny__ear bunny__ear--right"></span>
          </div>
          <div class="grass"></div>
          <div class="flowers">
            <span></span><span></span><span></span><span></span>
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
    case 'lobby':
      return renderLobbyView();
    default:
      return renderCreateOnlyView();
  }
}

function renderLobbyView() {
  return `
    <section class="grid grid--two">
      <article class="card">
        <div class="card__header">
          <div>
            <h2 class="card__title">Parties ouvertes</h2>
            <p class="card__subtitle">Rejoins-en une, ou cree une nouvelle.</p>
          </div>
          <button class="button button--secondary" data-action="refresh" ${disabledAttr()}>
            Actualiser
          </button>
        </div>
        <div class="tile-list">
          ${state.games.map(renderGameLobbyTile).join('')}
        </div>
      </article>
      ${renderCreatePanel()}
    </section>
  `;
}

function renderCreateOnlyView() {
  return renderCreatePanel();
}

function renderCreatePanel() {
  if (!state.create) {
    return '';
  }

  return `
    <article class="card card--soft">
      <div class="card__header">
        <div>
          <h2 class="card__title">${state.games.length > 0 ? 'Nouvelle partie' : '1. Nouvelle partie'}</h2>
          <p class="card__subtitle">${state.games.length > 0 ? 'Tu peux en ouvrir une autre.' : 'Commence ici.'}</p>
        </div>
        ${state.games.length > 0 ? '<button class="button button--ghost" data-action="refresh">Voir les parties</button>' : ''}
      </div>
      <div class="grid">
        <div class="field">
          <label for="game-title">Nom de la partie</label>
          <input id="game-title" value="${escapeHtml(state.create.title)}" />
        </div>
        <div class="field">
          <label for="host-name">Qui cache ?</label>
          <input id="host-name" value="${escapeHtml(state.create.hostName)}" />
        </div>
        <div class="field">
          <label for="game-code">Code secret</label>
          <input
            id="game-code"
            type="password"
            inputmode="numeric"
            maxlength="4"
            placeholder="0000"
            value="${escapeHtml(state.create.adminCode)}"
          />
        </div>
      </div>
      <div class="card__header" style="margin-top: 22px;">
        <div>
          <h3 class="card__title">Joueurs</h3>
          <p class="card__subtitle">Un nom par chasseur.</p>
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
          ? state.create.players.map((player) => `
              <span class="chip">
                ${escapeHtml(player)}
                <button data-action="remove-player" data-player-name="${escapeHtml(player)}">
                  retirer
                </button>
              </span>
            `).join('')
          : '<div class="empty">Ajoute les enfants.</div>'}
      </div>
      <div class="card__header" style="margin-top: 22px;">
        <div>
          <h3 class="card__title">Oeufs</h3>
          <p class="card__subtitle">Choisis les cachettes.</p>
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
          : '<div class="empty">Ajoute un joueur, puis un oeuf.</div>'
      }
      <div class="row" style="margin-top: 18px;">
        <button
          class="button button--primary"
          data-action="create-game"
          ${state.create.players.length && state.create.eggs.length && allEggDraftsReady() ? '' : 'disabled'}
        >
          Ouvrir la partie
        </button>
      </div>
    </article>
  `;
}

function renderGameLobbyTile(game) {
  const claimedPlayerId = getClaimedPlayerId(game.id);
  const claimedPlayer = claimedPlayerId
    ? game.players.find((player) => player.id === claimedPlayerId)
    : null;
  const label = isHostGame(game.id)
    ? 'Ouvrir'
    : claimedPlayer
      ? 'Continuer'
      : 'Rejoindre';

  return `
    <article class="tile tile--pending">
      <div>
        <h3 class="tile__title">${escapeHtml(game.title)}</h3>
        <div class="tile__meta">
          ${escapeHtml(game.hostName)} · ${game.players.length} joueur(s) · ${game.eggs.length} oeuf(s)
          ${claimedPlayer ? `<br />Tu joues : ${escapeHtml(claimedPlayer.name)}` : ''}
        </div>
      </div>
      <div class="tile__aside">
        <div class="tile__actions">
          <button
            class="button button--primary"
            data-action="select-game"
            data-game-id="${game.id}"
            ${disabledAttr()}
          >
            ${label}
          </button>
          <button
            class="button button--danger"
            data-action="delete-game"
            data-game-id="${game.id}"
            ${disabledAttr()}
          >
            Supprimer
          </button>
        </div>
      </div>
    </article>
  `;
}

function renderEggDraft(draft) {
  const areas = [...state.groupedHideSpots.keys()];
  const spots = hideSpotsForArea(draft.area);
  const currentSpot = previewHideSpotForDraft(draft);
  return `
    <article class="draft">
      <div class="draft__head">
        <div>
          <strong>Oeuf ${draft.id}</strong>
          <div class="muted">Un joueur, une cachette.</div>
        </div>
        <button class="button button--ghost" data-action="remove-egg" data-egg-id="${draft.id}">
          Retirer
        </button>
      </div>
      <div class="grid">
        <div class="field">
          <label>Style</label>
          <select data-egg-id="${draft.id}" data-field="mode">
            <option value="catalog" ${draft.mode === 'catalog' ? 'selected' : ''}>Catalogue</option>
            <option value="custom" ${draft.mode === 'custom' ? 'selected' : ''}>Perso</option>
          </select>
        </div>
        <div class="field">
          <label>Joueur</label>
          <select data-egg-id="${draft.id}" data-field="player">
            ${state.create.players.map((player) => `
              <option value="${escapeHtml(player)}" ${player === draft.playerName ? 'selected' : ''}>
                ${escapeHtml(player)}
              </option>
            `).join('')}
          </select>
        </div>
      </div>
      ${
        draft.mode === 'custom'
          ? `
              <div class="grid">
                <div class="field">
                  <label>Piece</label>
                  <input
                    data-egg-id="${draft.id}"
                    data-field="customArea"
                    value="${escapeHtml(draft.customArea)}"
                    placeholder="Ex. Veranda"
                  />
                </div>
                <div class="field">
                  <label>Objet</label>
                  <input
                    data-egg-id="${draft.id}"
                    data-field="customObjectLabel"
                    value="${escapeHtml(draft.customObjectLabel)}"
                    placeholder="Ex. sous le gros coussin"
                  />
                </div>
                <div class="field">
                  <label>Enigme</label>
                  <textarea
                    data-egg-id="${draft.id}"
                    data-field="customRiddle"
                    rows="4"
                    placeholder="Ecris une enigme difficile"
                  >${escapeHtml(draft.customRiddle)}</textarea>
                </div>
                <div class="field">
                  <label>Indice</label>
                  <textarea
                    data-egg-id="${draft.id}"
                    data-field="customHint"
                    rows="3"
                    placeholder="Un petit coup de pouce"
                  >${escapeHtml(draft.customHint)}</textarea>
                </div>
              </div>
            `
          : `
              <div class="grid">
                <div class="field">
                  <label>Piece</label>
                  <select data-egg-id="${draft.id}" data-field="area">
                    ${areas.map((area) => `
                      <option value="${escapeHtml(area)}" ${area === draft.area ? 'selected' : ''}>
                        ${escapeHtml(area)}
                      </option>
                    `).join('')}
                  </select>
                </div>
                <div class="field">
                  <label>Cachette</label>
                  <select data-egg-id="${draft.id}" data-field="hideSpotId">
                    ${spots.map((spot) => `
                      <option value="${spot.id}" ${spot.id === draft.hideSpotId ? 'selected' : ''}>
                        ${escapeHtml(spot.objectLabel)}
                      </option>
                    `).join('')}
                  </select>
                </div>
              </div>
            `
      }
      <div class="peek"><strong>Enigme</strong><span>${escapeHtml(currentSpot?.riddle || '')}</span></div>
      <div class="peek peek--hint"><strong>Indice</strong><span>${escapeHtml(currentSpot?.hint || '')}</span></div>
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
          <p class="card__subtitle">Partie ouverte par ${escapeHtml(game.hostName)}.</p>
        </div>
        <div class="row">
          <button class="button button--ghost" data-action="go-lobby" ${disabledAttr()}>
            Parties
          </button>
          <button class="button button--secondary" data-action="refresh" ${disabledAttr()}>
            Actualiser
          </button>
          <button class="button button--danger" data-action="close-game" ${disabledAttr()}>
            Fermer
          </button>
        </div>
      </div>
      <div class="summary">
        <div class="summary__item">${game.players.length} joueur(s)</div>
        <div class="summary__item">${game.eggs.length} oeuf(s)</div>
        <div class="summary__item">${escapeHtml(socketLabel())}</div>
      </div>
    </article>
    <section class="grid grid--two">
      <article class="card">
        <div class="card__header">
          <div>
            <h2 class="card__title">Qui cherche ?</h2>
            <p class="card__subtitle">Tout bouge en direct.</p>
          </div>
        </div>
        <div class="tile-list">
          ${game.players.map(renderHostPlayerTile).join('')}
        </div>
      </article>
      <article class="card card--soft">
        <div class="card__header">
          <div>
            <h2 class="card__title">Ou sont les oeufs ?</h2>
            <p class="card__subtitle">Petit pense-bete.</p>
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
          ${player.claimedBy ? `Pris par ${escapeHtml(player.claimedBy)}.` : 'Libre'}
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
        <div class="tile__meta">Pour ${escapeHtml(player?.name || 'Inconnu')}</div>
      </div>
      <div class="tile__aside">${egg.foundAt ? 'Trouvé' : 'Cache'}</div>
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
          <p class="card__subtitle">Choisis ton nom.</p>
        </div>
        <div class="row">
          <button class="button button--ghost" data-action="go-lobby" ${disabledAttr()}>
            Parties
          </button>
          <button class="button button--secondary" data-action="refresh" ${disabledAttr()}>
            Actualiser
          </button>
        </div>
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
          ${eggs.length} oeuf(s) · ${foundCount} trouvé(s)
          ${player.claimedBy ? `<br />Pris par ${escapeHtml(player.claimedBy)}` : ''}
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
          <p class="card__subtitle">${foundCount} / ${eggs.length} trouvé(s)</p>
        </div>
        <div class="row">
          <button class="button button--ghost" data-action="go-lobby" ${disabledAttr()}>
            Parties
          </button>
          <button class="button button--secondary" data-action="refresh" ${disabledAttr()}>
            Synchroniser
          </button>
          <button class="button button--ghost" data-action="leave-player" ${disabledAttr()}>
            Changer
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
                  <h2 class="card__title">Enigme</h2>
                  <p class="card__subtitle" data-role="hint-timer">${remainingHintLine()}</p>
                </div>
              </div>
              <div class="riddle">${escapeHtml(spot.riddle)}</div>
              <div class="${isHintUnlocked() ? 'hint' : 'hint hint--locked'}" data-role="hint-box" style="margin-top: 16px;">
                ${
                  isHintUnlocked()
                    ? `<strong>Indice :</strong> ${escapeHtml(spot.hint)}`
                    : 'Encore un petit peu...'
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
                  <h2 class="card__title">Tous trouvés !</h2>
                  <p class="card__subtitle">Bravo !</p>
                </div>
              </div>
            </article>
          `
    }
    <article class="card">
      <div class="card__header">
        <div>
          <h2 class="card__title">Petit journal</h2>
          <p class="card__subtitle">Les trouvés apparaissent ici.</p>
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
        <div class="tile__meta">${done ? 'Cachette révélée.' : 'Le secret reste entier.'}</div>
      </div>
      <div class="tile__aside">${done ? 'Trouvé' : 'En attente'}</div>
    </article>
  `;
}

function currentViewLabel() {
  switch (currentView()) {
    case 'host':
      return 'Grand lapin';
    case 'picker':
      return 'Choix';
    case 'hunt':
      return 'Enigme';
    case 'lobby':
      return 'Parties';
    default:
      return 'Prepa';
  }
}

function socketLabel() {
  switch (state.socketStatus) {
    case 'open':
      return 'Direct';
    case 'connecting':
      return 'Connexion';
    case 'closed':
      return 'Retour...';
    default:
      return state.selectedGameId ? 'Calme' : 'Hall';
  }
}

function remainingHintLine() {
  return isHintUnlocked() ? 'Indice pret' : `Indice ${remainingHintLabel()}`;
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

function hideSpotById(hideSpotId, game = state.game) {
  const customSpot = game?.customHideSpots?.find((spot) => spot.id === hideSpotId);
  if (customSpot) {
    return customSpot;
  }
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

function loadHostGameIds() {
  try {
    const raw = localStorage.getItem(STORAGE_KEYS.hostGameIds);
    if (!raw) {
      return [];
    }
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((value) => typeof value === 'string') : [];
  } catch {
    return [];
  }
}

function saveHostGameIds() {
  localStorage.setItem(STORAGE_KEYS.hostGameIds, JSON.stringify(state.hostGameIds));
}

function isHostGame(gameId) {
  return state.hostGameIds.includes(gameId);
}

function addHostGameId(gameId) {
  if (!state.hostGameIds.includes(gameId)) {
    state.hostGameIds.push(gameId);
    saveHostGameIds();
  }
}

function removeHostGameId(gameId) {
  state.hostGameIds = state.hostGameIds.filter((id) => id !== gameId);
  saveHostGameIds();
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

function savePlayerClaims() {
  localStorage.setItem(STORAGE_KEYS.playerClaims, JSON.stringify(state.playerClaims));
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
  savePlayerClaims();
}

function setSelectedGameId(gameId) {
  state.selectedGameId = gameId;
}

function clearSelectedGame() {
  state.selectedGameId = '';
}

function clearSessionForGame(gameId) {
  if (!gameId) {
    return;
  }
  setClaimedPlayerId(gameId, null);
  if (state.selectedGameId === gameId) {
    clearSelectedGame();
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
