-- =============================================================
-- 01_schema.sql  — DDL complet (exécuté par l'utilisateur APP_USER)
-- Oracle 23ai Free / gvenzl image
-- =============================================================

-- Nettoyage (ré-exécution idempotente)
BEGIN
    FOR t IN (
        SELECT table_name FROM user_tables
        WHERE table_name IN (
            'MESURE','SEQUENCE_TEST','DEFINITION',
            'PRODUIT','MOYEN_DE_TEST'
        )
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS';
    END LOOP;
END;
/

-- 1. MOYEN_DE_TEST
CREATE TABLE MOYEN_DE_TEST (
    test_mean_id     VARCHAR2(50)  NOT NULL,
    test_mean_config VARCHAR2(500),
    CONSTRAINT pk_moyen_de_test PRIMARY KEY (test_mean_id)
);

-- 2. PRODUIT (auto-référence)
CREATE TABLE PRODUIT (
    prod_id      VARCHAR2(50) NOT NULL,
    prod_type_id VARCHAR2(50),
    parent_id    VARCHAR2(50),
    CONSTRAINT pk_produit        PRIMARY KEY (prod_id),
    CONSTRAINT fk_produit_parent FOREIGN KEY (parent_id)
        REFERENCES PRODUIT(prod_id)
        DEFERRABLE INITIALLY DEFERRED
);

-- 3. DEFINITION
CREATE TABLE DEFINITION (
    def_id  VARCHAR2(50)   NOT NULL,
    prod_id VARCHAR2(50)   NOT NULL,
    min_val FLOAT,
    max_val FLOAT,
    def     VARCHAR2(500),
    CONSTRAINT pk_definition      PRIMARY KEY (def_id),
    CONSTRAINT fk_definition_prod FOREIGN KEY (prod_id)
        REFERENCES PRODUIT(prod_id)
);

-- 4. SEQUENCE_TEST  (SEQUENCE est réservé Oracle)
CREATE TABLE SEQUENCE_TEST (
    seq_id     VARCHAR2(50) NOT NULL,
    result     VARCHAR2(10),
    started_at TIMESTAMP,
    ended_at   TIMESTAMP,
    CONSTRAINT pk_sequence_test PRIMARY KEY (seq_id),
    CONSTRAINT chk_seq_result   CHECK (result IN ('passed','failed'))
);

-- 5. MESURE (entité centrale)
CREATE TABLE MESURE (
    meas_id      VARCHAR2(50) NOT NULL,
    seq_id       VARCHAR2(50) NOT NULL,
    prod_id      VARCHAR2(50) NOT NULL,
    test_mean_id VARCHAR2(50) NOT NULL,
    result       VARCHAR2(10),
    value        FLOAT,
    started_at   TIMESTAMP,
    ended_at     TIMESTAMP,
    CONSTRAINT pk_mesure         PRIMARY KEY (meas_id),
    CONSTRAINT chk_mes_result    CHECK (result IN ('passed','failed')),
    CONSTRAINT fk_mes_seq        FOREIGN KEY (seq_id)       REFERENCES SEQUENCE_TEST(seq_id),
    CONSTRAINT fk_mes_prod       FOREIGN KEY (prod_id)      REFERENCES PRODUIT(prod_id),
    CONSTRAINT fk_mes_testmean   FOREIGN KEY (test_mean_id) REFERENCES MOYEN_DE_TEST(test_mean_id)
);

-- Index
CREATE INDEX idx_mesure_seq      ON MESURE(seq_id);
CREATE INDEX idx_mesure_prod     ON MESURE(prod_id);
CREATE INDEX idx_mesure_testmean ON MESURE(test_mean_id);
CREATE INDEX idx_mesure_start    ON MESURE(started_at);
CREATE INDEX idx_mesure_result   ON MESURE(result);
CREATE INDEX idx_seq_start       ON SEQUENCE_TEST(started_at);
CREATE INDEX idx_seq_result      ON SEQUENCE_TEST(result);
CREATE INDEX idx_def_prod        ON DEFINITION(prod_id);
CREATE INDEX idx_prod_parent     ON PRODUIT(parent_id);

-- Vue conformité
CREATE OR REPLACE VIEW V_MESURE_CONFORMITE AS
SELECT m.meas_id, m.seq_id, m.prod_id, m.test_mean_id,
       m.result AS result_mesure, m.value,
       d.def_id, d.min_val, d.max_val, d.def AS critere,
       CASE WHEN m.value < d.min_val THEN 'SOUS_MIN'
            WHEN m.value > d.max_val THEN 'SUR_MAX'
            ELSE 'OK' END AS conformite,
       m.started_at, m.ended_at,
       ROUND((CAST(m.ended_at AS DATE) - CAST(m.started_at AS DATE))*86400,1) AS duree_sec
FROM   MESURE m
LEFT JOIN DEFINITION d ON d.prod_id = m.prod_id;

-- Vue qualité quotidienne (source panels Grafana)
CREATE OR REPLACE VIEW V_QUALITE_QUOTIDIENNE AS
SELECT TRUNC(started_at,'DD') AS jour,
       test_mean_id,
       COUNT(*) AS nb_mesures,
       SUM(CASE WHEN result='passed' THEN 1 ELSE 0 END) AS nb_passed,
       SUM(CASE WHEN result='failed' THEN 1 ELSE 0 END) AS nb_failed,
       ROUND(SUM(CASE WHEN result='passed' THEN 1 ELSE 0 END)*100.0/COUNT(*),2) AS taux_passed_pct
FROM   MESURE
GROUP  BY TRUNC(started_at,'DD'), test_mean_id;

COMMIT;

PROMPT Schema OK — tables, index et vues créés.
