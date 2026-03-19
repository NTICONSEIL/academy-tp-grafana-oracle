## Description

<!-- Décrivez les changements apportés -->

## Type de changement

- [ ] Correction de bug
- [ ] Nouvelle fonctionnalité
- [ ] Refactoring (pas de changement fonctionnel)
- [ ] Documentation
- [ ] Mise à jour de dépendances

## Checklist

- [ ] Le code a été testé localement (`make up && make test-bridge`)
- [ ] Le dashboard JSON est valide (`python3 -c "import json; json.load(open('grafana/dashboards/banc_test.json'))"`)
- [ ] Le fichier `.env` n'est PAS inclus dans le commit
- [ ] Le `README.md` est mis à jour si nécessaire
- [ ] Les nouvelles routes du bridge sont documentées dans le README
