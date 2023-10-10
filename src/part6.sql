-- Создаем представление product_groups_view
DROP VIEW IF EXISTS product_groups_view;
CREATE VIEW product_groups_view AS
SELECT
    first_step.group_id,
    first_step.sku_id,
    first_step.sku_qty::numeric / second_step.gr_qty AS sku_share
FROM (
    SELECT
        group_id,
        sku_id,
        COUNT(DISTINCT transaction_id) AS sku_qty
    FROM main
    GROUP BY group_id, sku_id
) AS first_step
JOIN (
    SELECT
        group_id,
        COUNT(DISTINCT transaction_id) AS gr_qty
    FROM main
    GROUP BY group_id
) AS second_step
ON first_step.group_id = second_step.group_id;

-- Создаем функцию personal_suggestions
DROP FUNCTION IF EXISTS personal_suggestions(int, numeric, numeric, numeric, numeric);
CREATE FUNCTION personal_suggestions(group_qty int DEFAULT 5,
                              max_churn_index numeric DEFAULT 25,
                              max_stability_index numeric DEFAULT 2.5,
                              max_sku_share numeric DEFAULT 70,
                              allow_margin_share numeric DEFAULT 60)
    RETURNS table
    (
        "Customer_ID"          bigint,
        "SKU_Name"             varchar,
        "Offer_Discount_Depth" numeric
    )
AS
$$
BEGIN
    RETURN QUERY
        WITH suitable_groups AS (
    		SELECT
        		gv."Customer_ID" AS customer_id,
        		gv."Group_ID" AS group_id,
        		cus.customer_primary_store AS c_store,
        		ROW_NUMBER() OVER (PARTITION BY gv."Customer_ID" ORDER BY gv."Group_Affinity_Index" DESC) AS gr_rank
    		FROM groups AS gv
    		JOIN customers AS cus ON cus.customer_id = gv."Customer_ID"
    		WHERE gv."Group_Churn_Rate" <= max_churn_index
        		AND gv."Group_Stability_Index" < max_stability_index
		),
		ranked_groups AS (
    		SELECT
        		sg.*,
        		ROW_NUMBER() OVER (PARTITION BY sg.customer_id ORDER BY sg.gr_rank DESC) AS rank
    		FROM suitable_groups AS sg
		),
		result_groups AS (
			SELECT
    			rg.customer_id,
    			rg.group_id,
    			rg.c_store
			FROM ranked_groups AS rg
			WHERE rg.rank <= group_qty
		),
        most_suitable_sku AS (
    	-- Выбираем наиболее подходящий SKU для каждой группы и магазина
    		SELECT
        		st.transaction_store_id,
        		pd.group_id,
        		st.sku_id,
        		st.sku_retail_price,
        		st.sku_retail_price - st.sku_purchace_price AS diff_price,
        		ROW_NUMBER() OVER (PARTITION BY st.transaction_store_id, pd.group_id
                           	ORDER BY (st.sku_retail_price - st.sku_purchace_price) DESC) AS i
    		FROM store AS st
    		JOIN products pd ON st.sku_id = pd.sku_id
		),
		result_suitable_sku as (
			SELECT
    			rg.customer_id,
    			rg.group_id,
    			rg.c_store,
    			mss.sku_id,
    			mss.diff_price,
    			mss.sku_retail_price
			FROM result_groups AS rg
			JOIN most_suitable_sku AS mss ON mss.transaction_store_id = rg.c_store
            		AND mss.group_id = rg.group_id
                    AND mss.i = 1
		),                   
        filtered_sku AS (
    	-- Отбираем записи из result_suitable_sku, удовлетворяющие условию sku_share
    	SELECT
        	rss.customer_id,
        	rss.group_id,
        	rss.c_store,
        	rss.sku_id,
        	rss.diff_price,
        	rss.sku_retail_price,
        	p."Group_Min_Discount"
    	FROM result_suitable_sku AS rss
    	JOIN periods AS p ON rss.customer_id = p."Customer_ID"
                     AND rss.group_id = p."Group_ID"
    	JOIN product_groups_view AS ssg ON ssg.sku_id = rss.sku_id
                     AND ssg.group_id = rss.group_id
    	WHERE ssg.sku_share <= max_sku_share::numeric / 100
		),
		discounts AS (
    	-- Рассчитываем скидку и минимальную скидку
    	SELECT
        	fsk.customer_id,
        	fsk.group_id,
        	fsk.c_store,
        	fsk.sku_id,
        	(fsk.diff_price * allow_margin_share::numeric / 100) / fsk.sku_retail_price AS discount,
        	--ROUND(fsk."Group_Min_Discount" / 0.05) * 0.05 AS min_discount
        	CASE
	        	WHEN ROUND(fsk."Group_Min_Discount" / 0.05) * 0.05 < fsk."Group_Min_Discount"
                	THEN (ROUND(fsk."Group_Min_Discount" / 0.05) * 0.05 + 0.05)
               	ELSE (ROUND(fsk."Group_Min_Discount" / 0.05) * 0.05)
           	END AS min_discount
    	FROM filtered_sku AS fsk
		)
		SELECT
    		d.customer_id,
    		pd.sku_name,
    		d.min_discount * 100
		FROM discounts AS d
		JOIN products pd ON pd.sku_id = d.sku_id
		WHERE d.discount >= d.min_discount;
END;
$$ LANGUAGE plpgsql; 

-- Вызов функции и выборка результатов
SELECT * FROM personal_suggestions();



