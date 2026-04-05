# Chasse aux oeufs

Prototype de chasse aux oeufs avec une architecture monolithique simple a deployer : un seul conteneur Dart sert l'interface web, l'API et la synchronisation temps reel.

## Serveur local avec Docker Compose

Le dossier `server/` contient maintenant l'application complete prevue pour le reseau local :

- catalogue de cachettes et enigmes
- creation d'une partie active
- selection d'un joueur existant
- liberation d'un joueur en cas de mauvaise selection
- validation d'un oeuf trouvé
- synchronisation en temps reel via WebSocket
- persistance JSON sur volume Docker
- interface web servie directement a la racine `/`

### Lancer sur le Raspberry

1. Copier `.env.example` vers `.env` si tu veux changer le port ou l'origine autorisee.
2. Lancer :

```bash
docker compose up --build -d
```

3. Depuis les telephones ou ordinateurs du meme reseau, ouvrir l'URL du serveur :

```text
http://raspberrypi.local:8181
```

Ou, si `raspberrypi.local` n'est pas resolu :

```text
http://IP_DU_RASPBERRY:8181
```

### Arreter

```bash
docker compose down
```

La donnee de partie est conservee dans le volume `egg_hunt_data`.

Cette URL ouvre directement l'application web de chasse aux oeufs. Aucun client separe n'est necessaire.

## Variables Docker Compose

- `HOST_PORT` : port expose sur le Raspberry, par defaut `8181`
- `ALLOWED_ORIGIN` : origine CORS autorisee, par defaut `*`

## API principale

- `GET /health`
- `GET /api/catalog/hide-spots`
- `GET /api/games`
- `GET /api/games/active`
- `GET /api/games/{id}`
- `POST /api/games`
- `POST /api/games/{id}/join`
- `POST /api/games/{id}/leave`
- `POST /api/games/{id}/eggs/{eggId}/found`
- `POST /api/games/{id}/close`
- `GET /ws/games/{id}`

## Exemple de creation de partie

```bash
curl -X POST http://raspberrypi.local:8181/api/games \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Chasse du dimanche",
    "hostName": "Salon",
    "players": ["Zoe", "Louis"],
    "eggs": [
      {"playerName": "Zoe", "hideSpotId": "salon-canape"},
      {"playerName": "Louis", "hideSpotId": "jardin-pot"}
    ]
  }'
```

## Etat actuel du repo

Le chemin de deploiement le plus simple est desormais le monolithe Docker du dossier `server/`. Le prototype Flutter natif reste present dans le repo comme base exploratoire, mais la version la plus facile a utiliser sur Raspberry et navigateurs locaux est l'interface web servie par le backend Dart.
