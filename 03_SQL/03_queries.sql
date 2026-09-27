-- ============================================================================
-- BNPL COMMAND CENTER — PRACTICE QUERIES
-- ============================================================================
-- Every query below is written the way a Business Analyst / Data Analyst
-- would actually write it on the job, and every one has been run against
-- the schema + sample data in this folder to confirm it works.
--
-- HOW TO USE THIS FILE TO PRACTICE:
--   1. Cover the SQL, read only the "Business question" comment, and try
--      writing the query yourself before looking at the answer.
--   2. Run it and compare your result to what's described.
--   3. Once these feel easy, try changing the sample data (add a new
--      customer, a new late payment) and predict how each query's result
--      changes before re-running it.
--
-- The queries are grouped by SQL technique, roughly in order of how often
-- each technique shows up in real BA/DA interviews and daily work.
-- ============================================================================


-- ============================================================================
-- SECTION 1 — BASIC FILTERING, SORTING, JOINS
-- ============================================================================

-- Q1. Business question: "Show me every BNPL payment for customer Somchai
-- (101), with the provider name spelled out, most recent first."
-- Technique: INNER JOIN + ORDER BY
SELECT
    c.full_name,
    p.provider_name,
    o.due_date,
    o.expected_amount,
    o.actual_paid_amount
FROM detected_obligation o
JOIN customer c      ON c.customer_id = o.customer_id
JOIN bnpl_provider p ON p.provider_id = o.provider_id
WHERE c.customer_id = 101
ORDER BY o.due_date DESC;


-- Q2. Business question: "Which customers paid MORE than the amount they
-- originally owed?" (a proxy for 'was charged a late fee')
-- Technique: WHERE with column-to-column comparison
SELECT
    c.full_name,
    p.provider_name,
    o.due_date,
    o.expected_amount,
    o.actual_paid_amount,
    o.actual_paid_amount - o.expected_amount AS extra_charged
FROM detected_obligation o
JOIN customer c      ON c.customer_id = o.customer_id
JOIN bnpl_provider p ON p.provider_id = o.provider_id
WHERE o.actual_paid_amount > o.expected_amount
ORDER BY extra_charged DESC;


-- ============================================================================
-- SECTION 2 — AGGREGATION: GROUP BY, HAVING
-- ============================================================================

-- Q3. Business question: "For each customer, what is their total BNPL
-- obligation across all providers and all cycles?"
-- Technique: GROUP BY + SUM
SELECT
    c.customer_id,
    c.full_name,
    SUM(o.expected_amount) AS total_expected,
    SUM(o.actual_paid_amount) AS total_actually_paid
FROM detected_obligation o
JOIN customer c ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.full_name
ORDER BY total_expected DESC;


-- Q4. Business question: "Which customers use 2 or more DIFFERENT BNPL
-- providers at all (ever), and how many?" — a simple (non-time-windowed)
-- version of stacking, good for a first pass before the real Business Rule
-- R-03 logic in Q7.
-- Technique: GROUP BY + HAVING (HAVING filters on an aggregate — WHERE cannot)
SELECT
    c.customer_id,
    c.full_name,
    COUNT(DISTINCT o.provider_id) AS distinct_providers_used
FROM detected_obligation o
JOIN customer c ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.full_name
HAVING COUNT(DISTINCT o.provider_id) >= 2
ORDER BY distinct_providers_used DESC, c.customer_id;


-- ============================================================================
-- SECTION 3 — WINDOW FUNCTIONS
-- ============================================================================
-- Window functions calculate something ACROSS a set of rows related to the
-- current row, without collapsing them into one row (unlike GROUP BY).
-- They are one of the most tested SQL skills in real BA/DA interviews.

-- Q5. Business question: "Rank customers by total amount owed, so we can
-- see our top-10 highest-exposure customers."
-- Technique: RANK() OVER (ORDER BY ...)
SELECT
    c.customer_id,
    c.full_name,
    SUM(o.expected_amount) AS total_exposure,
    RANK() OVER (ORDER BY SUM(o.expected_amount) DESC) AS exposure_rank
FROM detected_obligation o
JOIN customer c ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.full_name
ORDER BY exposure_rank
LIMIT 10;


-- Q6. Business question: "For each customer's SPayLater payments, show the
-- amount THIS cycle next to the amount LAST cycle, so we can spot sudden
-- jumps (a signal of a late fee being added)."
-- Technique: LAG() OVER (PARTITION BY ... ORDER BY ...)
SELECT
    c.full_name,
    o.due_date,
    o.actual_paid_amount AS this_cycle_amount,
    LAG(o.actual_paid_amount) OVER (
        PARTITION BY o.customer_id, o.provider_id
        ORDER BY o.due_date
    ) AS previous_cycle_amount,
    o.actual_paid_amount
        - LAG(o.actual_paid_amount) OVER (
              PARTITION BY o.customer_id, o.provider_id
              ORDER BY o.due_date
          ) AS change_vs_last_cycle
FROM detected_obligation o
JOIN customer c      ON c.customer_id = o.customer_id
JOIN bnpl_provider p ON p.provider_id = o.provider_id
WHERE p.provider_name = 'Shopee SPayLater'
ORDER BY c.full_name, o.due_date;


-- Q7. *** THE CORE QUERY OF THIS WHOLE PROJECT ***
-- Business question: this is FRD Business Rule R-03 written as SQL:
-- "Flag a customer as STACKED if they have obligations with 2+ distinct
-- BNPL providers in the trailing 90 days as of a given obligation's due
-- date."
-- Technique: correlated subquery (a subquery that references the outer
-- query's current row — here, o.customer_id and o.due_date). This pattern
-- is extremely common any time a business rule involves "in the trailing
-- N days" — window functions can't easily do COUNT(DISTINCT ...) with a
-- time-based frame in standard SQL, so a correlated subquery is the
-- practical, readable answer real BAs/DAs reach for.
SELECT
    o.customer_id,
    c.full_name,
    o.obligation_id,
    o.due_date,
    (
        SELECT COUNT(DISTINCT o2.provider_id)
        FROM detected_obligation o2
        WHERE o2.customer_id = o.customer_id
          AND o2.due_date BETWEEN o.due_date - INTERVAL '90 days' AND o.due_date
    ) AS distinct_providers_trailing_90d
FROM detected_obligation o
JOIN customer c ON c.customer_id = o.customer_id
ORDER BY o.customer_id, o.due_date;


-- ============================================================================
-- SECTION 4 — CTEs (WITH clauses) AND THE FULL DECISION-LOGIC QUERY
-- ============================================================================
-- A CTE (Common Table Expression) lets you build a query in named, readable
-- steps instead of one giant nested query. Real BA/DA SQL almost always
-- looks like this once the logic gets past 2-3 steps.

-- Q8. *** THE FLAGSHIP QUERY — turns FRD Business Rules R-01 through R-05
-- into one runnable query. This single query IS the specification for what
-- the application must compute. ***
-- Business question: "As of today, which customers are Consolidation
-- Candidates (Stacked + Late Payment Signal), and what happened to them —
-- Eligible with an offer, or Not Eligible and referred?"
WITH stacking_check AS (
    -- Step 1: for every obligation, count distinct providers in the
    -- trailing 90 days (same logic as Q7)
    SELECT
        o.customer_id,
        o.obligation_id,
        o.due_date,
        (
            SELECT COUNT(DISTINCT o2.provider_id)
            FROM detected_obligation o2
            WHERE o2.customer_id = o.customer_id
              AND o2.due_date BETWEEN o.due_date - INTERVAL '90 days' AND o.due_date
        ) AS distinct_providers_90d
    FROM detected_obligation o
),
customer_stacking_status AS (
    -- Step 2: a customer is "Stacked" if ANY of their obligations hit 2+
    -- distinct providers in the trailing 90 days
    SELECT
        customer_id,
        MAX(distinct_providers_90d) AS max_distinct_providers_90d,
        (MAX(distinct_providers_90d) >= 2) AS is_stacked
    FROM stacking_check
    GROUP BY customer_id
),
has_late_signal AS (
    -- Step 3: does this customer have ANY late payment signal at all?
    SELECT DISTINCT customer_id
    FROM late_payment_signal
),
consolidation_candidates AS (
    -- Step 4: Business Rule R-03 — Stacked AND has a late signal
    SELECT
        s.customer_id,
        s.is_stacked,
        (h.customer_id IS NOT NULL) AS has_late_signal
    FROM customer_stacking_status s
    LEFT JOIN has_late_signal h ON h.customer_id = s.customer_id
    WHERE s.is_stacked = TRUE
      AND h.customer_id IS NOT NULL
)
-- Step 5: bring in the screening outcome and offer status (R-04 / R-05)
SELECT
    c.customer_id,
    cu.full_name,
    'Stacked' AS stacking_status,
    'Consolidation Candidate' AS candidate_status,
    COALESCE(cr.eligibility_outcome, 'Not Yet Screened') AS screening_outcome,
    cr.credit_score,
    cr.dsr_pct,
    COALESCE(co.status, CASE WHEN cr.eligibility_outcome = 'Not Eligible'
                              THEN 'Referred to BOT debt-relief program'
                              ELSE 'No offer generated' END) AS outcome
FROM consolidation_candidates c
JOIN customer cu ON cu.customer_id = c.customer_id
LEFT JOIN credit_screening_result cr ON cr.customer_id = c.customer_id
LEFT JOIN consolidation_offer co     ON co.customer_id = c.customer_id
ORDER BY c.customer_id;


-- ============================================================================
-- SECTION 5 — CASE WHEN (bucketing / segmentation)
-- ============================================================================

-- Q9. Business question: "Segment every customer into one of four groups
-- for a marketing/risk report: Not a BNPL user / Single provider / Stacked
-- - healthy / Stacked - at risk."
-- Technique: CASE WHEN with subqueries in the SELECT list
SELECT
    c.customer_id,
    c.full_name,
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM detected_obligation o WHERE o.customer_id = c.customer_id)
            THEN 'Not a BNPL user'
        WHEN (SELECT COUNT(DISTINCT o.provider_id) FROM detected_obligation o WHERE o.customer_id = c.customer_id) = 1
            THEN 'Single provider'
        WHEN EXISTS (SELECT 1 FROM late_payment_signal l WHERE l.customer_id = c.customer_id)
            THEN 'Stacked - at risk'
        ELSE 'Stacked - healthy'
    END AS customer_segment
FROM customer c
ORDER BY customer_segment, c.customer_id;


-- ============================================================================
-- SECTION 6 — DATE FUNCTIONS / MONTHLY REPORTING
-- ============================================================================

-- Q10. Business question: "What is our total BNPL obligation volume by
-- month, across all customers?" — a typical monthly trend chart's source
-- query, and exactly the kind of query that later feeds a Power BI /
-- Tableau line chart.
-- Technique: DATE_TRUNC
SELECT
    DATE_TRUNC('month', due_date)::DATE AS obligation_month,
    COUNT(*) AS obligation_count,
    SUM(expected_amount) AS total_expected,
    SUM(actual_paid_amount) AS total_actually_paid
FROM detected_obligation
GROUP BY DATE_TRUNC('month', due_date)
ORDER BY obligation_month;


-- ============================================================================
-- SECTION 7 — FUNNEL / CONVERSION ANALYSIS
-- ============================================================================

-- Q11. Business question: "Give me the full conversion funnel: of all
-- customers, how many are Stacked, how many of those have a Late Payment
-- Signal, how many passed screening, and how many accepted an offer? I
-- need counts AND percentages for a board slide."
-- Technique: multiple CTEs + UNION ALL to stack funnel stages into rows
-- (a very common report shape: "funnel query")
WITH total_customers AS (
    SELECT COUNT(*) AS n FROM customer
),
stacked AS (
    SELECT COUNT(DISTINCT customer_id) AS n
    FROM (
        SELECT o.customer_id,
               (SELECT COUNT(DISTINCT o2.provider_id)
                FROM detected_obligation o2
                WHERE o2.customer_id = o.customer_id
                  AND o2.due_date BETWEEN o.due_date - INTERVAL '90 days' AND o.due_date) AS cnt
        FROM detected_obligation o
    ) x
    WHERE cnt >= 2
),
late_and_stacked AS (
    SELECT COUNT(DISTINCT l.customer_id) AS n
    FROM late_payment_signal l
    WHERE l.customer_id IN (
        SELECT o.customer_id
        FROM detected_obligation o
        GROUP BY o.customer_id
        HAVING COUNT(DISTINCT o.provider_id) >= 2
    )
),
screened_eligible AS (
    SELECT COUNT(*) AS n FROM credit_screening_result WHERE eligibility_outcome = 'Eligible'
),
offer_accepted AS (
    SELECT COUNT(*) AS n FROM consolidation_offer WHERE status = 'Accepted'
)
SELECT 'Stage 1: Total Customers'          AS funnel_stage, n, ROUND(100.0 * n / (SELECT n FROM total_customers), 1) AS pct_of_total FROM total_customers
UNION ALL
SELECT 'Stage 2: Stacked (2+ providers)',     n, ROUND(100.0 * n / (SELECT n FROM total_customers), 1) FROM stacked
UNION ALL
SELECT 'Stage 3: Stacked + Late Signal',      n, ROUND(100.0 * n / (SELECT n FROM total_customers), 1) FROM late_and_stacked
UNION ALL
SELECT 'Stage 4: Passed Credit Screening',    n, ROUND(100.0 * n / (SELECT n FROM total_customers), 1) FROM screened_eligible
UNION ALL
SELECT 'Stage 5: Accepted Consolidation Offer', n, ROUND(100.0 * n / (SELECT n FROM total_customers), 1) FROM offer_accepted;


-- ============================================================================
-- SECTION 8 — REVENUE / MRR CALCULATION
-- ============================================================================

-- Q12. Business question: "What is our current Monthly Recurring Revenue
-- (MRR) from B2B bank licensing, plus estimated monthly interest revenue
-- from accepted consolidation offers?"
-- NOTE (business-model pivot, locked 2026-09-16): the consumer app is
-- 100% free with zero exceptions — there is no consumer subscription fee
-- anywhere in the product. B2B licensing to partner banks (b2b_license) is
-- the only recurring revenue line; consolidation-loan interest is a
-- second, separate revenue line (a lending product, not a subscription
-- fee, so it was NOT affected by the pivot that closed the consumer tier).
-- Technique: two aggregates combined with UNION ALL, plus a grand total
-- using ROLLUP-style manual total row (simple, portfolio-readable version).
-- Also demonstrates a real MRR convention: the one-time setup fee is
-- reported separately and deliberately excluded from the MRR figure.
WITH b2b_mrr AS (
    SELECT SUM(monthly_license_fee_baht) AS amount
    FROM b2b_license
    WHERE status = 'Active'
),
b2b_setup_fees_billed AS (
    -- one-time revenue, NOT recurring — shown for context, excluded from MRR
    SELECT SUM(setup_fee_baht) AS amount
    FROM b2b_license
),
consolidation_monthly_revenue AS (
    -- simplified estimate: (rate% / 12) * outstanding principal, for
    -- accepted offers only
    SELECT SUM(total_amount * (offered_rate_pct / 100.0) / 12) AS amount
    FROM consolidation_offer
    WHERE status = 'Accepted'
)
SELECT 'B2B licensing MRR (recurring)' AS revenue_line, ROUND(amount, 2) AS monthly_baht FROM b2b_mrr
UNION ALL
SELECT 'Consolidation loan interest (monthly, est.)', ROUND(amount, 2) FROM consolidation_monthly_revenue
UNION ALL
SELECT 'TOTAL MRR', ROUND((SELECT amount FROM b2b_mrr) + (SELECT amount FROM consolidation_monthly_revenue), 2)
UNION ALL
SELECT 'B2B setup fees billed to date (one-time, memo only — not MRR)', ROUND(amount, 2) FROM b2b_setup_fees_billed;


-- ============================================================================
-- SECTION 9 — DATA QUALITY CHECKS
-- ============================================================================
-- A large part of real DA work is NOT reporting — it's checking that the
-- data can be trusted before anyone reports on it. These are the kinds of
-- checks that should run automatically every day in a real pipeline.

-- Q13. Check: any obligation where the paid date is BEFORE the transaction
-- even happened, or a negative/zero amount slipped through (should be
-- impossible given the CHECK constraints, but this is the kind of query
-- you write to double check constraints are actually doing their job).
SELECT *
FROM detected_obligation
WHERE expected_amount <= 0
   OR actual_paid_amount <= 0;
-- Expected result: 0 rows. If this ever returns rows, the CHECK constraints
-- were bypassed (e.g. a bulk load that skipped validation) and someone
-- needs to be told immediately.

-- Q14. Check: orphan transactions — a transaction whose account_id doesn't
-- exist in the account table. With a proper FOREIGN KEY this is also
-- impossible, but this is the standard "trust but verify" query DAs run
-- against a data warehouse copy that might not have the same constraints
-- as the source system.
SELECT t.*
FROM transaction t
LEFT JOIN account a ON a.account_id = t.account_id
WHERE a.account_id IS NULL;
-- Expected result: 0 rows.

-- Q15. Check: customers with a Late Payment Signal but NO matching
-- detected_obligation row (a referential integrity check across two
-- "downstream" tables, which foreign keys alone don't fully protect
-- against logic bugs — e.g. wrong customer_id copied into the signal row).
SELECT l.*
FROM late_payment_signal l
LEFT JOIN detected_obligation o
       ON o.obligation_id = l.obligation_id
      AND o.customer_id   = l.customer_id
WHERE o.obligation_id IS NULL;
-- Expected result: 0 rows.


-- ============================================================================
-- SECTION 10 — EXISTS / NOT EXISTS (a very common interview pattern)
-- ============================================================================

-- Q16. Business question: "Which customers have NEVER had a late payment
-- signal, even though they use BNPL?" — i.e. our "good" BNPL customers,
-- who should get free tracking + auto-pay marketing, never a loan pitch
-- (Business Rule R-06).
SELECT c.customer_id, c.full_name
FROM customer c
WHERE EXISTS (SELECT 1 FROM detected_obligation o WHERE o.customer_id = c.customer_id)
  AND NOT EXISTS (SELECT 1 FROM late_payment_signal l WHERE l.customer_id = c.customer_id)
ORDER BY c.customer_id;

-- ============================================================================
-- End of practice queries.
-- ============================================================================
