-- materialized view main - будет использоваться в дальнейшем
DROP MATERIALIZED VIEW IF EXISTS main CASCADE;
CREATE MATERIALIZED VIEW main AS
SELECT cd.customer_id,
       tr.transaction_id,
       tr.transaction_datetime,
       bl.sku_id,
       pd.group_id,
       bl.sku_amount,
       bl.sku_summ,
       bl.sku_summ_paid,
       bl.sku_discount,
       st.sku_purchace_price,
       st.sku_purchace_price * bl.sku_amount AS sku_cost,
       st.sku_retail_price
FROM transactions AS tr
JOIN cards AS cd ON cd.customer_card_id = tr.customer_card_id
JOIN bills AS bl ON bl.transaction_id = tr.transaction_id
JOIN products as pd ON pd.sku_id = bl.sku_id
JOIN store AS st ON st.transaction_store_id = tr.transaction_store_id AND st.sku_id = pd.sku_id;

-- purchase_history
DROP VIEW IF EXISTS purchase_history;
CREATE VIEW purchase_history AS
SELECT customer_id AS "Customer_ID",
       transaction_id AS "Transaction_ID",
       transaction_datetime AS "Transaction_DateTime",
       group_id AS "Group_ID",
       ROUND(SUM(sku_cost), 2) AS "Group_Cost",
       ROUND(SUM(sku_summ), 2) AS "Group_Summ",
       ROUND(SUM(sku_summ_paid), 2) AS "Group_Summ_Paid"
FROM main
GROUP BY customer_id,
         transaction_id,
         transaction_datetime,
         group_id;

SELECT * FROM purchase_history;