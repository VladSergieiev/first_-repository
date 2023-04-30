WITH user_loyalty_fixed AS (
  SELECT
    id,
    tags,
    user_id,
    CASE WHEN created_at IS NULL THEN valid_until - '1 year'::INTERVAL ELSE created_at END AS created_at,
    valid_until,
    order_id,
    sku_id
  FROM
    user_loyalty
  WHERE
    --tags IS NULL OR tags = 'gone-black' --OR tags LIKE 'promocode%'
    tags IS NULL OR tags in ('gone-black', 'wartime', 'wartime switched to black9', 'manually updated 8 to 9', 'try-black')
),

black as (
  SELECT DISTINCT
    ul.user_id,
    min(DATE(ul.created_at)) as created_at,
    max(DATE(ul.valid_until)) as valid_until
  FROM
    order_order AS oo
    RIGHT JOIN user_loyalty_fixed AS ul ON oo.id = ul.order_id
    left join basket_basketitem as bi on bi.order_id = oo.id
  WHERE
    (oo.is_cancelled IS FALSE OR oo.is_cancelled IS NULL)
        AND ul.valid_until >= '2023-01-01'
        AND ul.created_at < '2023-05-01'
group by 1
),

orders as (
SELECT
            date(oo.created_at) as days,
            oo.id as order_id,
            case when not oo.is_cancelled  and bi.return_accepted_quantity < bi.quantity then oo.id else null end as net_orders,
            case
                when p1.ref1c is not null then '1P' --1P: First Party - Marketplace or platform owner/operator who sells products or services directly, handling fulfillment through their own warehouses
                when oo.market_type = 'v3' and p1.ref1c is null then '2P' --2P: Second Party - Seller on the marketplace or platform who uses the marketplace's or platform's fulfillment services or warehouses for storing and shipping products to customers
                when oo.is_marketplace = true then '2P'
                when oo.market_type = 'v4' then '3P' --3P: Third Party - Independent seller on the marketplace or platform who handles their own fulfillment and warehousing, separate from the marketplace or platform
                else '?'
            end as model,
            case when oo.bank_name = 'kastapay' then oo.id else null end as card_pay,
            me.market,
            me.flash,
            b.user_id as black,
            
            SUM(bi.persisted_price * bi.quantity) as revenue,
            SUM(bi.persisted_price * (bi.quantity - bi.cancelled_quantity - bi.return_accepted_quantity)) as net_revenue,
            SUM(bi.supplier_price * (bi.quantity - bi.cancelled_quantity - bi.return_accepted_quantity)) as supplier_price_net,
            --SUM(bi.persisted_price * (bi.quantity - bi.cancelled_quantity - bi.return_accepted_quantity)) - SUM(bi.supplier_price * (bi.quantity - bi.cancelled_quantity - bi.return_accepted_quantity)) as net_gross_profit,
            case
                when bi.campaign_id is not null and me.flash is not null then sum(bi.persisted_price * (bi.quantity - bi.cancelled_quantity - bi.return_accepted_quantity)) * me.flash
                when bi.campaign_id is null and me.market is not null then sum(bi.persisted_price * (bi.quantity - bi.cancelled_quantity - bi.return_accepted_quantity)) * me.market
                else SUM(bi.persisted_price * (bi.quantity - bi.cancelled_quantity - bi.return_accepted_quantity)) - SUM(bi.supplier_price * (bi.quantity - bi.cancelled_quantity - bi.return_accepted_quantity))
            end as net_gross_profit
            
FROM order_order AS oo
JOIN basket_basketitem AS bi ON bi.order_id = oo.id
left join bi_supplier_1p_contract p1 on p1.ref1c = bi.contract_ref1c
left join product_sku as sku on sku.id = bi.sku_id
left join bi_supplier as s on s.batch_id = sku.batch_id
left join bi_margin_exceptions as me on me.gk = s.gk_name and date(oo.created_at) between date(me."period") and date(me.periodend)
left join black as b on b.user_id = oo.persisted_user_id and date(oo.created_at) BETWEEN b.created_at and b.valid_until


WHERE true
    AND oo.payment_received
    AND persisted_user_id NOT IN (5064814,5910386,6069395,6643002,7338866,7477227,8129278,8207648,8207927,8302610,8317620)
    AND (oo.persisted_campaign_id <> 22148 OR oo.persisted_campaign_id IS NULL)
  and date(oo.created_at) >= '2023-01-01'
    and date(oo.created_at) < '2023-05-01'
group by 1, 2, 3, 4, 5, 6, 7, 8, bi.campaign_id
)

SELECT
            date(date_trunc('month', days)) as months,
            
            sum(revenue) as "revenue",
            sum(net_revenue) as "net_revenue",
            sum(net_gross_profit) as "net_gross_profit",
            
            sum(case when black is not null then revenue else 0 end) as "black_revenue",
            sum(case when black is not null then net_revenue else 0 end) as "black_net_revenue",
            sum(case when black is not null then net_gross_profit else 0 end) as "black_net_gross_profit",
            count(distinct case when black is not null then net_orders else null end) as "black_net_orders",
            count(distinct case when black is not null and card_pay is not null then net_orders else null end) as "black_net_orders_card_pay",
            sum(case when black is not null and model = '1P' then revenue else 0 end) as "1p_black_revenue",
            sum(case when black is not null and model = '2P' then revenue else 0 end) as "2p_black_revenue",
            sum(case when black is not null and model = '3P' then revenue else 0 end) as "3p_black_revenue",
            sum(case when black is not null and model = '1P' then net_revenue else 0 end) as "1p_black_net_revenue",
            sum(case when black is not null and model = '2P' then net_revenue else 0 end) as "2p_black_net_revenue",
            sum(case when black is not null and model = '3P' then net_revenue else 0 end) as "3p_black_net_revenue",
            sum(case when black is not null and model = '1P' then net_gross_profit else 0 end) as "1p_black_net_gross_profit",
            sum(case when black is not null and model = '2P' then net_gross_profit else 0 end) as "2p_black_net_gross_profit",
            sum(case when black is not null and model = '3P' then net_gross_profit else 0 end) as "3p_black_net_gross_profit",
            count(distinct case when black is not null and model = '1P' then net_orders else null end) as "1p_black_net_orders",
            count(distinct case when black is not null and model = '2P' then net_orders else null end) as "2p_black_net_orders",
            count(distinct case when black is not null and model = '3P' then net_orders else null end) as "3p_black_net_orders",
            count(distinct case when black is not null and model = '1P' and card_pay is not null then net_orders else null end) as "1p_black_net_orders_card_pay",
            count(distinct case when black is not null and model = '2P' and card_pay is not null then net_orders else null end) as "2p_black_net_orders_card_pay",
            count(distinct case when black is not null and model = '3P' and card_pay is not null then net_orders else null end) as "3p_black_net_orders_card_pay",
            
            sum(case when black is null then revenue else 0 end) as "non_black_revenue",
            sum(case when black is null then net_revenue else 0 end) as "non_black_net_revenue",
            sum(case when black is null then net_gross_profit else 0 end) as "non_black_net_gross_profit",
            count(distinct case when black is null then net_orders else null end) as "non_black_net_orders",
            count(distinct case when black is null and card_pay is not null then net_orders else null end) as "non_black_net_orders_card_pay",
            sum(case when black is null and model = '1P' then revenue else 0 end) as "1p_non_black_revenue",
            sum(case when black is null and model = '2P' then revenue else 0 end) as "2p_non_black_revenue",
            sum(case when black is null and model = '3P' then revenue else 0 end) as "3p_non_black_revenue",
            sum(case when black is null and model = '1P' then net_revenue else 0 end) as "1p_non_black_net_revenue",
            sum(case when black is null and model = '2P' then net_revenue else 0 end) as "2p_non_black_net_revenue",
            sum(case when black is null and model = '3P' then net_revenue else 0 end) as "3p_non_black_net_revenue",
            sum(case when black is null and model = '1P' then net_gross_profit else 0 end) as "1p_non_black_net_gross_profit",
            sum(case when black is null and model = '2P' then net_gross_profit else 0 end) as "2p_non_black_net_gross_profit",
            sum(case when black is null and model = '3P' then net_gross_profit else 0 end) as "3p_non_black_net_gross_profit",
            count(distinct case when black is null and model = '1P' then net_orders else null end) as "1p_non_black_net_orders",
            count(distinct case when black is null and model = '2P' then net_orders else null end) as "2p_non_black_net_orders",
            count(distinct case when black is null and model = '3P' then net_orders else null end) as "3p_non_black_net_orders",
            count(distinct case when black is null and model = '1P' and card_pay is not null then net_orders else null end) as "1p_non_black_net_orders_card_pay",
            count(distinct case when black is null and model = '2P' and card_pay is not null then net_orders else null end) as "2p_non_black_net_orders_card_pay",
            count(distinct case when black is null and model = '3P' and card_pay is not null then net_orders else null end) as "3p_non_black_net_orders_card_pay"
            
FROM orders AS oo
group by 1
order by 1