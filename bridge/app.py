"""
bridge/app.py
=============================================================
Proxy REST entre Oracle 23ai et le plugin Grafana Infinity.

Routes :
  GET  /health               — liveness check
  GET  /tables               — liste des tables/vues disponibles
  POST /query                — exécute une requête SQL (body JSON)
  GET  /panels/<panel_id>    — requêtes prédéfinies pour chaque panel du TP

Sécurité : lecture seule (SELECT uniquement), liste blanche de tables.
=============================================================
"""

import os, re, logging
from datetime import datetime, date
import oracledb
from flask import Flask, jsonify, request, abort

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')

# ── Connexion Oracle ──────────────────────────────────────────────────────────
DB_CFG = dict(
    host     = os.environ.get('ORACLE_HOST',     'oracle'),
    port     = int(os.environ.get('ORACLE_PORT', '1521')),
    service_name = os.environ.get('ORACLE_SERVICE', 'FREEPDB1'),
    user     = os.environ.get('ORACLE_USER',     'banc_test'),
    password = os.environ.get('ORACLE_PASSWORD', 'BancTest2025!'),
)

def get_conn():
    dsn = oracledb.makedsn(DB_CFG['host'], DB_CFG['port'], service_name=DB_CFG['service_name'])
    return oracledb.connect(user=DB_CFG['user'], password=DB_CFG['password'], dsn=dsn)

# ── Sécurité : SELECT uniquement ─────────────────────────────────────────────
ALLOWED_TABLES = {
    'SEQUENCE_TEST','MESURE','PRODUIT','MOYEN_DE_TEST','DEFINITION',
    'V_MESURE_CONFORMITE','V_QUALITE_QUOTIDIENNE',
}

def check_query(sql: str):
    clean = sql.strip().upper()
    if not clean.startswith('SELECT'):
        abort(403, 'Seules les requêtes SELECT sont autorisées.')
    for kw in ('INSERT','UPDATE','DELETE','DROP','TRUNCATE','CREATE','EXECUTE','GRANT'):
        if re.search(r'\b' + kw + r'\b', clean):
            abort(403, f'Mot-clé interdit : {kw}')

def serial(val):
    if isinstance(val, (datetime, date)):
        return val.isoformat()
    return val

def run_query(sql: str, params: dict = None, limit: int = 5000):
    check_query(sql)
    try:
        conn = get_conn()
        cur  = conn.cursor()
        if params:
            cur.execute(sql, params)
        else:
            cur.execute(sql)
        cols = [d[0].lower() for d in cur.description]
        rows = [dict(zip(cols, [serial(v) for v in row])) for row in cur.fetchmany(limit)]
        cur.close(); conn.close()
        return cols, rows
    except oracledb.DatabaseError as e:
        logging.error(f'Oracle error: {e}')
        abort(500, str(e))

# ── Requêtes prédéfinies pour les panels Grafana du TP ───────────────────────
PANEL_QUERIES = {

    # Panel 1 — Volumes globaux
    'volumes': """
        SELECT 'Sequences'  AS metric, COUNT(*) AS value FROM SEQUENCE_TEST
        UNION ALL
        SELECT 'Mesures',    COUNT(*) FROM MESURE
        UNION ALL
        SELECT 'Passed_pct',
               ROUND(SUM(CASE WHEN result='passed' THEN 1 ELSE 0 END)*100.0/COUNT(*),1)
        FROM   SEQUENCE_TEST
        UNION ALL
        SELECT 'Produits',   COUNT(DISTINCT prod_id) FROM MESURE
    """,

    # Panel 2 — Taux réussite quotidien
    'qualite_quotidienne': """
        SELECT TRUNC(started_at,'DD') AS jour,
               ROUND(SUM(CASE WHEN result='passed' THEN 1 ELSE 0 END)*100.0/COUNT(*),1) AS taux_passed_pct
        FROM   SEQUENCE_TEST
        WHERE  started_at >= :date_from
          AND  started_at <= :date_to
        GROUP  BY TRUNC(started_at,'DD')
        ORDER  BY 1
    """,

    # Panel 3 — Taux échec par moyen de test
    'echec_par_moyen': """
        SELECT TRUNC(m.started_at,'DD') AS jour,
               m.test_mean_id,
               ROUND(SUM(CASE WHEN m.result='failed' THEN 1 ELSE 0 END)*100.0/COUNT(*),1) AS taux_failed_pct
        FROM   MESURE m
        WHERE  m.started_at >= :date_from
          AND  m.started_at <= :date_to
        GROUP  BY TRUNC(m.started_at,'DD'), m.test_mean_id
        ORDER  BY 1, 2
    """,

    # Panel 4 — Répartition passed/failed
    'repartition': """
        SELECT result, COUNT(*) AS nb
        FROM   SEQUENCE_TEST
        WHERE  started_at >= :date_from
          AND  started_at <= :date_to
        GROUP  BY result
    """,

    # Panel 5 — Synthèse par moyen
    'synthese_moyens': """
        SELECT mt.test_mean_id AS moyen,
               COUNT(*) AS nb_mesures,
               SUM(CASE WHEN m.result='passed' THEN 1 ELSE 0 END) AS nb_passed,
               SUM(CASE WHEN m.result='failed' THEN 1 ELSE 0 END) AS nb_failed,
               ROUND(SUM(CASE WHEN m.result='passed' THEN 1 ELSE 0 END)*100.0/COUNT(*),1) AS taux_pct,
               ROUND(AVG((CAST(m.ended_at AS DATE)-CAST(m.started_at AS DATE))*86400),0) AS duree_moy_sec
        FROM   MESURE m
        JOIN   MOYEN_DE_TEST mt ON mt.test_mean_id = m.test_mean_id
        GROUP  BY mt.test_mean_id
        ORDER  BY taux_pct DESC
    """,

    # Panel 7 — Dérive valeurs RF
    'derive_rf': """
        SELECT TRUNC(m.started_at,'DD') AS jour,
               m.prod_id,
               ROUND(AVG(m.value),4)   AS valeur_moyenne
        FROM   MESURE m
        WHERE  m.prod_id IN ('RF_AMPLI','RF_FILTER','ANTENNA_MOD')
          AND  m.started_at >= :date_from
          AND  m.started_at <= :date_to
        GROUP  BY TRUNC(m.started_at,'DD'), m.prod_id
        ORDER  BY 1, 2
    """,

    # Panel 8 — Durées de mesure
    'durees': """
        SELECT ROUND((CAST(ended_at AS DATE)-CAST(started_at AS DATE))*86400) AS duree_sec
        FROM   MESURE
        WHERE  started_at >= :date_from
          AND  started_at <= :date_to
    """,

    # Panel 9 — Non-conformités
    'non_conformites': """
        SELECT m.meas_id, m.prod_id, m.test_mean_id,
               ROUND(m.value,4) AS valeur,
               d.min_val, d.max_val, d.def AS critere,
               CASE WHEN m.value < d.min_val THEN 'SOUS_MIN' ELSE 'SUR_MAX' END AS type_ecart,
               TO_CHAR(m.started_at,'DD/MM/YYYY HH24:MI') AS horodatage
        FROM   MESURE m
        JOIN   DEFINITION d ON d.prod_id = m.prod_id
        WHERE (m.value < d.min_val OR m.value > d.max_val)
          AND  m.started_at >= :date_from
          AND  m.started_at <= :date_to
        ORDER  BY m.started_at DESC
        FETCH  FIRST 500 ROWS ONLY
    """,

    # Exercice 1 — Heatmap
    'heatmap_echec': """
        SELECT TO_NUMBER(TO_CHAR(started_at,'D'))    AS jour_semaine,
               TO_NUMBER(TO_CHAR(started_at,'HH24')) AS heure,
               ROUND(SUM(CASE WHEN result='failed' THEN 1 ELSE 0 END)*100.0/COUNT(*),1) AS taux_failed
        FROM   MESURE
        GROUP  BY TO_NUMBER(TO_CHAR(started_at,'D')),
                  TO_NUMBER(TO_CHAR(started_at,'HH24'))
        ORDER  BY 1, 2
    """,

    # Exercice 2 — Hiérarchie produit
    'hierarchie_produit': """
        SELECT LEVEL AS niveau,
               LPAD(' ',(LEVEL-1)*4)||p.prod_id AS produit,
               p.prod_type_id,
               COUNT(m.meas_id) AS nb_mesures,
               ROUND(SUM(CASE WHEN m.result='failed' THEN 1 ELSE 0 END)
                     *100.0/NULLIF(COUNT(m.meas_id),0),1) AS taux_failed_pct
        FROM   PRODUIT p
        LEFT JOIN MESURE m ON m.prod_id = p.prod_id
        START  WITH p.parent_id IS NULL
        CONNECT BY PRIOR p.prod_id = p.parent_id
        GROUP  BY LEVEL, p.prod_id, p.prod_type_id
        ORDER  SIBLINGS BY p.prod_id
    """,
}

# ── Routes ─────────────────────────────────────────────────────────────────────
@app.get('/health')
def health():
    try:
        conn = get_conn(); conn.close()
        return jsonify(status='ok', oracle='connected')
    except Exception as e:
        return jsonify(status='error', detail=str(e)), 503

@app.get('/tables')
def tables():
    _, rows = run_query(
        "SELECT table_name AS name, 'TABLE' AS type FROM user_tables "
        "UNION ALL SELECT view_name, 'VIEW' FROM user_views ORDER BY 1"
    )
    return jsonify(rows)

@app.post('/query')
def query():
    """Corps JSON : { "sql": "SELECT ...", "params": {}, "limit": 1000 }"""
    body  = request.get_json(force=True, silent=True) or {}
    sql   = body.get('sql', '').strip()
    if not sql:
        abort(400, 'Champ "sql" manquant.')
    params = body.get('params', {})
    limit  = min(int(body.get('limit', 5000)), 10000)
    cols, rows = run_query(sql, params or None, limit)
    return jsonify(columns=cols, rows=rows, count=len(rows))

@app.get('/panels/<panel_id>')
def panel(panel_id):
    """Requête prédéfinie avec filtre temporel optionnel."""
    if panel_id not in PANEL_QUERIES:
        abort(404, f'Panel inconnu : {panel_id}. Disponibles : {list(PANEL_QUERIES)}')
    sql = PANEL_QUERIES[panel_id]
    params = {}
    if ':date_from' in sql:
        params['date_from'] = request.args.get('from', '2024-09-01 00:00:00')
        params['date_to']   = request.args.get('to',   '2025-03-01 23:59:59')
    _, rows = run_query(sql, params or None, 10000)
    return jsonify(rows)

@app.get('/panels')
def panel_list():
    return jsonify(list(PANEL_QUERIES.keys()))

# ── CORS minimal pour Grafana ──────────────────────────────────────────────────
@app.after_request
def add_cors(resp):
    resp.headers['Access-Control-Allow-Origin']  = '*'
    resp.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    resp.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    return resp

@app.route('/', methods=['OPTIONS'])
@app.route('/<path:path>', methods=['OPTIONS'])
def options(*args, **kwargs):
    return '', 204

# ── Démarrage ──────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    port = int(os.environ.get('BRIDGE_PORT', 8080))
    logging.info(f'Bridge démarré sur le port {port}')
    from waitress import serve
    serve(app, host='0.0.0.0', port=port)
