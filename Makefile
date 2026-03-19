# =============================================================
# Makefile — TP Grafana / Oracle 23ai
# =============================================================

.PHONY: up down restart logs status clean oracle-shell bridge-shell

## Démarrer tous les services
up:
	docker compose up -d --build
	@echo ""
	@echo "  Oracle 23ai  : jdbc:oracle:thin:@localhost:1521/FREEPDB1"
	@echo "  Bridge API   : http://localhost:8080/health"
	@echo "  Grafana      : http://localhost:3000  (admin / Grafana2025!)"
	@echo ""
	@echo "  Oracle démarre en ~3 min. Suivre : make logs-oracle"

## Arrêter tous les services
down:
	docker compose down

## Redémarrer
restart:
	docker compose restart

## Voir tous les logs en direct
logs:
	docker compose logs -f

## Logs Oracle uniquement
logs-oracle:
	docker compose logs -f oracle

## Logs Bridge uniquement
logs-bridge:
	docker compose logs -f bridge

## Logs Grafana uniquement
logs-grafana:
	docker compose logs -f grafana

## État des conteneurs
status:
	docker compose ps

## Ouvrir un shell SQL*Plus dans Oracle
oracle-shell:
	docker exec -it tp_oracle sqlplus banc_test/BancTest2025!@//localhost:1521/FREEPDB1

## Ouvrir un shell dans le bridge
bridge-shell:
	docker exec -it tp_bridge bash

## Tester le bridge
test-bridge:
	@echo "==> Health"
	curl -s http://localhost:8080/health | python3 -m json.tool
	@echo ""
	@echo "==> Panels disponibles"
	curl -s http://localhost:8080/panels | python3 -m json.tool
	@echo ""
	@echo "==> Volumes"
	curl -s http://localhost:8080/panels/volumes | python3 -m json.tool

## Supprimer les volumes (ATTENTION : efface les données Oracle)
clean:
	docker compose down -v
	@echo "Volumes supprimés."

## Rebuild du bridge seul (après modif app.py)
rebuild-bridge:
	docker compose build bridge
	docker compose up -d bridge
