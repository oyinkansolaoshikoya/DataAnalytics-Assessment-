-- Geographic Market Performance Analysis
-- Purpose: Identify high-growth markets and underperforming regions for strategic investment
-- Tables Used: users, transactions, user_verifications, payment_methods
-- Business Logic: Analyzes market performance by country with verification tiers and payment methods
-- Edge Cases Handled: NULL values, division by zero, data quality checks

WITH 
-- Base metric calculation with data quality checks
market_base_metrics AS (
    SELECT
        u.country_code,
        DATE_TRUNC('month', t.initiated_at) AS analysis_month,
        
        -- User metrics with NULL handling
        COUNT(DISTINCT u.id) AS total_users,
        COUNT(DISTINCT CASE WHEN uv.kyc_status = 'approved' THEN u.id END) AS approved_users,
        
        -- Transaction metrics with completed status check
        COUNT(t.id) AS total_transactions,
        COUNT(CASE WHEN t.status = 'completed' THEN 1 END) AS successful_transactions,
        SUM(CASE WHEN t.status = 'completed' THEN t.source_amount::DECIMAL / 100 ELSE 0 END) AS volume_usd,
        SUM(CASE WHEN t.status = 'completed' THEN t.revenue_usd ELSE 0 END) AS revenue_usd,
        
        -- Payment method distribution
        COUNT(CASE WHEN pm.method_name = 'Bank Transfer' THEN 1 END) AS bank_transfer_count,
        COUNT(CASE WHEN pm.method_name = 'Mobile Money' THEN 1 END) AS mobile_money_count,
        
        -- Verification tier metrics
        COUNT(DISTINCT CASE WHEN uv.verification_level = 3 THEN u.id END) AS tier3_users,
        COUNT(DISTINCT CASE WHEN uv.verification_level = 2 THEN u.id END) AS tier2_users
    FROM 
        users u
    JOIN 
        transactions t ON u.id = t.user_id
    LEFT JOIN 
        user_verifications uv ON u.id = uv.user_id
    LEFT JOIN 
        payment_methods pm ON t.payment_method_id = pm.id
    WHERE 
        t.initiated_at >= '2024-01-01'  -- Focus on current year data
    GROUP BY 
        u.country_code, 
        DATE_TRUNC('month', t.initiated_at)
),

-- Growth rate calculations with LAG functions
market_growth_metrics AS (
    SELECT
        *,
        LAG(total_users) OVER (PARTITION BY country_code ORDER BY analysis_month) AS prev_month_users,
        LAG(total_transactions) OVER (PARTITION BY country_code ORDER BY analysis_month) AS prev_month_transactions,
        LAG(volume_usd) OVER (PARTITION BY country_code ORDER BY analysis_month) AS prev_month_volume,
        LAG(revenue_usd) OVER (PARTITION BY country_code ORDER BY analysis_month) AS prev_month_revenue
    FROM 
        market_base_metrics
),

-- Final metrics with calculated percentages and growth rates
market_performance AS (
    SELECT
        country_code,
        TO_CHAR(analysis_month, 'YYYY-MM') AS report_month,
        
        -- User metrics
        total_users,
        ROUND(approved_users::DECIMAL / NULLIF(total_users, 0) * 100, 2) AS approval_rate,
        ROUND(tier3_users::DECIMAL / NULLIF(total_users, 0) * 100, 2) AS tier3_concentration,
        
        -- Transaction metrics
        total_transactions,
        ROUND(successful_transactions::DECIMAL / NULLIF(total_transactions, 0) * 100, 2) AS success_rate,
        ROUND(volume_usd, 2) AS volume_usd,
        ROUND(revenue_usd, 2) AS revenue_usd,
        ROUND(revenue_usd / NULLIF(volume_usd, 0) * 100, 2) AS margin_pct,
        
        -- Payment method distribution
        ROUND(bank_transfer_count::DECIMAL / NULLIF(total_transactions, 0) * 100, 2) AS bank_transfer_pct,
        ROUND(mobile_money_count::DECIMAL / NULLIF(total_transactions, 0) * 100, 2) AS mobile_money_pct,
        
        -- Growth calculations with NULL handling
        CASE 
            WHEN prev_month_users IS NULL THEN NULL
            ELSE ROUND((total_users - prev_month_users)::DECIMAL / NULLIF(prev_month_users, 0) * 100, 2)
        END AS user_growth_pct,
        
        CASE 
            WHEN prev_month_revenue IS NULL THEN NULL
            ELSE ROUND((revenue_usd - prev_month_revenue)::DECIMAL / NULLIF(prev_month_revenue, 0) * 100, 2)
        END AS revenue_growth_pct,
        
        -- Market classification
        CASE
            WHEN (revenue_usd - prev_month_revenue)::DECIMAL / NULLIF(prev_month_revenue, 0) * 100 > 20 THEN 'High Growth'
            WHEN (revenue_usd - prev_month_revenue)::DECIMAL / NULLIF(prev_month_revenue, 0) * 100 < -5 THEN 'Declining'
            ELSE 'Stable'
        END AS growth_category
    FROM 
        market_growth_metrics
)

-- Final output with all market performance metrics
SELECT
    country_code,
    report_month,
    total_users,
    approval_rate,
    tier3_concentration,
    total_transactions,
    success_rate,
    volume_usd,
    revenue_usd,
    margin_pct,
    bank_transfer_pct,
    mobile_money_pct,
    user_growth_pct,
    revenue_growth_pct,
    growth_category,
    
    -- Performance scoring
    CASE
        WHEN revenue_growth_pct > 20 AND tier3_concentration > 15 THEN 'Priority Market'
        WHEN revenue_growth_pct > 15 AND success_rate > 90 THEN 'Growth Market'
        WHEN revenue_growth_pct < -5 THEN 'At-Risk Market'
        ELSE 'Core Market'
    END AS investment_priority
FROM 
    market_performance
WHERE 
    report_month >= '2024-02'  -- Exclude partial first month
ORDER BY 
    country_code, 
    report_month,
    investment_priority DESC;