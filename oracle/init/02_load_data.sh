#!/bin/bash
# =============================================================
# 02_load_data.sh  — Génération et chargement des données fictives
# Exécuté dans le conteneur Oracle après 01_schema.sql
# =============================================================

echo "[DATA] Génération des données fictives..."

# Python est disponible dans l'image gvenzl/oracle-free
python3 - <<'PYEOF'
import random, os

random.seed(42)

moyens = [
    ('MT_ELEC',  '{"type":"banc_electrique","firmware":"v2.3.1"}'),
    ('MT_RF',    '{"type":"analyseur_rf","freq_min_ghz":0.1,"freq_max_ghz":6.0}'),
    ('MT_THERM', '{"type":"chambre_thermique","t_min_c":-40,"t_max_c":125}'),
    ('MT_VIBR',  '{"type":"table_vibrante","freq_max_hz":2000}'),
    ('MT_EMC',   '{"type":"cage_faraday","attenuation_db":80}'),
    ('MT_OPTIQ', '{"type":"vision_machine","resolution_mp":12}'),
]
produits = [
    ('FAM_A','FAMILLE',None),('CARTE_CPU','CARTE','FAM_A'),
    ('PROC_UNIT','COMPOSANT','CARTE_CPU'),('MEM_MODULE','COMPOSANT','CARTE_CPU'),
    ('PWR_REG','COMPOSANT','CARTE_CPU'),('FAM_B','FAMILLE',None),
    ('CARTE_IO','CARTE','FAM_B'),('USB_CTRL','COMPOSANT','CARTE_IO'),
    ('ETH_CTRL','COMPOSANT','CARTE_IO'),('PCIE_BRIDGE','COMPOSANT','CARTE_IO'),
    ('FAM_C','FAMILLE',None),('CARTE_RF','CARTE','FAM_C'),
    ('RF_AMPLI','COMPOSANT','CARTE_RF'),('RF_FILTER','COMPOSANT','CARTE_RF'),
    ('ANTENNA_MOD','COMPOSANT','CARTE_RF'),
]
definitions = [
    ('DEF_001','CARTE_CPU',3.20,3.40,'Tension alimentation 3V3 (V)'),
    ('DEF_002','CARTE_CPU',40.0,60.0,'Courant repos (mA)'),
    ('DEF_003','PROC_UNIT',1.10,1.30,'Tension coeur CPU (V)'),
    ('DEF_004','PROC_UNIT',0.0,85.0,'Temperature jonction (degC)'),
    ('DEF_005','MEM_MODULE',1.45,1.55,'Tension DDR (V)'),
    ('DEF_006','MEM_MODULE',100.0,200.0,'Debit lecture (MB/s)'),
    ('DEF_007','PWR_REG',3.25,3.35,'Tension sortie regulateur (V)'),
    ('DEF_008','PWR_REG',0.5,2.0,'Ondulation (mV)'),
    ('DEF_009','CARTE_IO',4.75,5.25,'Tension USB 5V (V)'),
    ('DEF_010','USB_CTRL',400.0,500.0,'Debit USB3 (MB/s)'),
    ('DEF_011','ETH_CTRL',940.0,1000.0,'Debit ethernet (Mbps)'),
    ('DEF_012','PCIE_BRIDGE',2.45,2.55,'Tension PCIe (V)'),
    ('DEF_013','CARTE_RF',-5.0,2.0,'Niveau bruit (dBm)'),
    ('DEF_014','RF_AMPLI',18.0,22.0,'Gain ampli (dB)'),
    ('DEF_015','RF_FILTER',-3.0,-1.0,'Insertion loss (dB)'),
    ('DEF_016','ANTENNA_MOD',-2.0,0.5,'Return loss (dB)'),
]
prod_defs = {}
for (did,pid,mn,mx,lbl) in definitions:
    prod_defs.setdefault(pid,[]).append((did,mn,mx))

testable = [p[0] for p in produits if p[1] in ('COMPOSANT','CARTE')]
prod_means = {
    'CARTE_CPU':['MT_ELEC','MT_THERM'],'PROC_UNIT':['MT_ELEC','MT_THERM'],
    'MEM_MODULE':['MT_ELEC'],'PWR_REG':['MT_ELEC'],
    'CARTE_IO':['MT_ELEC','MT_EMC'],'USB_CTRL':['MT_ELEC','MT_OPTIQ'],
    'ETH_CTRL':['MT_ELEC','MT_EMC'],'PCIE_BRIDGE':['MT_ELEC'],
    'CARTE_RF':['MT_RF','MT_EMC'],'RF_AMPLI':['MT_RF'],
    'RF_FILTER':['MT_RF','MT_VIBR'],'ANTENNA_MOD':['MT_RF','MT_OPTIQ'],
}
base_failure = {
    'CARTE_CPU':0.06,'PROC_UNIT':0.05,'MEM_MODULE':0.04,'PWR_REG':0.08,
    'CARTE_IO':0.05,'USB_CTRL':0.07,'ETH_CTRL':0.06,'PCIE_BRIDGE':0.05,
    'CARTE_RF':0.10,'RF_AMPLI':0.12,'RF_FILTER':0.09,'ANTENNA_MOD':0.11,
}
from datetime import datetime, timedelta

def gen_value(mn, mx, fp, drift=1.0):
    spread = (mx - mn) / 2
    if random.random() < fp:
        if random.random() < 0.5:
            v = mn - random.uniform(spread*0.05, spread*0.6)
        else:
            v = mx + random.uniform(spread*0.05, spread*0.6)*drift
        return round(v, 4), 'failed'
    center = (mn + mx) / 2
    v = center + random.gauss(0, spread*0.25) + spread*0.15*(drift-1.0)
    v = max(mn*0.999, min(mx*1.001, v))
    return round(v, 4), 'passed'

base  = datetime(2024, 9, 1)
total = (datetime(2025, 3, 1) - base).total_seconds()

lines = []
meas_count = 0

for i in range(1, 5001):
    seq_id = f'SEQ_{i:06d}'
    off    = random.uniform(0, total)
    d_el   = off / 86400.0
    drift  = 1.0 + (d_el/180.0)*0.30
    elec_x = max(0.0, (d_el-90)/90.0*0.15) if d_el > 90 else 0.0
    st     = base + timedelta(seconds=off)
    cur    = st
    seq_failed = False
    mrows  = []

    for prod_id in random.choices(testable, k=random.randint(4,8)):
        meas_count += 1
        mid   = f'MEAS_{meas_count:08d}'
        tm_id = random.choice(prod_means.get(prod_id, ['MT_ELEC']))
        dur   = random.uniform(30, 300)
        ms    = cur
        me    = cur + timedelta(seconds=dur)
        cur   = me + timedelta(seconds=random.uniform(2,15))
        defs  = prod_defs.get(prod_id, [])
        _, mn, mx = random.choice(defs) if defs else ('X', 0.0, 100.0)
        fp    = base_failure.get(prod_id, 0.07)
        if tm_id == 'MT_ELEC': fp += elec_x
        d     = drift if prod_id in ('RF_AMPLI','ANTENNA_MOD') else 1.0+(drift-1.0)*0.4
        val, res = gen_value(mn, mx, fp, d)
        if res == 'failed': seq_failed = True
        mrows.append(
            f"INSERT INTO MESURE VALUES('{mid}','{seq_id}','{prod_id}','{tm_id}','{res}',{val},"
            f"TIMESTAMP '{ms.strftime('%Y-%m-%d %H:%M:%S')}',TIMESTAMP '{me.strftime('%Y-%m-%d %H:%M:%S')}');"
        )
    res = 'failed' if seq_failed else 'passed'
    lines.append(
        f"INSERT INTO SEQUENCE_TEST VALUES('{seq_id}','{res}',"
        f"TIMESTAMP '{st.strftime('%Y-%m-%d %H:%M:%S')}',TIMESTAMP '{cur.strftime('%Y-%m-%d %H:%M:%S')}');"
    )
    lines.extend(mrows)

with open('/tmp/data.sql','w') as f:
    f.write('\n'.join(lines))

print(f"Généré: 5000 séquences, {meas_count} mesures")
PYEOF

echo "[DATA] Chargement des référentiels..."
sqlplus -s "${APP_USER}/${APP_USER_PASSWORD}@//localhost:1521/FREEPDB1" <<SQL
SET ECHO OFF
SET FEEDBACK OFF
SET DEFINE OFF

-- MOYEN_DE_TEST
INSERT INTO MOYEN_DE_TEST VALUES('MT_ELEC',  '{"type":"banc_electrique","firmware":"v2.3.1"}');
INSERT INTO MOYEN_DE_TEST VALUES('MT_RF',    '{"type":"analyseur_rf","freq_min_ghz":0.1,"freq_max_ghz":6.0}');
INSERT INTO MOYEN_DE_TEST VALUES('MT_THERM', '{"type":"chambre_thermique","t_min_c":-40,"t_max_c":125}');
INSERT INTO MOYEN_DE_TEST VALUES('MT_VIBR',  '{"type":"table_vibrante","freq_max_hz":2000}');
INSERT INTO MOYEN_DE_TEST VALUES('MT_EMC',   '{"type":"cage_faraday","attenuation_db":80}');
INSERT INTO MOYEN_DE_TEST VALUES('MT_OPTIQ', '{"type":"vision_machine","resolution_mp":12}');

-- PRODUIT
INSERT INTO PRODUIT VALUES('FAM_A','FAMILLE',NULL);
INSERT INTO PRODUIT VALUES('FAM_B','FAMILLE',NULL);
INSERT INTO PRODUIT VALUES('FAM_C','FAMILLE',NULL);
INSERT INTO PRODUIT VALUES('CARTE_CPU','CARTE','FAM_A');
INSERT INTO PRODUIT VALUES('CARTE_IO','CARTE','FAM_B');
INSERT INTO PRODUIT VALUES('CARTE_RF','CARTE','FAM_C');
INSERT INTO PRODUIT VALUES('PROC_UNIT','COMPOSANT','CARTE_CPU');
INSERT INTO PRODUIT VALUES('MEM_MODULE','COMPOSANT','CARTE_CPU');
INSERT INTO PRODUIT VALUES('PWR_REG','COMPOSANT','CARTE_CPU');
INSERT INTO PRODUIT VALUES('USB_CTRL','COMPOSANT','CARTE_IO');
INSERT INTO PRODUIT VALUES('ETH_CTRL','COMPOSANT','CARTE_IO');
INSERT INTO PRODUIT VALUES('PCIE_BRIDGE','COMPOSANT','CARTE_IO');
INSERT INTO PRODUIT VALUES('RF_AMPLI','COMPOSANT','CARTE_RF');
INSERT INTO PRODUIT VALUES('RF_FILTER','COMPOSANT','CARTE_RF');
INSERT INTO PRODUIT VALUES('ANTENNA_MOD','COMPOSANT','CARTE_RF');

-- DEFINITION
INSERT INTO DEFINITION VALUES('DEF_001','CARTE_CPU',3.20,3.40,'Tension alimentation 3V3 (V)');
INSERT INTO DEFINITION VALUES('DEF_002','CARTE_CPU',40.0,60.0,'Courant repos (mA)');
INSERT INTO DEFINITION VALUES('DEF_003','PROC_UNIT',1.10,1.30,'Tension coeur CPU (V)');
INSERT INTO DEFINITION VALUES('DEF_004','PROC_UNIT',0.0,85.0,'Temperature jonction (degC)');
INSERT INTO DEFINITION VALUES('DEF_005','MEM_MODULE',1.45,1.55,'Tension DDR (V)');
INSERT INTO DEFINITION VALUES('DEF_006','MEM_MODULE',100.0,200.0,'Debit lecture (MB/s)');
INSERT INTO DEFINITION VALUES('DEF_007','PWR_REG',3.25,3.35,'Tension sortie regulateur (V)');
INSERT INTO DEFINITION VALUES('DEF_008','PWR_REG',0.5,2.0,'Ondulation (mV)');
INSERT INTO DEFINITION VALUES('DEF_009','CARTE_IO',4.75,5.25,'Tension USB 5V (V)');
INSERT INTO DEFINITION VALUES('DEF_010','USB_CTRL',400.0,500.0,'Debit USB3 (MB/s)');
INSERT INTO DEFINITION VALUES('DEF_011','ETH_CTRL',940.0,1000.0,'Debit ethernet (Mbps)');
INSERT INTO DEFINITION VALUES('DEF_012','PCIE_BRIDGE',2.45,2.55,'Tension PCIe (V)');
INSERT INTO DEFINITION VALUES('DEF_013','CARTE_RF',-5.0,2.0,'Niveau bruit (dBm)');
INSERT INTO DEFINITION VALUES('DEF_014','RF_AMPLI',18.0,22.0,'Gain ampli (dB)');
INSERT INTO DEFINITION VALUES('DEF_015','RF_FILTER',-3.0,-1.0,'Insertion loss (dB)');
INSERT INTO DEFINITION VALUES('DEF_016','ANTENNA_MOD',-2.0,0.5,'Return loss (dB)');

COMMIT;
EXIT;
SQL

echo "[DATA] Chargement des séquences et mesures (5000 / ~30 000)..."
sqlplus -s "${APP_USER}/${APP_USER_PASSWORD}@//localhost:1521/FREEPDB1" @/tmp/data.sql

sqlplus -s "${APP_USER}/${APP_USER_PASSWORD}@//localhost:1521/FREEPDB1" <<SQL
SET FEEDBACK OFF
COMMIT;
EXIT;
SQL

echo "[DATA] Chargement terminé."

sqlplus -s "${APP_USER}/${APP_USER_PASSWORD}@//localhost:1521/FREEPDB1" <<SQL
SET PAGESIZE 20
SET LINESIZE 60
SELECT 'SEQUENCE_TEST' AS tbl, COUNT(*) AS nb FROM SEQUENCE_TEST
UNION ALL
SELECT 'MESURE',        COUNT(*) FROM MESURE
UNION ALL
SELECT 'PRODUIT',       COUNT(*) FROM PRODUIT
UNION ALL
SELECT 'MOYEN_DE_TEST', COUNT(*) FROM MOYEN_DE_TEST
UNION ALL
SELECT 'DEFINITION',    COUNT(*) FROM DEFINITION;
EXIT;
SQL
