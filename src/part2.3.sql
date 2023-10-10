-- materialized view для periods
DROP VIEW IF EXISTS periods CASCADE;
CREATE VIEW periods AS
SELECT customer_id::bigint AS "Customer_ID",
       group_id::bigint AS "Group_ID",
       MIN(transaction_datetime) AS "First_Group_Purchase_Date",
       MAX(transaction_datetime) AS "Last_Group_Purchase_Date",
       COUNT(*) AS "Group_Purchase",
       ((MAX(transaction_datetime)::date - MIN(transaction_datetime)::date) + 1) / COUNT(*) AS "Group_Frequency",
       ROUND(COALESCE(MIN(NULLIF(sku_discount / NULLIF(sku_summ, 0), 0)), 0), 2) AS "Group_Min_Discount"
FROM main
GROUP BY customer_id, group_id;

SELECT * FROM periods;
