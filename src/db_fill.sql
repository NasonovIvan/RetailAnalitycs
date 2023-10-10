-- Замените путь до датасета на свой во всех местах

COPY personal_information FROM '/Users/ivan/SQL3_RetailAnalitycs_v1.0-1/datasets/Personal_Data_Mini.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER false);
COPY cards FROM '/Users/ivan/SQL3_RetailAnalitycs_v1.0-1/datasets/Cards_Mini.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER false);
COPY sku_groups FROM '/Users/ivan/SQL3_RetailAnalitycs_v1.0-1/datasets/Groups_SKU_Mini.tsv' WITH (FORMAT csv, DELIMITER E'\t');
COPY products FROM '/Users/ivan/SQL3_RetailAnalitycs_v1.0-1/datasets/SKU_Mini.tsv' WITH (FORMAT csv, DELIMITER E'\t');
COPY store FROM '/Users/ivan/SQL3_RetailAnalitycs_v1.0-1/datasets/Stores_Mini.tsv' WITH (FORMAT csv, DELIMITER E'\t');


CREATE TEMP TABLE temp_table (
    col1 INT,
    col2 INT,
    col3 FLOAT,
    datetime_text TEXT,
    col5 INT
);
COPY temp_table FROM '/Users/ivan/SQL3_RetailAnalitycs_v1.0-1/datasets/Transactions_Mini.tsv' WITH (FORMAT csv, DELIMITER E'\t');



INSERT INTO transactions
SELECT col1, col2, col3, TO_TIMESTAMP(datetime_text, 'DD.MM.YYYY HH24:MI:SS'), col5
FROM temp_table;

DROP TABLE temp_table;

COPY bills FROM '/Users/ivan/SQL3_RetailAnalitycs_v1.0-1/datasets/Checks_Mini.tsv' WITH (FORMAT csv, DELIMITER E'\t');

CREATE TEMP TABLE temp_table
(
    datetime_text TEXT
);
COPY temp_table from '/Users/ivan/SQL3_RetailAnalitycs_v1.0-1/datasets/Date_Of_Analysis_Formation.tsv' WITH (FORMAT csv, DELIMITER E'\t');
INSERT INTO analysis_date
SELECT TO_TIMESTAMP(datetime_text, 'DD.MM.YYYY HH24:MI:SS')
FROM temp_table;
DROP TABLE temp_table;
