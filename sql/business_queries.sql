-- ================================================================
-- BANK CHURN INTELLIGENCE — Business SQL Queries
-- Database: churn_db | Table: bank_customers
-- ================================================================

USE churn_db;

-- ----------------------------------------------------------------
-- Q1: What is the overall scale of the churn problem?
-- ----------------------------------------------------------------
SELECT 
    COUNT(*) AS total_customers,
    SUM(Exited) AS total_churned,
    ROUND(100.0 * SUM(Exited) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(SUM(CASE WHEN Exited = 1 THEN Balance ELSE 0 END), 0) 
        AS total_balance_lost,
    ROUND(AVG(CASE WHEN Exited = 1 THEN Balance END), 0) 
        AS avg_balance_per_churner
FROM bank_customers;


-- ----------------------------------------------------------------
-- Q2: Which geography has the worst churn problem?
-- ----------------------------------------------------------------
SELECT
    Geography,
    COUNT(*) AS total_customers,
    SUM(Exited) AS churned,
    ROUND(100.0 * SUM(Exited) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(SUM(CASE WHEN Exited = 1 THEN Balance ELSE 0 END), 0) 
        AS balance_lost
FROM bank_customers
GROUP BY Geography
ORDER BY churn_rate_pct DESC;


-- ----------------------------------------------------------------
-- Q3: Complaint impact — did every complainer really leave?
-- ----------------------------------------------------------------
SELECT
    Complain,
    COUNT(*) AS total_customers,
    SUM(Exited) AS churned,
    ROUND(100.0 * SUM(Exited) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(Balance), 0) AS avg_balance
FROM bank_customers
GROUP BY Complain
ORDER BY Complain DESC;


-- ----------------------------------------------------------------
-- Q4: Build a risk tier for every customer using CASE WHEN
-- How does churn rate vary by risk tier?
-- ----------------------------------------------------------------
WITH risk_scored AS (
    SELECT *,
        CASE
            WHEN Complain = 1 THEN 'Critical'
            WHEN IsActiveMember = 0 
                AND CreditScore < 500 THEN 'High'
            WHEN IsActiveMember = 0 
                AND CreditScore BETWEEN 500 AND 650 THEN 'Medium-High'
            WHEN IsActiveMember = 1 
                AND CreditScore < 600 THEN 'Medium'
            ELSE 'Low'
        END AS risk_tier
    FROM bank_customers
)
SELECT
    risk_tier,
    COUNT(*) AS total_customers,
    SUM(Exited) AS churned,
    ROUND(100.0 * SUM(Exited) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(Balance), 0) AS avg_balance,
    ROUND(SUM(CASE WHEN Exited = 1 
        THEN Balance ELSE 0 END), 0) AS balance_lost,
    RANK() OVER (ORDER BY 
        SUM(Exited) * 1.0 / COUNT(*) DESC) AS severity_rank
FROM risk_scored
GROUP BY risk_tier
ORDER BY churn_rate_pct DESC;


-- ----------------------------------------------------------------
-- Q5: WINDOW FUNCTION — Top 5 highest balance churned 
-- customers per geography (who did we lose the most money from?)
-- ----------------------------------------------------------------
SELECT *
FROM (
    SELECT
        CustomerId,
        Geography,
        Age,
        Balance,
        CreditScore,
        `Card Type`,
        `Satisfactory Score`,
        RANK() OVER (
            PARTITION BY Geography 
            ORDER BY Balance DESC
        ) AS rank_in_region
    FROM bank_customers
    WHERE Exited = 1
) ranked
WHERE rank_in_region <= 5
ORDER BY Geography, rank_in_region;


-- ----------------------------------------------------------------
-- Q6: Churn rate by number of products — the product paradox
-- ----------------------------------------------------------------
SELECT
    NumOfProducts,
    COUNT(*) AS total_customers,
    SUM(Exited) AS churned,
    ROUND(100.0 * SUM(Exited) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(Balance), 0) AS avg_balance,
    ROUND(SUM(CASE WHEN Exited = 1 
        THEN Balance ELSE 0 END), 0) AS balance_lost
FROM bank_customers
GROUP BY NumOfProducts
ORDER BY NumOfProducts;


-- ----------------------------------------------------------------
-- Q7: LAG — Churn rate by tenure band
-- When in the customer lifecycle does churn peak?
-- ----------------------------------------------------------------
SELECT
    tenure_band,
    total_customers,
    churned,
    churn_rate_pct,
    LAG(churn_rate_pct) OVER (
        ORDER BY min_tenure
    ) AS prev_band_churn_rate,
    ROUND(churn_rate_pct - LAG(churn_rate_pct) OVER (
        ORDER BY min_tenure
    ), 2) AS change_from_prev_band
FROM (
    SELECT
        CASE
            WHEN Tenure BETWEEN 0 AND 2 THEN '0-2 years'
            WHEN Tenure BETWEEN 3 AND 5 THEN '3-5 years'
            WHEN Tenure BETWEEN 6 AND 8 THEN '6-8 years'
            ELSE '9-10 years'
        END AS tenure_band,
        MIN(Tenure) AS min_tenure,
        COUNT(*) AS total_customers,
        SUM(Exited) AS churned,
        ROUND(100.0 * SUM(Exited) / COUNT(*), 2) AS churn_rate_pct
    FROM bank_customers
    GROUP BY tenure_band
) tenure_summary
ORDER BY min_tenure;


-- ----------------------------------------------------------------
-- Q8: THE SAVE LIST — customers to call before they leave
-- Active customers who match the exact churn profile
-- but have NOT complained yet — intervention window is NOW
-- ----------------------------------------------------------------
SELECT
    CustomerId,
    Age,
    Geography,
    `Card Type`,
    Balance,
    CreditScore,
    Tenure,
    `Satisfactory Score`,
    NumOfProducts,
    -- Risk score: 1 point per risk factor
    (CASE WHEN CreditScore < 600 THEN 1 ELSE 0 END +
     CASE WHEN `Satisfactory Score` <= 2 THEN 1 ELSE 0 END +
     CASE WHEN NumOfProducts >= 3 THEN 1 ELSE 0 END +
     CASE WHEN Tenure < 3 THEN 1 ELSE 0 END +
     CASE WHEN Age BETWEEN 45 AND 60 THEN 1 ELSE 0 END
    ) AS risk_score
FROM bank_customers
WHERE Exited = 0
    AND IsActiveMember = 0
    AND Balance > 50000
    AND Complain = 0
HAVING risk_score >= 2
ORDER BY Balance DESC, risk_score DESC
LIMIT 50;