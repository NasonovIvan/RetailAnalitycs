create or replace function average_period(
    start_date date,
    end_date date,
    koeff_up decimal
)
    returns table
            (
                customer_id   int,
                average_check decimal
            )

as
$$
begin
    return query
        select c.customer_id, avg(t.transaction_summ) * koeff_up
        from cards c
                 join transactions t on c.customer_card_id = t.customer_card_id
        where t.transaction_datetime >= start_date
          and t.transaction_datetime <= end_date
        group by c.customer_id, koeff_up;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION average_count(transactions_count int, koeff_up decimal)
    RETURNS TABLE
            (
                customer_id   int,
                average_check decimal
            )
    LANGUAGE plpgsql
AS
$$
BEGIN
    CREATE TEMP TABLE temp_row_numbers AS
    SELECT c.customer_id,
           t.transaction_summ,
           ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY t.transaction_datetime DESC) AS row_num
    FROM cards c
             JOIN transactions t ON c.customer_card_id = t.customer_card_id;

    RETURN QUERY
        SELECT temp_row_numbers.customer_id,
               AVG(transaction_summ) * koeff_up AS average_check
        FROM temp_row_numbers
        WHERE row_num <= transactions_count
        GROUP BY temp_row_numbers.customer_id, koeff_up;

    DROP TABLE IF EXISTS temp_row_numbers;
END;
$$;

drop function if exists reward_group(decimal, decimal, decimal);
create or replace function reward_group(
    max_churn_rate decimal,
    max_transitions_with_discount decimal,
    max_margin_share decimal
)
    returns table
            (
                customer_id            int,
                group_id               int,
                group_margin           decimal,
                group_minimum_discount decimal
            )
as
$$
begin
    return query
        with tmp as (select *
                     from (select "Customer_ID",
                                  "Group_ID",
                                  ("Group_Margin" * max_margin_share)          as custom_margin,
                                  ceil("Group_Minimum_Discount" / 0.05) * 0.05 as rounded_min_discount,
                                  "2".rn                                       as rn
                           from (select *,
                                        row_number()
                                        over (partition by "Customer_ID" order by "Group_Affinity_Index") rn
                                 from groups
                                 where "Group_Churn_Rate" <= max_churn_rate
                                   and "Group_Discount_Share" < max_transitions_with_discount) as "2") as "3"
                     where custom_margin <= rounded_min_discount)

        select tmp."Customer_ID", tmp."Group_ID", tmp.custom_margin, tmp.rounded_min_discount
        from tmp
                 right join (select "Customer_ID", min(rn) as rn from tmp group by "Customer_ID") t2
                            on tmp."Customer_ID" = t2."Customer_ID" and tmp.rn = t2.rn;
end;
$$ language plpgsql;

select *
from reward_group(100, 0.7, 0.3);

drop function if exists average_check_up(int, date, date, int,
                                         decimal, decimal, decimal, decimal);
create or replace function average_check_up(
    calc_method int default 1,
    first_date date default current_date,
    last_date date default current_date,
    transactions_num int default 5,
    koeff_up decimal default 2,
    max_churn_rate decimal default 100,
    max_transitions_with_discount decimal default 0.7,
    max_margin_share decimal default 0.3
)
    returns table
            (
                customer_id            int,
                required_check_measure decimal,
                group_name             varchar(50),
                offer_discount_depth   decimal
            )
as
$$
declare
    upper_bound date := (SELECT MAX(transaction_datetime)
                         FROM transactions);
    lower_bound date := (SELECT MIN(transaction_datetime)
                         FROM transactions);

begin
    IF last_date < first_date THEN
        last_date = upper_bound;
    END IF;
    IF last_date > upper_bound THEN
        last_date = upper_bound;
    END IF;
    IF first_date < lower_bound THEN
        first_date = lower_bound;
    END IF;

    if calc_method = 1 then
        return query
            select ap.customer_id, ap.average_check, sg.group_name, rg.group_margin
            from average_period(first_date, last_date, koeff_up) ap
                     join reward_group(max_churn_rate, max_transitions_with_discount, max_margin_share) rg
                          on ap.customer_id = rg.customer_id
                     join sku_groups sg on rg.group_id = sg.group_id;
    elsif calc_method = 2 then
        return query
            select ac.customer_id, ac.average_check, sg.group_name, rg.group_margin
            from average_count(transactions_num, koeff_up) ac
                     join reward_group(max_churn_rate, max_transitions_with_discount, max_margin_share) rg
                          on ac.customer_id = rg.customer_id
                     join sku_groups sg on rg.group_id = sg.group_id;
    ELSE
        RAISE EXCEPTION 'Select 1 or 2 as calc method parameter';
    END IF;

end;
$$ language plpgsql;

SELECT *
FROM average_check_up(2);