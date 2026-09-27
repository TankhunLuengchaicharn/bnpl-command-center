-- ============================================================================
-- BNPL COMMAND CENTER — DATABASE SCHEMA
-- ============================================================================
-- Written in standard PostgreSQL syntax.
-- This schema turns the FRD's "Data Requirements (Preview)" section (FRD §8)
-- into real tables. Every table below maps to one bullet point in that
-- section, plus two extra tables (bank_profile, rule_config) that exist
-- because of FR-11 ("Configurable Bank Profile") and the FRD's
-- Non-Functional Requirement "Configurability" (all thresholds must be
-- adjustable without a code change).
--
-- Design choices explained (for later self-study):
--   1. Every table has a surrogate integer primary key (..._id, SERIAL /
--      GENERATED ALWAYS AS IDENTITY). This is the most common real-world
--      pattern — natural keys (like a national ID) can change or be
--      reused, surrogate keys never do.
--   2. Foreign keys always reference the parent's primary key and use
--      ON DELETE RESTRICT by default (you cannot delete a customer who
--      still has transactions) — this protects data integrity, which is
--      exactly the kind of thing a BA/DA is expected to think about when
--      handing a data model to an engineering team.
--   3. CHECK constraints encode business rules directly in the database
--      (e.g. dsr_pct must be between 0 and 100). This is a second line of
--      defense — even if application code has a bug, the database won't
--      accept nonsense data.
--   4. Money columns use NUMERIC(12,2), never FLOAT/REAL. Floating point
--      types round money incorrectly; NUMERIC is exact. This is a very
--      common interview question for BA/DA and data engineering roles.
-- ============================================================================

DROP TABLE IF EXISTS auto_pay_run CASCADE;
DROP TABLE IF EXISTS subscription CASCADE;
DROP TABLE IF EXISTS consolidation_offer CASCADE;
DROP TABLE IF EXISTS credit_screening_result CASCADE;
DROP TABLE IF EXISTS late_payment_signal CASCADE;
DROP TABLE IF EXISTS detected_obligation CASCADE;
DROP TABLE IF EXISTS transaction CASCADE;
DROP TABLE IF EXISTS bnpl_provider CASCADE;
DROP TABLE IF EXISTS account CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS rule_config CASCADE;
DROP TABLE IF EXISTS b2b_license CASCADE;
DROP TABLE IF EXISTS bank_profile CASCADE;

-- ----------------------------------------------------------------------------
-- 1. BANK_PROFILE
-- Supports FR-11 "works for any bank, not just KBank" — the whole system is
-- designed to be sold/licensed to any bank, so bank identity is data, not
-- something hard-coded into the application.
-- ----------------------------------------------------------------------------
CREATE TABLE bank_profile (
    bank_id         SERIAL PRIMARY KEY,
    bank_name       VARCHAR(100) NOT NULL,
    country         VARCHAR(50)  NOT NULL DEFAULT 'Thailand',
    bank_size_tier  VARCHAR(10)  NOT NULL CHECK (bank_size_tier IN ('Small','Medium','Large')),
    onboarded_date  DATE         NOT NULL DEFAULT CURRENT_DATE
);

COMMENT ON TABLE bank_profile IS 'One row per client bank. Everything else in the schema is scoped (directly or indirectly) to a bank_id, so the same database can serve multiple banks. bank_size_tier drives the B2B licensing price tier in b2b_license (Business Model Decision #4).';

-- ----------------------------------------------------------------------------
-- 2. B2B_LICENSE
-- The ONLY revenue line in the product, per the locked business-model pivot
-- (2026-09-16): the consumer app (Dashboard + Auto-Pay) is 100% free with
-- zero exceptions — B2B licensing to partner banks is where all revenue
-- comes from. Structure: one-time setup/integration fee + a recurring
-- monthly license fee, both tiered by the licensing bank's size
-- (bank_profile.bank_size_tier). tier_at_signing is snapshotted rather than
-- read live from bank_profile, because a bank's size can change after
-- signing but the contracted price should not silently move with it.
-- ----------------------------------------------------------------------------
CREATE TABLE b2b_license (
    license_id               SERIAL PRIMARY KEY,
    bank_id                   INTEGER NOT NULL REFERENCES bank_profile(bank_id),
    tier_at_signing           VARCHAR(10) NOT NULL CHECK (tier_at_signing IN ('Small','Medium','Large')),
    setup_fee_baht            NUMERIC(14,2) NOT NULL CHECK (setup_fee_baht >= 0),   -- one-time, billed at signing — NOT part of MRR
    monthly_license_fee_baht  NUMERIC(12,2) NOT NULL CHECK (monthly_license_fee_baht >= 0),  -- recurring — this IS MRR
    contract_start_date       DATE NOT NULL,
    contract_end_date         DATE,
    status                    VARCHAR(10) NOT NULL DEFAULT 'Active' CHECK (status IN ('Active','Cancelled'))
);

COMMENT ON TABLE b2b_license IS 'One row per bank licensing contract. setup_fee_baht is one-time revenue (billed once, at signing); monthly_license_fee_baht is the recurring revenue that feeds MRR (Q12). Pricing assumptions here are illustrative placeholders for the portfolio project — the Excel revenue model (not yet built) is the source of truth once finalized, and these should be reconciled against it.';

-- ----------------------------------------------------------------------------
-- 3. RULE_CONFIG
-- Supports FRD NFR "Configurability" — Business Rules R-01 to R-06 use
-- configurable numbers (days late, credit score minimum, DSR max). Instead
-- of hard-coding those numbers in application code, they live here so
-- Risk & Compliance staff can change them without a software release.
-- ----------------------------------------------------------------------------
CREATE TABLE rule_config (
    config_key      VARCHAR(50) PRIMARY KEY,
    config_value    NUMERIC(10,2) NOT NULL,
    description     VARCHAR(255) NOT NULL,
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE rule_config IS 'Key/value store for the configurable thresholds referenced in FRD Business Rules R-02, R-03, R-04.';

-- ----------------------------------------------------------------------------
-- 4. CUSTOMER
-- ----------------------------------------------------------------------------
CREATE TABLE customer (
    customer_id             SERIAL PRIMARY KEY,
    bank_id                 INTEGER NOT NULL REFERENCES bank_profile(bank_id),
    full_name               VARCHAR(100) NOT NULL,
    date_of_birth           DATE NOT NULL,
    monthly_income_declared NUMERIC(12,2) CHECK (monthly_income_declared >= 0),
    account_open_date       DATE NOT NULL,
    consent_given           BOOLEAN NOT NULL DEFAULT FALSE,
    consent_date            DATE,
    CONSTRAINT chk_consent_date CHECK (consent_given = FALSE OR consent_date IS NOT NULL)
);

COMMENT ON TABLE customer IS 'Basic profile. consent_given/consent_date enforce the PDPA non-functional requirement: the system must never read transactions without recorded consent.';

-- ----------------------------------------------------------------------------
-- 5. ACCOUNT
-- A customer can link more than one bank account (checking + savings).
-- ----------------------------------------------------------------------------
CREATE TABLE account (
    account_id           SERIAL PRIMARY KEY,
    customer_id          INTEGER NOT NULL REFERENCES customer(customer_id),
    account_number_masked VARCHAR(20) NOT NULL,   -- e.g. 'xxxx-xxxx-4821'
    account_type         VARCHAR(20) NOT NULL CHECK (account_type IN ('Checking','Savings')),
    is_linked_for_scan   BOOLEAN NOT NULL DEFAULT TRUE,
    linked_date          DATE NOT NULL
);

-- ----------------------------------------------------------------------------
-- 6. BNPL_PROVIDER
-- The maintained list referenced in FRD Edge Case "provider not on the
-- maintained name list" and FR-01 (Transaction Scanning Engine).
-- ----------------------------------------------------------------------------
CREATE TABLE bnpl_provider (
    provider_id             SERIAL PRIMARY KEY,
    provider_name           VARCHAR(50) NOT NULL UNIQUE,
    matching_pattern        VARCHAR(100) NOT NULL,   -- text pattern used to match transaction descriptions
    typical_late_rate_pct   NUMERIC(5,2),             -- annualised penalty interest rate once payment is late
    reports_to_credit_bureau BOOLEAN NOT NULL DEFAULT FALSE
);

-- ----------------------------------------------------------------------------
-- 7. TRANSACTION
-- Raw bank transaction data — this is the input the whole system runs on.
-- ----------------------------------------------------------------------------
CREATE TABLE transaction (
    transaction_id      SERIAL PRIMARY KEY,
    account_id           INTEGER NOT NULL REFERENCES account(account_id),
    transaction_date     DATE NOT NULL,
    amount                NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    description_raw       VARCHAR(200) NOT NULL,       -- raw text as it appears on the statement
    direction             VARCHAR(6) NOT NULL CHECK (direction IN ('DEBIT','CREDIT'))
);

CREATE INDEX idx_transaction_account_date ON transaction(account_id, transaction_date);

-- ----------------------------------------------------------------------------
-- 8. DETECTED_OBLIGATION
-- FR-01 output: a transaction that has been matched to a known BNPL provider.
-- ----------------------------------------------------------------------------
CREATE TABLE detected_obligation (
    obligation_id     SERIAL PRIMARY KEY,
    customer_id       INTEGER NOT NULL REFERENCES customer(customer_id),
    provider_id       INTEGER NOT NULL REFERENCES bnpl_provider(provider_id),
    transaction_id    INTEGER REFERENCES transaction(transaction_id),
    due_date          DATE NOT NULL,
    expected_amount   NUMERIC(12,2) NOT NULL CHECK (expected_amount > 0),
    actual_paid_amount NUMERIC(12,2),
    actual_paid_date  DATE,
    cycle_number      INTEGER NOT NULL DEFAULT 1        -- which installment in the plan (1st, 2nd, ...)
);

CREATE INDEX idx_obligation_customer_due ON detected_obligation(customer_id, due_date);

COMMENT ON TABLE detected_obligation IS 'One row per expected BNPL payment cycle. FRD Business Rule R-03 (Stacking Status) counts DISTINCT provider_id in this table within a trailing 90-day window.';

-- ----------------------------------------------------------------------------
-- 9. LATE_PAYMENT_SIGNAL
-- FR-05 output, produced by Business Rule R-02.
-- ----------------------------------------------------------------------------
CREATE TABLE late_payment_signal (
    signal_id       SERIAL PRIMARY KEY,
    obligation_id   INTEGER NOT NULL REFERENCES detected_obligation(obligation_id),
    customer_id     INTEGER NOT NULL REFERENCES customer(customer_id),
    provider_id     INTEGER NOT NULL REFERENCES bnpl_provider(provider_id),
    days_late       INTEGER NOT NULL CHECK (days_late >= 0),
    signal_date     DATE NOT NULL,
    signal_reason   VARCHAR(20) NOT NULL CHECK (signal_reason IN ('LATE_PAYMENT','AMOUNT_SPIKE'))
);

-- ----------------------------------------------------------------------------
-- 10. CREDIT_SCREENING_RESULT
-- FR-06 output, produced by Business Rules R-04 / R-05.
-- ----------------------------------------------------------------------------
CREATE TABLE credit_screening_result (
    screening_id           SERIAL PRIMARY KEY,
    customer_id            INTEGER NOT NULL REFERENCES customer(customer_id),
    screening_date         DATE NOT NULL,
    credit_score           INTEGER CHECK (credit_score BETWEEN 300 AND 900),
    dsr_pct                NUMERIC(5,2) CHECK (dsr_pct BETWEEN 0 AND 200),
    income_stability_flag  BOOLEAN NOT NULL,   -- TRUE = 3+ consecutive months of regular salary deposits
    eligibility_outcome    VARCHAR(15) NOT NULL CHECK (eligibility_outcome IN ('Eligible','Not Eligible')),
    reason                 VARCHAR(200)
);

-- ----------------------------------------------------------------------------
-- 11. CONSOLIDATION_OFFER
-- FR-07 output. Only created when eligibility_outcome = 'Eligible'.
-- ----------------------------------------------------------------------------
CREATE TABLE consolidation_offer (
    offer_id            SERIAL PRIMARY KEY,
    customer_id         INTEGER NOT NULL REFERENCES customer(customer_id),
    screening_id        INTEGER NOT NULL REFERENCES credit_screening_result(screening_id),
    offer_date          DATE NOT NULL,
    total_amount         NUMERIC(12,2) NOT NULL CHECK (total_amount > 0),
    offered_rate_pct     NUMERIC(5,2) NOT NULL,
    monthly_payment      NUMERIC(12,2) NOT NULL,
    status                VARCHAR(15) NOT NULL DEFAULT 'Offered'
                            CHECK (status IN ('Offered','Accepted','Declined','Expired'))
);

-- ----------------------------------------------------------------------------
-- 12. SUBSCRIPTION
-- FR-08 output. NOTE: per the locked business-model pivot (2026-09-16),
-- BOTH plan types are free — Dashboard and Auto-Pay carry no consumer fee
-- anywhere in the app (Business Rule R-06). plan_type is therefore a
-- FEATURE-ENGAGEMENT flag only ("has this customer turned Auto-Pay on"),
-- never a billing tier — there is deliberately no fee/price column here.
-- All product revenue comes from b2b_license instead.
-- ----------------------------------------------------------------------------
CREATE TABLE subscription (
    subscription_id  SERIAL PRIMARY KEY,
    customer_id       INTEGER NOT NULL REFERENCES customer(customer_id),
    plan_type          VARCHAR(15) NOT NULL CHECK (plan_type IN ('Free','AutoPay')),
    start_date         DATE NOT NULL,
    end_date           DATE,
    status              VARCHAR(10) NOT NULL DEFAULT 'Active' CHECK (status IN ('Active','Cancelled'))
);

-- ----------------------------------------------------------------------------
-- 13. AUTO_PAY_RUN
-- One row per monthly auto-pay attempt — needed to model the FRD Edge Case
-- "Auto-Pay deduction fails (insufficient funds)".
-- ----------------------------------------------------------------------------
CREATE TABLE auto_pay_run (
    run_id             SERIAL PRIMARY KEY,
    subscription_id    INTEGER NOT NULL REFERENCES subscription(subscription_id),
    run_date            DATE NOT NULL,
    total_deducted       NUMERIC(12,2) NOT NULL,
    run_status            VARCHAR(10) NOT NULL CHECK (run_status IN ('Success','Failed')),
    failure_reason        VARCHAR(100)
);

-- ============================================================================
-- End of schema.
-- ============================================================================
