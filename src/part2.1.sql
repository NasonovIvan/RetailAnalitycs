DROP VIEW IF EXISTS customers;
create view customers as
with Average_Checks as (select pe.customer_id,
                               avg(t.transaction_summ) as Customer_Average_Check
                        from personal_information pe
                                 join public.cards c on pe.customer_id = c.customer_id
                                 join public.transactions t on c.customer_card_id = t.customer_card_id
                        group by pe.customer_id
                        order by 2 desc),
     average_check_segment as (select *,
                                      (CASE
                                           WHEN ROW_NUMBER() OVER ()
                                               <= ROUND(((select count(*) from Average_Checks) * 0.1), 0)
                                               THEN 'High'::varchar(30)
                                           WHEN ROW_NUMBER() OVER ()
                                               <= ROUND((select count(*) from Average_Checks) * 0.35, 0)
                                               THEN 'Medium'::varchar(30)
                                           ELSE 'Low'::varchar(30) END)
                                          AS Customer_Average_Check_Segment
                               from Average_Checks),

     Frequency as (select pe.customer_id,
                          EXTRACT(DAY FROM (max(transaction_datetime) - min(transaction_datetime)) /
                                           count(transaction_datetime)) as Customer_Frequency
                   from personal_information pe
                            join public.cards c on pe.customer_id = c.customer_id
                            join public.transactions t on c.customer_card_id = t.customer_card_id
                   group by pe.customer_id
                   order by Customer_Frequency desc),
     frequency_segment as (select *,
                                  (CASE
                                       WHEN ROW_NUMBER() OVER ()
                                           <= ROUND(((select count(*) from Average_Checks) * 0.1), 0)
                                           THEN 'Often'::varchar(30)
                                       WHEN ROW_NUMBER() OVER ()
                                           <= ROUND((select count(*) from Average_Checks) * 0.35, 0)
                                           THEN 'Occasionally'::varchar(30)
                                       ELSE 'Rarely'::varchar(30) END)
                                      AS Customer_Frequency_Segment
                           from Frequency),

     Inactive_Period as (select pe.customer_id,
                                EXTRACT(DAY FROM ((select analysis_information from analysis_date) -
                                                  max(transaction_datetime))) as Customer_Inactive_Period
                         from personal_information pe
                                  join public.cards c on pe.customer_id = c.customer_id
                                  join public.transactions t on c.customer_card_id = t.customer_card_id
                         group by pe.customer_id),
     Churn_Rate as (select customer_id,
                           f.Customer_Frequency / ip.Customer_Inactive_Period as Customer_Churn_Rate
                    from Frequency f
                             natural join Inactive_Period ip),
     churn_segment as (select customer_id,
                              Customer_Churn_Rate,
                              (case
                                   when Customer_Churn_Rate < 2 then 'Low'
                                   when Customer_Churn_Rate < 5 then 'Medium'
                                   else 'High'
                                  end) as Customer_Churn_Segment
                       from Churn_Rate),
     Average_Segment as (select customer_id,
                                ((case
                                      when customer_average_check_segment = 'Low' then 0
                                      when customer_average_check_segment = 'Medium' then 1
                                      else 2 end) * 9 +
                                 (case
                                      when Customer_Frequency_Segment = 'Rarely' then 0
                                      when Customer_Frequency_Segment = 'Occasionally' then 1
                                      else 2 end) * 3 +
                                 (case
                                      when Customer_Churn_Segment = 'Low' then 0
                                      when Customer_Churn_Segment = 'Medium' then 1
                                      else 2 end) + 1) as Customer_Average_Segment
                         from average_check_segment
                                  natural join frequency_segment
                                  natural join churn_segment),
    store_count AS (SELECT c.customer_id,
                            transaction_store_id,
                            COUNT(transaction_store_id)                                                 AS tr_count,
                            ROW_NUMBER()
                            OVER (PARTITION BY c.customer_id ORDER BY COUNT(transaction_store_id) DESC) AS rn
                     FROM personal_information
                              JOIN public.cards c ON personal_information.customer_id = c.customer_id
                              JOIN public.transactions t ON c.customer_card_id = t.customer_card_id
                     GROUP BY c.customer_id,
                              transaction_store_id),
     most_popular_store as (SELECT customer_id,
                                   transaction_store_id
                            FROM store_count
                            WHERE rn = 1
                            ORDER BY customer_id),
     last_stores as (select pi.customer_id,
                            t.transaction_datetime,
                            t.Transaction_Store_ID,
                            row_number()
                            over (PARTITION BY pi.customer_id ORDER BY t.transaction_datetime desc) as transaction_number
                     from personal_information pi
                              join public.cards c on pi.customer_id = c.customer_id
                              join public.transactions t on c.customer_card_id = t.customer_card_id
                     order by pi.customer_id, t.transaction_datetime desc),
     three_last_stores as (select *
                           from last_stores
                           where transaction_number < 4),
     popular_last_store as (select customer_id,
                                   case
                                       WHEN COUNT(DISTINCT transaction_store_id) > 1 THEN 0
                                       ELSE max(transaction_store_id)
                                       END AS customer_popular_last_store
                            from three_last_stores
                            group by customer_id),
     Primary_Store as (select customer_id,
                              (case
                              when pls.customer_popular_last_store >0 then pls.customer_popular_last_store
                       else mps.transaction_store_id end) as Customer_Primary_Store
                       from popular_last_store pls
                       natural join most_popular_store mps)
select *
from average_check_segment
natural join frequency_segment
    natural join Inactive_Period
natural join churn_segment
natural join Average_Segment
natural join Primary_Store;

select * from customers;