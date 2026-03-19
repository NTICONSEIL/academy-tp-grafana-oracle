# TP Grafana — Banc de Test Oracle 23ai
### Christophe CROISANT / ntiConseil

Environnement Docker complet pour le TP de prise en main de Grafana
sur une base de données Oracle 23ai simulant un banc de test électronique.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Docker network : tp_net                                │
│                                                         │
│  ┌─────────────┐    SQL     ┌──────────────┐            │
│  │ Oracle 23ai │◄──────────►│   Bridge     │            │
│  │  :1521      │            │  Flask/Python│            │
│  │  FREEPDB1   │            │  :8080       │            │
│  └─────────────┘            └──────┬───────┘            │
│                                    │ REST/JSON           │
│                             ┌──────▼───────┐            │
│                             │   Grafana    │            │
│                             │  OSS :3000   │            │
│                             │  + Infinity  │            │
│                             └──────────────┘            │
└─────────────────────────────────────────────────────────┘
```

**Pourquoi un bridge ?**
Le plugin Oracle officiel de Grafana est réservé à la version Enterprise (payante).
Le bridge Flask expose les données Oracle en JSON via une API REST légère,
consommée par le plugin gratuit **Infinity datasource**.

---

## Prérequis

- Docker Desktop >= 4.x (ou Docker Engine + Compose v2)
- 4 Go de RAM libres (Oracle 23ai Free en nécessite ~2 Go)
- Ports libres : 1521, 3000, 8080

---

## Démarrage rapide

```bash
# 1. Cloner / décompresser le dossier
cd docker-tp-grafana

# 2. (Optionnel) Modifier les mots de passe dans .env

# 3. Démarrer
make up
# ou sans make :
docker compose up -d --build

# 4. Suivre l'initialisation Oracle (~3 min)
make logs-oracle
# Attendre : "DATABASE IS READY TO USE!"

# 5. Vérifier le bridge
make test-bridge

# 6. Ouvrir Grafana
# http://localhost:3000
# Login : admin / Grafana2025!
```

Le dashboard "TP Grafana - Banc de Test Oracle 23ai" s'ouvre automatiquement.

---

## Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin / Grafana2025! |
| Bridge API | http://localhost:8080 | — (lecture seule) |
| Oracle | localhost:1521/FREEPDB1 | banc_test / BancTest2025! |

---

## Endpoints du Bridge

| Méthode | URL | Description |
|---------|-----|-------------|
| GET | /health | Liveness + test connexion Oracle |
| GET | /tables | Liste des tables et vues |
| POST | /query | Exécute une requête SQL libre (SELECT uniquement) |
| GET | /panels | Liste des requêtes prédéfinies |
| GET | /panels/{id} | Requête prédéfinie (avec ?from=&to= optionnel) |

**Panels prédéfinis :**
- `volumes` — compteurs globaux
- `qualite_quotidienne` — taux réussite jour/jour
- `echec_par_moyen` — taux échec par moyen de test
- `repartition` — passed vs failed
- `synthese_moyens` — tableau complet par moyen
- `derive_rf` — dérive valeurs composants RF
- `durees` — durées individuelles des mesures
- `non_conformites` — mesures hors seuils
- `heatmap_echec` — heatmap jour×heure
- `hierarchie_produit` — arbre produits avec taux

**Exemple :**
```bash
curl "http://localhost:8080/panels/echec_par_moyen?from=2024-12-01&to=2025-01-31"
```

**Requête libre :**
```bash
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT COUNT(*) AS nb FROM MESURE WHERE result = '\''failed'\''", "limit": 10}'
```

---

## Structure du projet

```
docker-tp-grafana/
├── docker-compose.yml
├── .env                          # Variables (mots de passe)
├── Makefile                      # Commandes raccourcies
│
├── oracle/
│   └── init/
│       ├── 01_schema.sql         # DDL : tables, index, vues
│       └── 02_load_data.sh       # Génération + chargement données fictives
│
├── bridge/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app.py                    # API Flask (proxy Oracle → JSON)
│
└── grafana/
    ├── provisioning/
    │   ├── datasources/
    │   │   └── oracle_bridge.yaml
    │   └── dashboards/
    │       └── dashboards.yaml
    └── dashboards/
        └── banc_test.json        # Dashboard pré-configuré (9 panels)
```

---

## Données simulées

| Entité | Volume |
|--------|--------|
| Séquences | 5 000 |
| Mesures | ~30 000 |
| Produits | 15 (3 familles, 3 cartes, 9 composants) |
| Moyens de test | 6 (ELEC, RF, THERM, VIBR, EMC, OPTIQ) |
| Définitions | 16 (seuils min/max par produit) |
| Période | 01/09/2024 — 01/03/2025 |

**Scénarios injectés** (visibles dans les graphiques) :
- **Dégradation MT_ELEC** : taux d'échec +15 % progressif après J+90 (01/12/2024)
- **Dérive RF_AMPLI / ANTENNA_MOD** : valeurs +30 % sur 6 mois

---

## Commandes utiles

```bash
make up              # Démarrer
make down            # Arrêter
make logs            # Logs temps réel
make logs-oracle     # Logs Oracle uniquement
make status          # État des conteneurs
make oracle-shell    # Ouvrir SQL*Plus
make test-bridge     # Tester l'API bridge
make clean           # Tout supprimer (volumes inclus)
```

---

## Personnaliser les requêtes dans Grafana

Pour modifier une requête dans un panel :

1. Cliquer sur le panel > **Edit**
2. Onglet **Query** > champ **URL**
3. Remplacer l'endpoint `/panels/xxx` par un appel `/query` avec votre SQL :

```
URL   : http://bridge:8080/query
Method: POST
Body  : {"sql": "SELECT ...", "limit": 5000}
```

Ou utilisez directement les endpoints `/panels/` comme point de départ et
ajoutez vos propres routes dans `bridge/app.py`, puis `make rebuild-bridge`.

---

## Passer au plugin Oracle Enterprise (optionnel)

Si vous disposez d'une licence Grafana Enterprise ou d'un trial 30 jours :

1. Remplacer dans `docker-compose.yml` :
   ```yaml
   image: grafana/grafana-enterprise:11.4.0
   ```
2. Ajouter dans `environment` :
   ```yaml
   GF_INSTALL_PLUGINS: grafana-oracle-datasource
   ```
3. Modifier la datasource dans `grafana/provisioning/datasources/oracle_bridge.yaml`
   pour pointer directement sur Oracle (host: oracle, port: 1521, etc.)
4. Mettre à jour les targets dans `banc_test.json` pour utiliser du SQL natif
   avec les macros `$__timeFrom()` et `$__timeTo()`

---

*ntiConseil — 2025*
