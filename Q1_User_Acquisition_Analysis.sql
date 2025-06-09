/*
File: Q1_User_Acquisition_Analysis.sql
Purpose: Analyze user onboarding effectiveness and identify activation drivers for FX payment platform
Business Questions Addressed:
  1. Monthly user acquisition and activation rates
  2. Highest performing acquisition channels
  3. Average time to first transaction by country
  4. Onboarding funnel health indicators

Tables Used:
  - users: Core user information
  - transactions: Completed payment transactions
  - user_verifications: KYC verification status

Key Metrics:
  - Activation: First completed transaction within 30 days of registration
  - Only approved users (kyc_status = 'approved') are included
  - Test users (id <= 10) are excluded
*/

WITH 
-- CTE 1: Identify each user's activation status and timing
-- Uses FILTER to only consider completed transactions without adding status to GROUP BY
user_activation AS (
    SELECT 
        u.id AS user_id,
        u.registration_date,
        u.country_code,
        u.acquisition_channel,
        uv.verification_level,
        -- First completed transaction date
        MIN(t.initiated_at) FILTER (WHERE t.status = 'completed') AS first_completed_transaction_date,
        -- Activation flag (1 if first transaction within 30 days)
        CASE 
            WHEN MIN(t.initiated_at) FILTER (WHERE t.status = 'completed') IS NOT NULL
                 AND MIN(t.initiated_at) FILTER (WHERE t.status = 'completed') <= 
                     (u.registration_date + INTERVAL '30 days')
            THEN 1 
            ELSE 0 
        END AS activated_within_30_days,
        -- Days between registration and first completed transaction
        EXTRACT(DAY FROM 
            MIN(t.initiated_at) FILTER (WHERE t.status = 'completed') - 
            u.registration_date
        ) AS days_to_activation
    FROM 
        users u
    JOIN
        user_verifications uv 
        ON u.id = uv.user_id 
        AND uv.kyc_status = 'approved'
    LEFT JOIN 
        transactions t 
        ON u.id = t.user_id
    WHERE
        u.id > 10 -- Exclude test users
    GROUP BY 
        u.id, u.registration_date, u.country_code, 
        u.acquisition_channel, uv.verification_level
),

-- CTE 2: Aggregate metrics by key dimensions
monthly_metrics AS (
    SELECT
        DATE_TRUNC('month', u.registration_date) AS acquisition_month,
        u.country_code,
        u.acquisition_channel,
        uv.verification_level,
        -- Total approved users
        COUNT(DISTINCT u.id) AS total_users,
        -- Activated users count
        COUNT(DISTINCT CASE WHEN ua.activated_within_30_days = 1 THEN u.id END) AS activated_users,
        -- Activation rate with NULL handling
        ROUND(
            COUNT(DISTINCT CASE WHEN ua.activated_within_30_days = 1 THEN u.id END) * 100.0 / 
            NULLIF(COUNT(DISTINCT u.id), 0), 
            1
        ) AS activation_rate,
        -- Average days to activation (only for activated users)
        ROUND(
            AVG(CASE WHEN ua.activated_within_30_days = 1 THEN ua.days_to_activation END), 
            1
        ) AS avg_days_to_activation
    FROM
        users u
    JOIN
        user_verifications uv 
        ON u.id = uv.user_id 
        AND uv.kyc_status = 'approved'
    LEFT JOIN
        user_activation ua 
        ON u.id = ua.user_id
    WHERE
        u.id > 10 -- Exclude test users
    GROUP BY
        DATE_TRUNC('month', u.registration_date), 
        u.country_code, 
        u.acquisition_channel,
        uv.verification_level
)

-- Final output with formatted business metrics
SELECT
    TO_CHAR(mm.acquisition_month, 'YYYY-MM') AS acquisition_month,
    mm.country_code,
    INITCAP(REPLACE(mm.acquisition_channel, '_', ' ')) AS acquisition_channel,
    mm.verification_level,
    mm.total_users,
    mm.activated_users,
    mm.activation_rate || '%' AS activation_rate,
    mm.avg_days_to_activation,
    -- Additional business context
    COUNT(DISTINCT pm.id) AS available_payment_methods,
    ROUND(AVG(uv.monthly_limit_usd), 0) AS avg_monthly_limit_usd,
    ROUND(AVG(uv.single_transaction_limit_usd), 0) AS avg_transaction_limit_usd,
    -- Funnel health indicator
    CASE 
        WHEN mm.activation_rate < 50 THEN 'Needs Improvement'
        WHEN mm.activation_rate < 70 THEN 'Moderate'
        ELSE 'Strong'
    END AS funnel_health
FROM
    monthly_metrics mm
JOIN
    users u 
    ON DATE_TRUNC('month', u.registration_date) = mm.acquisition_month
    AND u.country_code = mm.country_code
    AND u.acquisition_channel = mm.acquisition_channel
JOIN
    user_verifications uv 
    ON u.id = uv.user_id 
    AND uv.kyc_status = 'approved'
    AND uv.verification_level = mm.verification_level
LEFT JOIN
    payment_methods pm 
    ON u.country_code = pm.country_code 
    AND pm.is_active = true
GROUP BY
    mm.acquisition_month,
    mm.country_code,
    mm.acquisition_channel,
    mm.verification_level,
    mm.total_users,
    mm.activated_users,
    mm.activation_rate,
    mm.avg_days_to_activation
ORDER BY
    mm.acquisition_month,
    mm.activation_rate DESC;