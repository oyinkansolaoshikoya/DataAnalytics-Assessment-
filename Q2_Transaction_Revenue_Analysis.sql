/*
File: Q2_Transaction_Revenue_Analysis.sql
Purpose: Analyze transaction patterns to optimize pricing and identify revenue opportunities
Tables Used:
  - transactions: Payment records
  - exchange_rates: Currency conversion rates
  - transaction_fees: Fee structures

Key Metrics:
  - Monthly transaction volume/value by currency corridor
  - User segmentation by transaction behavior
  - Fee revenue analysis
  - Seasonal transaction patterns
*/

WITH 
-- Convert all amounts to USD for consistent analysis
transaction_values AS (
    SELECT
        t.id,
        t.user_id,
        t.initiated_at,
        t.source_currency || '/' || t.destination_currency AS currency_pair,
        t.source_amount / 100.0 AS source_amount_usd,
        (t.source_amount / 100.0) * er.rate AS destination_amount_usd,
        t.fee_amount / 100.0 AS fee_amount_usd,
        t.status,
        EXTRACT(DOW FROM t.initiated_at) AS day_of_week,
        EXTRACT(MONTH FROM t.initiated_at) AS month_of_year
    FROM
        transactions t
    JOIN
        exchange_rates er ON 
            t.source_currency || '/' || t.destination_currency = er.currency_pair AND
            er.date_recorded = DATE(t.initiated_at)
    WHERE
        t.status = 'completed'
),

-- Segment users by transaction behavior
user_segments AS (
    SELECT
        user_id,
        COUNT(*) AS transaction_count,
        SUM(source_amount_usd) AS total_value_usd,
        SUM(fee_amount_usd) AS total_fees_usd,
        CASE
            WHEN COUNT(*) >= 10 OR SUM(source_amount_usd) >= 10000 THEN 'High-Value'
            WHEN COUNT(*) >= 5 THEN 'Regular'
            WHEN COUNT(*) >= 1 THEN 'Occasional'
            ELSE 'Dormant'
        END AS user_segment
    FROM
        transaction_values
    GROUP BY
        user_id
),

-- Calculate corridor performance metrics
corridor_performance AS (
    SELECT
        currency_pair,
        DATE_TRUNC('month', initiated_at) AS month,
        COUNT(*) AS transaction_count,
        SUM(source_amount_usd) AS total_value_usd,
        SUM(fee_amount_usd) AS total_fees_usd,
        SUM(fee_amount_usd) / NULLIF(SUM(source_amount_usd), 0) AS effective_fee_rate,
        AVG(source_amount_usd) AS avg_txn_size_usd
    FROM
        transaction_values
    GROUP BY
        currency_pair,
        DATE_TRUNC('month', initiated_at)
),

-- Identify seasonal patterns
seasonal_patterns AS (
    SELECT
        day_of_week,
        month_of_year,
        COUNT(*) AS transaction_count,
        SUM(source_amount_usd) AS total_value_usd,
        SUM(fee_amount_usd) AS total_fees_usd
    FROM
        transaction_values
    GROUP BY
        day_of_week,
        month_of_year
)

-- Final business-ready output
SELECT
    -- Time dimensions
    TO_CHAR(cp.month, 'YYYY-MM') AS month,
    cp.currency_pair,
    
    -- User segments
    us.user_segment,
    COUNT(DISTINCT tv.user_id) AS user_count,
    
    -- Transaction metrics
    cp.transaction_count,
    cp.total_value_usd,
    cp.total_fees_usd,
    ROUND(cp.effective_fee_rate * 100, 2) || '%' AS effective_fee_rate_pct,
    cp.avg_txn_size_usd,
    
    -- Seasonal patterns
    sp.day_of_week,
    sp.month_of_year,
    sp.transaction_count AS seasonal_txn_count,
    sp.total_value_usd AS seasonal_value_usd,
    
    -- Fee structure context
    tf.fee_type,
    tf.fee_value AS fee_percentage,
    tf.minimum_fee / 100.0 AS min_fee_usd,
    tf.maximum_fee / 100.0 AS max_fee_usd,
    
    -- Business recommendations
    CASE
        WHEN cp.effective_fee_rate < 0.02 THEN 'Consider fee increase'
        WHEN cp.effective_fee_rate > 0.04 THEN 'Potential for volume discounts'
        ELSE 'Optimal fee range'
    END AS pricing_recommendation
FROM
    corridor_performance cp
JOIN
    transaction_values tv ON 
        cp.currency_pair = tv.currency_pair AND
        cp.month = DATE_TRUNC('month', tv.initiated_at)
JOIN
    user_segments us ON tv.user_id = us.user_id
JOIN
    seasonal_patterns sp ON
        tv.day_of_week = sp.day_of_week AND
        tv.month_of_year = sp.month_of_year
LEFT JOIN
    transaction_fees tf ON
        cp.currency_pair = tf.currency_pair AND
        tf.is_active = true
GROUP BY
    cp.month,
    cp.currency_pair,
    us.user_segment,
    cp.transaction_count,
    cp.total_value_usd,
    cp.total_fees_usd,
    cp.effective_fee_rate,
    cp.avg_txn_size_usd,
    sp.day_of_week,
    sp.month_of_year,
    sp.transaction_count,
    sp.total_value_usd,
    tf.fee_type,
    tf.fee_value,
    tf.minimum_fee,
    tf.maximum_fee
ORDER BY
    cp.month,
    cp.total_fees_usd DESC;