
-- Materialized view affinity_index
DROP MATERIALIZED VIEW IF EXISTS affinity_index;
CREATE MATERIALIZED VIEW affinity_index AS
SELECT
    p."Customer_ID"::bigint AS customer_id,
    p."Group_ID"::bigint AS group_id,
    ROUND(
        COALESCE(p."Group_Purchase"::numeric / NULLIF(COUNT(DISTINCT ph."Transaction_ID"), 0), 0), 2
    ) AS group_affinity_index
FROM
    periods p
LEFT JOIN
    purchase_history ph ON ph."Customer_ID" = p."Customer_ID"
        AND ph."Transaction_DateTime" BETWEEN p."First_Group_Purchase_Date" AND p."Last_Group_Purchase_Date"
GROUP BY
    p."Customer_ID", p."Group_ID", p."Group_Purchase";

-- Materialized view churn_rate
DROP MATERIALIZED VIEW IF EXISTS churn_rate;
CREATE MATERIALIZED VIEW churn_rate AS
SELECT
    p."Customer_ID"::bigint AS customer_id,
    p."Group_ID"::bigint AS group_id,
    CASE
        WHEN p."Group_Frequency" = 0 THEN 0::numeric
        ELSE ROUND(
            (DATE_PART('day', (SELECT MAX(analysis_information) FROM analysis_date) - p."Last_Group_Purchase_Date"))::numeric / p."Group_Frequency", 2
        )::numeric
    END AS churn_rate
FROM
    periods p
LEFT JOIN
    purchase_history ph ON ph."Customer_ID" = p."Customer_ID"
GROUP BY
    p."Customer_ID", p."Group_ID", p."Last_Group_Purchase_Date", p."Group_Frequency";

-- Materialized view stability_index
DROP MATERIALIZED VIEW IF EXISTS stability_index;
CREATE MATERIALIZED VIEW stability_index AS
WITH stability_temp AS (
    SELECT
        ph."Customer_ID"::bigint AS customer_id,
        ph."Group_ID"::bigint AS group_id,
        ph."Transaction_DateTime" AS tr_date,
        COALESCE(DATE_PART('day', ph."Transaction_DateTime" - LAG(ph."Transaction_DateTime") OVER (PARTITION BY ph."Customer_ID", ph."Group_ID" ORDER BY ph."Transaction_DateTime")), 0) AS intervals,
        p."Group_Frequency" AS gr_frequency
    FROM
        purchase_history ph
    JOIN
        periods p ON p."Customer_ID" = ph."Customer_ID" AND p."Group_ID" = ph."Group_ID"
)
SELECT
    customer_id,
    group_id,
    ROUND(
        AVG(
            CASE
                WHEN gr_frequency = 0 THEN 0
                ELSE
                    CASE
                        WHEN gr_frequency > intervals THEN gr_frequency - intervals
                        ELSE intervals - gr_frequency
                    END::numeric / gr_frequency
            END
        ), 2
    ) AS stability_index
FROM
    stability_temp
GROUP BY
    customer_id, group_id;

-- Materialized view discount_share_min
DROP MATERIALIZED VIEW IF EXISTS discount_share_min;
CREATE MATERIALIZED VIEW discount_share_min AS
WITH discount_transaction AS (
    SELECT
        m.customer_id::bigint AS customer_id,
        m.group_id::bigint AS group_id,
        COUNT(DISTINCT transaction_id) AS qty_dis_tr
    FROM
        main m
    WHERE
        m.sku_discount > 0
    GROUP BY
        m.customer_id, m.group_id
)
SELECT
    p."Customer_ID"::bigint AS customer_id,
    p."Group_ID"::bigint AS group_id,
    ROUND(COALESCE(dt.qty_dis_tr, 0)::numeric / p."Group_Purchase", 2) AS group_discount_share,
    p."Group_Min_Discount" AS group_min_discount
FROM
    discount_transaction dt
RIGHT JOIN
    periods p ON p."Customer_ID" = dt.customer_id AND p."Group_ID" = dt.group_id;

-- Materialized view group_average_discount
DROP MATERIALIZED VIEW IF EXISTS group_average_discount;
CREATE MATERIALIZED VIEW group_average_discount AS
SELECT
    "Customer_ID"::bigint AS customer_id,
    "Group_ID"::bigint AS group_id,
    ROUND(SUM("Group_Summ_Paid") / NULLIF(SUM("Group_Summ"), 0), 2) AS group_average_discount
FROM
    purchase_history
GROUP BY
    "Customer_ID", "Group_ID";

-- group margin function 
DROP FUNCTION IF EXISTS func_group_margin(int, int) CASCADE;
CREATE OR REPLACE FUNCTION func_group_margin(mode_margin int DEFAULT 3, in_value int DEFAULT 100)
RETURNS TABLE (
    customer_id BIGINT,
    group_id BIGINT,
    group_margin NUMERIC
)
AS $$
BEGIN
    IF mode_margin = 1 THEN
        RETURN QUERY
        SELECT
            "Customer_ID"::bigint AS customer_id,
            "Group_ID"::bigint AS group_id,
            CASE
                WHEN SUM("Group_Summ_Paid") > 0 THEN ROUND(SUM("Group_Summ_Paid" - "Group_Cost") / SUM("Group_Summ_Paid"), 2)
                ELSE 0
            END AS group_margin
        FROM
            purchase_history
        WHERE
            "Transaction_DateTime"::DATE >= (
                SELECT
                    MAX(analysis_information)::DATE - in_value
                FROM
                    date_of_analysis_formation
            )
        GROUP BY
            "Customer_ID", "Group_ID";

    ELSIF mode_margin = 2 THEN
        RETURN QUERY
        SELECT
            "Customer_ID"::bigint AS customer_id,
            "Group_ID"::bigint AS group_id,
            CASE
                WHEN SUM("Group_Summ_Paid") > 0 THEN ROUND(SUM(("Group_Summ_Paid" - "Group_Cost") / "Group_Summ_Paid"), 2)
                ELSE 0
            END AS group_margin
        FROM (
            SELECT
                "Customer_ID",
                "Group_ID",
                "Group_Summ_Paid" - "Group_Cost" AS margin
            FROM
                purchase_history
            ORDER BY
                "Transaction_DateTime" DESC
            LIMIT
                1000
        ) AS lph
        GROUP BY
            "Customer_ID", "Group_ID";

    ELSE
        RETURN QUERY
        SELECT
            "Customer_ID"::bigint AS customer_id,
            "Group_ID"::bigint AS group_id,
            CASE
                WHEN SUM("Group_Summ_Paid") > 0 THEN ROUND(SUM("Group_Summ_Paid" - "Group_Cost") / SUM("Group_Summ_Paid"), 2)
                ELSE 0
            END AS group_margin
        FROM
            purchase_history
        GROUP BY
            "Customer_ID", "Group_ID";
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Materialized view groups
DROP VIEW IF EXISTS groups;
CREATE VIEW groups AS
SELECT
    gm.customer_id AS "Customer_ID",
    gm.group_id AS "Group_ID",
    ai.group_affinity_index AS "Group_Affinity_Index",
    cr.churn_rate AS "Group_Churn_Rate",
    si.stability_index AS "Group_Stability_Index",
    gm.group_margin AS "Group_Margin",
    dsm.group_discount_share AS "Group_Discount_Share",
    dsm.group_min_discount AS "Group_Minimum_Discount",
    gad.group_average_discount AS "Group_Average_Discount"
FROM
    func_group_margin() AS gm
JOIN
    affinity_index AS ai ON ai.customer_id = gm.customer_id AND ai.group_id = gm.group_id
JOIN
    churn_rate AS cr ON cr.customer_id = gm.customer_id AND cr.group_id = gm.group_id
JOIN
    stability_index AS si ON si.customer_id = gm.customer_id AND si.group_id = gm.group_id
JOIN
    discount_share_min AS dsm ON dsm.customer_id = gm.customer_id AND dsm.group_id = gm.group_id
JOIN
    group_average_discount AS gad ON gad.customer_id = gm.customer_id AND gad.group_id = gm.group_id;