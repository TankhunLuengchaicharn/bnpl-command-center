-- ============================================================================
-- BNPL COMMAND CENTER — SAMPLE DATA
-- ============================================================================
-- Realistic-looking (but fictional) data for one bank, 20 customers, 5 BNPL
-- providers, and roughly 6 months of transaction history. This is enough
-- data for every query in 03_queries.sql to return a meaningful, checkable
-- result — a real project would obviously have millions of rows, but the
-- point here is to practice writing correct SQL against a known, small
-- dataset where you can verify the answer by eye.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Bank + rule configuration
-- ----------------------------------------------------------------------------
-- Only KBank (bank_id 1) has actual customers/transactions loaded below —
-- it's the narrative anchor bank (KBank bought 50%+ of Atome Thailand,
-- April 2026). The other 4 banks exist purely to make the B2B licensing
-- revenue model (b2b_license, below) realistic across both tiers — a real
-- licensing pipeline covers banks we haven't onboarded customer data for
-- yet, so it's correct for them to have no customer/transaction rows in
-- this sample dataset.
-- Tier and bank names here MUST match 04_Excel Revenue_Model exactly:
-- Tier 1 = "Big 6 by assets" (KBank, SCB, BBL, KTB, Krungsri, TTB);
-- Tier 2 = mid-size domestic (TISCO, Kiatnakin Phatra, CIMB Thai, LH Bank,
-- UOB Thai, Standard Chartered Thai, ICBC Thai). Using 3 of the 6 Tier 1
-- banks and 2 of the 7 Tier 2 banks here is enough sample variety without
-- needing all 13 loaded.
INSERT INTO bank_profile (bank_id, bank_name, country, licensing_tier, onboarded_date) VALUES
  (1, 'Kasikornbank (KBank)',              'Thailand', 'Tier 1', '2026-01-15'),
  (2, 'Siam Commercial Bank (SCB)',        'Thailand', 'Tier 1', '2026-04-01'),
  (3, 'TMBThanachart Bank (ttb)',          'Thailand', 'Tier 1', '2026-06-15'),
  (4, 'Land and Houses Bank (LH Bank)',    'Thailand', 'Tier 2', '2026-08-01'),
  (5, 'Kiatnakin Phatra Bank (KKP)',       'Thailand', 'Tier 2', '2026-05-01');

-- ----------------------------------------------------------------------------
-- B2B licensing contracts — the ONLY revenue line in the product
-- (Business Model Decision #4/#5, locked 2026-09-16). Pricing is tiered by
-- licensing_tier: setup_fee_baht is one-time (billed once, at signing);
-- monthly_license_fee_baht is recurring and feeds MRR (Q12).
-- NOTE: these THB figures are NOT independently invented — they are copied
-- exactly from 04_Excel/BNPL_Command_Center_Analysis_Workbook.xlsx, sheet
-- Revenue_Model, cells E9-E12 (Tier 1 = THB 2,500,000 setup + THB 180,000/
-- month; Tier 2 = THB 900,000 setup + THB 70,000/month), so the SQL and
-- Excel deliverables agree on the same numbers.
-- KKP (bank_id 5) is deliberately CANCELLED here: its one-time setup fee
-- was already collected and stays in historical revenue, but its recurring
-- fee must drop out of current MRR — this is what makes the
-- `WHERE status = 'Active'` filter in Q12 actually matter, instead of
-- being a no-op over an all-Active sample.
-- ----------------------------------------------------------------------------
INSERT INTO b2b_license (bank_id, tier_at_signing, setup_fee_baht, monthly_license_fee_baht, contract_start_date, contract_end_date, status) VALUES
  (1, 'Tier 1', 2500000.00, 180000.00, '2026-01-15', NULL,         'Active'),
  (2, 'Tier 1', 2500000.00, 180000.00, '2026-04-01', NULL,         'Active'),
  (3, 'Tier 1', 2500000.00, 180000.00, '2026-06-15', NULL,         'Active'),
  (4, 'Tier 2', 900000.00,  70000.00,  '2026-08-01', NULL,         'Active'),
  (5, 'Tier 2', 900000.00,  70000.00,  '2026-05-01', '2026-08-15', 'Cancelled');

INSERT INTO rule_config (config_key, config_value, description) VALUES
  ('late_days_threshold',      3,   'Days past due before a Late Payment Signal is raised (FRD Business Rule R-02)'),
  ('stacking_provider_count',  2,   'Minimum distinct providers in trailing 90 days to count as Stacked (R-03)'),
  ('min_credit_score',         600, 'Minimum credit score to be Eligible for a consolidation offer (R-04)'),
  ('max_dsr_pct',              50,  'Maximum Debt-Service Ratio (%) to be Eligible for a consolidation offer (R-04)');

-- ----------------------------------------------------------------------------
-- BNPL providers (real, publicly known Thai BNPL products, used for realism)
-- ----------------------------------------------------------------------------
INSERT INTO bnpl_provider (provider_id, provider_name, matching_pattern, typical_late_rate_pct, reports_to_credit_bureau) VALUES
  (1, 'Shopee SPayLater',   '%SPAYLATER%',           25.00, TRUE),
  (2, 'Atome',              '%ATOME%',               20.00, FALSE),
  (3, 'LazPayLater',        '%LAZPAYLATER%',         18.00, FALSE),
  (4, 'TrueMoney Next',     '%TRUEMONEY NEXT%',      15.00, FALSE),
  (5, 'Grab PayLater',      '%GRAB PAYLATER%',       20.00, FALSE);

-- ----------------------------------------------------------------------------
-- Customers (20). Deliberately built to represent different segments:
--   101-104: heavy stackers, currently late  (Consolidation Candidates)
--   105-108: stacked, but always pay on time (no revenue opportunity, per
--            the business-model discussion — real BNPL users are NOT all
--            targets for a loan, only the ones with a live late-payment signal)
--   109-112: single-provider users (not stacked at all)
--   113-116: stacked + late, but will FAIL credit/DSR screening (must be
--            routed to referral, never offered a loan — R-05)
--   117-120: no BNPL usage at all (control group / normal banking customers)
-- ----------------------------------------------------------------------------
INSERT INTO customer (customer_id, bank_id, full_name, date_of_birth, monthly_income_declared, account_open_date, consent_given, consent_date) VALUES
  (101, 1, 'Somchai Jaidee',     '1994-03-12', 45000, '2023-06-01', TRUE, '2026-01-20'),
  (102, 1, 'Suda Panyawong',     '1991-07-22', 38000, '2022-11-15', TRUE, '2026-01-20'),
  (103, 1, 'Anan Chaiyaporn',    '1996-01-05', 32000, '2024-02-10', TRUE, '2026-01-21'),
  (104, 1, 'Nittaya Wongsawat',  '1989-09-30', 52000, '2021-05-20', TRUE, '2026-01-21'),
  (105, 1, 'Kittipong Srisuk',   '1993-12-18', 60000, '2020-08-01', TRUE, '2026-01-22'),
  (106, 1, 'Wanida Boonmee',     '1995-04-09', 41000, '2023-01-12', TRUE, '2026-01-22'),
  (107, 1, 'Prasert Rattanakul', '1988-06-14', 75000, '2019-03-05', TRUE, '2026-01-23'),
  (108, 1, 'Malee Thongdee',     '1997-02-28', 33000, '2024-07-01', TRUE, '2026-01-23'),
  (109, 1, 'Chatchai Kiatkamon', '1992-10-11', 29000, '2023-09-15', TRUE, '2026-01-24'),
  (110, 1, 'Pornthip Suksawat',  '1990-05-25', 47000, '2022-04-18', TRUE, '2026-01-24'),
  (111, 1, 'Wichai Amnuayporn',  '1994-08-08', 36000, '2023-11-02', TRUE, '2026-01-25'),
  (112, 1, 'Siriporn Nakornthap','1998-01-17', 27000, '2024-10-10', TRUE, '2026-01-25'),
  (113, 1, 'Boonsong Meechai',   '1991-11-03', 18000, '2023-03-22', TRUE, '2026-01-26'),
  (114, 1, 'Amporn Silpachai',   '1996-06-19', 21000, '2024-01-08', TRUE, '2026-01-26'),
  (115, 1, 'Somsak Pattaraporn', '1993-03-27', 19500, '2023-08-14', TRUE, '2026-01-27'),
  (116, 1, 'Kanya Ruangrit',     '1995-09-02', 22000, '2024-04-05', TRUE, '2026-01-27'),
  (117, 1, 'Direk Wattanasin',   '1987-12-24', 55000, '2018-01-10', TRUE, '2026-01-28'),
  (118, 1, 'Ratana Chotisiri',   '1992-02-14', 48000, '2021-09-09', TRUE, '2026-01-28'),
  (119, 1, 'Sombat Uthairat',    '1990-07-07', 62000, '2019-11-30', TRUE, '2026-01-29'),
  (120, 1, 'Wassana Intharaphan','1994-05-16', 44000, '2022-07-21', TRUE, '2026-01-29');

-- ----------------------------------------------------------------------------
-- Accounts — one checking account per customer, all linked for scanning
-- ----------------------------------------------------------------------------
INSERT INTO account (account_id, customer_id, account_number_masked, account_type, is_linked_for_scan, linked_date)
SELECT customer_id, customer_id, 'xxxx-xxxx-' || (1000 + customer_id), 'Checking', TRUE, '2026-01-30'
FROM customer;

-- ----------------------------------------------------------------------------
-- Transactions: BNPL repayment debits appearing on each customer's statement.
-- We insert transactions directly as "the BNPL repayment hit the account" —
-- in the real system, FR-01 would scan ALL transactions (groceries, rent,
-- etc.) and pick out only the ones matching a provider pattern; here we only
-- insert the ones relevant to BNPL detection, since that keeps the sample
-- data focused and the query results easy to verify by hand.
--
-- Cadence: monthly cycles for March, April, May 2026 (3 cycles).
-- account_id == customer_id, by construction above.
-- ----------------------------------------------------------------------------
INSERT INTO transaction (account_id, transaction_date, amount, description_raw, direction) VALUES
-- --- Customer 101: Somchai — stacked (Shopee + Atome), currently late on Shopee
(101, '2026-03-15', 1200.00, 'PAYMENT SPAYLATER TH0322', 'DEBIT'),
(101, '2026-03-18', 800.00,  'PAYMENT ATOME THAILAND',   'DEBIT'),
(101, '2026-04-15', 1200.00, 'PAYMENT SPAYLATER TH0422', 'DEBIT'),
(101, '2026-04-18', 800.00,  'PAYMENT ATOME THAILAND',   'DEBIT'),
(101, '2026-05-22', 1450.00, 'PAYMENT SPAYLATER TH0522', 'DEBIT'),  -- late + amount spike (late fee added)
(101, '2026-05-18', 800.00,  'PAYMENT ATOME THAILAND',   'DEBIT'),

-- --- Customer 102: Suda — stacked (SPayLater + LazPayLater + TrueMoney Next), late on 2
(102, '2026-03-10', 2000.00, 'PAYMENT SPAYLATER TH0310', 'DEBIT'),
(102, '2026-03-12', 1500.00, 'PAYMENT LAZPAYLATER ORDER','DEBIT'),
(102, '2026-03-14', 900.00,  'PAYMENT TRUEMONEY NEXT',   'DEBIT'),
(102, '2026-04-10', 2000.00, 'PAYMENT SPAYLATER TH0410', 'DEBIT'),
(102, '2026-04-12', 1500.00, 'PAYMENT LAZPAYLATER ORDER','DEBIT'),
(102, '2026-04-14', 900.00,  'PAYMENT TRUEMONEY NEXT',   'DEBIT'),
(102, '2026-05-25', 2300.00, 'PAYMENT SPAYLATER TH0510', 'DEBIT'), -- 15 days late + spike
(102, '2026-05-26', 1650.00, 'PAYMENT LAZPAYLATER ORDER','DEBIT'), -- 14 days late + spike
(102, '2026-05-14', 900.00,  'PAYMENT TRUEMONEY NEXT',   'DEBIT'),

-- --- Customer 103: Anan — stacked (Atome + Grab PayLater), late on Grab
(103, '2026-03-05', 1000.00, 'PAYMENT ATOME THAILAND',    'DEBIT'),
(103, '2026-03-08', 600.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(103, '2026-04-05', 1000.00, 'PAYMENT ATOME THAILAND',    'DEBIT'),
(103, '2026-04-08', 600.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(103, '2026-05-05', 1000.00, 'PAYMENT ATOME THAILAND',    'DEBIT'),
(103, '2026-05-19', 730.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'), -- 11 days late + spike

-- --- Customer 104: Nittaya — stacked (SPayLater + TrueMoney Next), late on both recently
(104, '2026-03-20', 1800.00, 'PAYMENT SPAYLATER TH0320',  'DEBIT'),
(104, '2026-03-22', 1100.00, 'PAYMENT TRUEMONEY NEXT',    'DEBIT'),
(104, '2026-04-20', 1800.00, 'PAYMENT SPAYLATER TH0420',  'DEBIT'),
(104, '2026-04-22', 1100.00, 'PAYMENT TRUEMONEY NEXT',    'DEBIT'),
(104, '2026-05-29', 2070.00, 'PAYMENT SPAYLATER TH0520',  'DEBIT'), -- 9 days late + spike
(104, '2026-05-30', 1265.00, 'PAYMENT TRUEMONEY NEXT',    'DEBIT'), -- 8 days late + spike

-- --- Customer 105: Kittipong — stacked (Atome + LazPayLater) but ALWAYS on time
(105, '2026-03-11', 900.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(105, '2026-03-13', 700.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'),
(105, '2026-04-11', 900.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(105, '2026-04-13', 700.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'),
(105, '2026-05-11', 900.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(105, '2026-05-13', 700.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'),

-- --- Customer 106: Wanida — stacked (SPayLater + Grab PayLater), always on time
(106, '2026-03-07', 1300.00, 'PAYMENT SPAYLATER TH0307',  'DEBIT'),
(106, '2026-03-09', 500.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(106, '2026-04-07', 1300.00, 'PAYMENT SPAYLATER TH0407',  'DEBIT'),
(106, '2026-04-09', 500.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(106, '2026-05-07', 1300.00, 'PAYMENT SPAYLATER TH0507',  'DEBIT'),
(106, '2026-05-09', 500.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),

-- --- Customer 107: Prasert — stacked (3 providers), always on time (high income, good planner)
(107, '2026-03-16', 2500.00, 'PAYMENT ATOME THAILAND',    'DEBIT'),
(107, '2026-03-17', 1800.00, 'PAYMENT SPAYLATER TH0317',  'DEBIT'),
(107, '2026-03-19', 1200.00, 'PAYMENT TRUEMONEY NEXT',    'DEBIT'),
(107, '2026-04-16', 2500.00, 'PAYMENT ATOME THAILAND',    'DEBIT'),
(107, '2026-04-17', 1800.00, 'PAYMENT SPAYLATER TH0417',  'DEBIT'),
(107, '2026-04-19', 1200.00, 'PAYMENT TRUEMONEY NEXT',    'DEBIT'),
(107, '2026-05-16', 2500.00, 'PAYMENT ATOME THAILAND',    'DEBIT'),
(107, '2026-05-17', 1800.00, 'PAYMENT SPAYLATER TH0517',  'DEBIT'),
(107, '2026-05-19', 1200.00, 'PAYMENT TRUEMONEY NEXT',    'DEBIT'),

-- --- Customer 108: Malee — stacked (SPayLater + Atome), always on time
(108, '2026-03-04', 950.00,  'PAYMENT SPAYLATER TH0304',  'DEBIT'),
(108, '2026-03-06', 650.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(108, '2026-04-04', 950.00,  'PAYMENT SPAYLATER TH0404',  'DEBIT'),
(108, '2026-04-06', 650.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(108, '2026-05-04', 950.00,  'PAYMENT SPAYLATER TH0504',  'DEBIT'),
(108, '2026-05-06', 650.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),

-- --- Customer 109-112: single provider only (never stacked)
(109, '2026-03-21', 700.00,  'PAYMENT SPAYLATER TH0321',  'DEBIT'),
(109, '2026-04-21', 700.00,  'PAYMENT SPAYLATER TH0421',  'DEBIT'),
(109, '2026-05-21', 700.00,  'PAYMENT SPAYLATER TH0521',  'DEBIT'),
(110, '2026-03-23', 500.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(110, '2026-04-23', 500.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(110, '2026-05-23', 500.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(111, '2026-03-02', 400.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(111, '2026-04-02', 400.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(111, '2026-05-02', 400.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(112, '2026-03-27', 350.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'),
(112, '2026-04-27', 350.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'),
(112, '2026-05-27', 350.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'),

-- --- Customer 113-116: stacked + currently late, but LOW income / will fail screening
(113, '2026-03-06', 800.00,  'PAYMENT SPAYLATER TH0306',  'DEBIT'),
(113, '2026-03-08', 600.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(113, '2026-04-06', 800.00,  'PAYMENT SPAYLATER TH0406',  'DEBIT'),
(113, '2026-04-08', 600.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(113, '2026-05-20', 980.00,  'PAYMENT SPAYLATER TH0506',  'DEBIT'), -- 14 days late + spike
(113, '2026-05-21', 735.00,  'PAYMENT ATOME THAILAND',    'DEBIT'), -- 13 days late + spike

(114, '2026-03-14', 600.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'),
(114, '2026-03-16', 450.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(114, '2026-04-14', 600.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'),
(114, '2026-04-16', 450.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(114, '2026-05-25', 735.00,  'PAYMENT LAZPAYLATER ORDER', 'DEBIT'), -- 11 days late + spike
(114, '2026-05-26', 550.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'), -- 10 days late + spike

(115, '2026-03-09', 700.00,  'PAYMENT SPAYLATER TH0309',  'DEBIT'),
(115, '2026-03-11', 500.00,  'PAYMENT TRUEMONEY NEXT',    'DEBIT'),
(115, '2026-04-09', 700.00,  'PAYMENT SPAYLATER TH0409',  'DEBIT'),
(115, '2026-04-11', 500.00,  'PAYMENT TRUEMONEY NEXT',    'DEBIT'),
(115, '2026-05-24', 875.00,  'PAYMENT SPAYLATER TH0509',  'DEBIT'), -- 15 days late + spike
(115, '2026-05-25', 615.00,  'PAYMENT TRUEMONEY NEXT',    'DEBIT'), -- 14 days late + spike

(116, '2026-03-13', 550.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(116, '2026-03-15', 400.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(116, '2026-04-13', 550.00,  'PAYMENT ATOME THAILAND',    'DEBIT'),
(116, '2026-04-15', 400.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'),
(116, '2026-05-22', 690.00,  'PAYMENT ATOME THAILAND',    'DEBIT'), -- 9 days late + spike
(116, '2026-05-23', 495.00,  'PAYMENT GRAB PAYLATER',     'DEBIT'); -- 8 days late + spike

-- Customers 117-120: no BNPL transactions at all (control group — regular banking customers)

-- ----------------------------------------------------------------------------
-- Detected obligations — one row per repayment cycle, tying each transaction
-- back to a provider and a due date. due_date is set to the ON-TIME date for
-- that cycle (the 1st/2nd cycle transactions ARE the due date; the 3rd-cycle
-- "late" transactions above happened AFTER the due date below).
-- ----------------------------------------------------------------------------
INSERT INTO detected_obligation (customer_id, provider_id, transaction_id, due_date, expected_amount, actual_paid_amount, actual_paid_date, cycle_number) VALUES
-- Somchai (101)
(101, 1, 1, '2026-03-15', 1200.00, 1200.00, '2026-03-15', 1),
(101, 2, 2, '2026-03-18', 800.00,  800.00,  '2026-03-18', 1),
(101, 1, 3, '2026-04-15', 1200.00, 1200.00, '2026-04-15', 2),
(101, 2, 4, '2026-04-18', 800.00,  800.00,  '2026-04-18', 2),
(101, 1, 5, '2026-05-15', 1200.00, 1450.00, '2026-05-22', 3),
(101, 2, 6, '2026-05-18', 800.00,  800.00,  '2026-05-18', 3),
-- Suda (102)
(102, 1, 7,  '2026-03-10', 2000.00, 2000.00, '2026-03-10', 1),
(102, 3, 8,  '2026-03-12', 1500.00, 1500.00, '2026-03-12', 1),
(102, 4, 9,  '2026-03-14', 900.00,  900.00,  '2026-03-14', 1),
(102, 1, 10, '2026-04-10', 2000.00, 2000.00, '2026-04-10', 2),
(102, 3, 11, '2026-04-12', 1500.00, 1500.00, '2026-04-12', 2),
(102, 4, 12, '2026-04-14', 900.00,  900.00,  '2026-04-14', 2),
(102, 1, 13, '2026-05-10', 2000.00, 2300.00, '2026-05-25', 3),
(102, 3, 14, '2026-05-12', 1500.00, 1650.00, '2026-05-26', 3),
(102, 4, 15, '2026-05-14', 900.00,  900.00,  '2026-05-14', 3),
-- Anan (103)
(103, 2, 16, '2026-03-05', 1000.00, 1000.00, '2026-03-05', 1),
(103, 5, 17, '2026-03-08', 600.00,  600.00,  '2026-03-08', 1),
(103, 2, 18, '2026-04-05', 1000.00, 1000.00, '2026-04-05', 2),
(103, 5, 19, '2026-04-08', 600.00,  600.00,  '2026-04-08', 2),
(103, 2, 20, '2026-05-05', 1000.00, 1000.00, '2026-05-05', 3),
(103, 5, 21, '2026-05-08', 600.00,  730.00,  '2026-05-19', 3),
-- Nittaya (104)
(104, 1, 22, '2026-03-20', 1800.00, 1800.00, '2026-03-20', 1),
(104, 4, 23, '2026-03-22', 1100.00, 1100.00, '2026-03-22', 1),
(104, 1, 24, '2026-04-20', 1800.00, 1800.00, '2026-04-20', 2),
(104, 4, 25, '2026-04-22', 1100.00, 1100.00, '2026-04-22', 2),
(104, 1, 26, '2026-05-20', 1800.00, 2070.00, '2026-05-29', 3),
(104, 4, 27, '2026-05-22', 1100.00, 1265.00, '2026-05-30', 3),
-- Kittipong (105) - always on time
(105, 2, 28, '2026-03-11', 900.00, 900.00, '2026-03-11', 1),
(105, 3, 29, '2026-03-13', 700.00, 700.00, '2026-03-13', 1),
(105, 2, 30, '2026-04-11', 900.00, 900.00, '2026-04-11', 2),
(105, 3, 31, '2026-04-13', 700.00, 700.00, '2026-04-13', 2),
(105, 2, 32, '2026-05-11', 900.00, 900.00, '2026-05-11', 3),
(105, 3, 33, '2026-05-13', 700.00, 700.00, '2026-05-13', 3),
-- Wanida (106) - always on time
(106, 1, 34, '2026-03-07', 1300.00, 1300.00, '2026-03-07', 1),
(106, 5, 35, '2026-03-09', 500.00,  500.00,  '2026-03-09', 1),
(106, 1, 36, '2026-04-07', 1300.00, 1300.00, '2026-04-07', 2),
(106, 5, 37, '2026-04-09', 500.00,  500.00,  '2026-04-09', 2),
(106, 1, 38, '2026-05-07', 1300.00, 1300.00, '2026-05-07', 3),
(106, 5, 39, '2026-05-09', 500.00,  500.00,  '2026-05-09', 3),
-- Prasert (107) - always on time, 3 providers
(107, 2, 40, '2026-03-16', 2500.00, 2500.00, '2026-03-16', 1),
(107, 1, 41, '2026-03-17', 1800.00, 1800.00, '2026-03-17', 1),
(107, 4, 42, '2026-03-19', 1200.00, 1200.00, '2026-03-19', 1),
(107, 2, 43, '2026-04-16', 2500.00, 2500.00, '2026-04-16', 2),
(107, 1, 44, '2026-04-17', 1800.00, 1800.00, '2026-04-17', 2),
(107, 4, 45, '2026-04-19', 1200.00, 1200.00, '2026-04-19', 2),
(107, 2, 46, '2026-05-16', 2500.00, 2500.00, '2026-05-16', 3),
(107, 1, 47, '2026-05-17', 1800.00, 1800.00, '2026-05-17', 3),
(107, 4, 48, '2026-05-19', 1200.00, 1200.00, '2026-05-19', 3),
-- Malee (108) - always on time
(108, 1, 49, '2026-03-04', 950.00, 950.00, '2026-03-04', 1),
(108, 2, 50, '2026-03-06', 650.00, 650.00, '2026-03-06', 1),
(108, 1, 51, '2026-04-04', 950.00, 950.00, '2026-04-04', 2),
(108, 2, 52, '2026-04-06', 650.00, 650.00, '2026-04-06', 2),
(108, 1, 53, '2026-05-04', 950.00, 950.00, '2026-05-04', 3),
(108, 2, 54, '2026-05-06', 650.00, 650.00, '2026-05-06', 3),
-- 109-112: single provider each
(109, 1, 55, '2026-03-21', 700.00, 700.00, '2026-03-21', 1),
(109, 1, 56, '2026-04-21', 700.00, 700.00, '2026-04-21', 2),
(109, 1, 57, '2026-05-21', 700.00, 700.00, '2026-05-21', 3),
(110, 2, 58, '2026-03-23', 500.00, 500.00, '2026-03-23', 1),
(110, 2, 59, '2026-04-23', 500.00, 500.00, '2026-04-23', 2),
(110, 2, 60, '2026-05-23', 500.00, 500.00, '2026-05-23', 3),
(111, 5, 61, '2026-03-02', 400.00, 400.00, '2026-03-02', 1),
(111, 5, 62, '2026-04-02', 400.00, 400.00, '2026-04-02', 2),
(111, 5, 63, '2026-05-02', 400.00, 400.00, '2026-05-02', 3),
(112, 3, 64, '2026-03-27', 350.00, 350.00, '2026-03-27', 1),
(112, 3, 65, '2026-04-27', 350.00, 350.00, '2026-04-27', 2),
(112, 3, 66, '2026-05-27', 350.00, 350.00, '2026-05-27', 3),
-- 113-116: stacked + late, low income
(113, 1, 67, '2026-03-06', 800.00, 800.00, '2026-03-06', 1),
(113, 2, 68, '2026-03-08', 600.00, 600.00, '2026-03-08', 1),
(113, 1, 69, '2026-04-06', 800.00, 800.00, '2026-04-06', 2),
(113, 2, 70, '2026-04-08', 600.00, 600.00, '2026-04-08', 2),
(113, 1, 71, '2026-05-06', 800.00, 980.00, '2026-05-20', 3),
(113, 2, 72, '2026-05-08', 600.00, 735.00, '2026-05-21', 3),
(114, 3, 73, '2026-03-14', 600.00, 600.00, '2026-03-14', 1),
(114, 5, 74, '2026-03-16', 450.00, 450.00, '2026-03-16', 1),
(114, 3, 75, '2026-04-14', 600.00, 600.00, '2026-04-14', 2),
(114, 5, 76, '2026-04-16', 450.00, 450.00, '2026-04-16', 2),
(114, 3, 77, '2026-05-14', 600.00, 735.00, '2026-05-25', 3),
(114, 5, 78, '2026-05-16', 450.00, 550.00, '2026-05-26', 3),
(115, 1, 79, '2026-03-09', 700.00, 700.00, '2026-03-09', 1),
(115, 4, 80, '2026-03-11', 500.00, 500.00, '2026-03-11', 1),
(115, 1, 81, '2026-04-09', 700.00, 700.00, '2026-04-09', 2),
(115, 4, 82, '2026-04-11', 500.00, 500.00, '2026-04-11', 2),
(115, 1, 83, '2026-05-09', 700.00, 875.00, '2026-05-24', 3),
(115, 4, 84, '2026-05-11', 500.00, 615.00, '2026-05-25', 3),
(116, 2, 85, '2026-03-13', 550.00, 550.00, '2026-03-13', 1),
(116, 5, 86, '2026-03-15', 400.00, 400.00, '2026-03-15', 1),
(116, 2, 87, '2026-04-13', 550.00, 550.00, '2026-04-13', 2),
(116, 5, 88, '2026-04-15', 400.00, 400.00, '2026-04-15', 2),
(116, 2, 89, '2026-05-13', 550.00, 690.00, '2026-05-22', 3),
(116, 5, 90, '2026-05-15', 400.00, 495.00, '2026-05-23', 3);

-- ----------------------------------------------------------------------------
-- Late payment signals — one row per obligation where actual_paid_date is
-- more than the configured threshold (3 days) after due_date.
-- (In the real system, Business Rule R-02 generates these automatically;
-- here we insert them directly to match the "late" obligations above.)
-- ----------------------------------------------------------------------------
INSERT INTO late_payment_signal (obligation_id, customer_id, provider_id, days_late, signal_date, signal_reason) VALUES
(5,  101, 1, 7,  '2026-05-22', 'LATE_PAYMENT'),
(13, 102, 1, 15, '2026-05-25', 'LATE_PAYMENT'),
(14, 102, 3, 14, '2026-05-26', 'LATE_PAYMENT'),
(21, 103, 5, 11, '2026-05-19', 'LATE_PAYMENT'),
(26, 104, 1, 9,  '2026-05-29', 'LATE_PAYMENT'),
(27, 104, 4, 8,  '2026-05-30', 'LATE_PAYMENT'),
(71, 113, 1, 14, '2026-05-20', 'LATE_PAYMENT'),
(72, 113, 2, 13, '2026-05-21', 'LATE_PAYMENT'),
(77, 114, 3, 11, '2026-05-25', 'LATE_PAYMENT'),
(78, 114, 5, 10, '2026-05-26', 'LATE_PAYMENT'),
(83, 115, 1, 15, '2026-05-24', 'LATE_PAYMENT'),
(84, 115, 4, 14, '2026-05-25', 'LATE_PAYMENT'),
(89, 116, 2, 9,  '2026-05-22', 'LATE_PAYMENT'),
(90, 116, 5, 8,  '2026-05-23', 'LATE_PAYMENT');

-- ----------------------------------------------------------------------------
-- Credit screening results (Business Rule R-04 / R-05).
--   101-104: good income + good credit -> ELIGIBLE
--   113-116: low income / high DSR -> NOT ELIGIBLE (must be referred, R-05)
-- ----------------------------------------------------------------------------
INSERT INTO credit_screening_result (customer_id, screening_date, credit_score, dsr_pct, income_stability_flag, eligibility_outcome, reason) VALUES
(101, '2026-05-23', 715, 32.5, TRUE,  'Eligible',     'Meets all thresholds: score >= 600, DSR <= 50%, stable income.'),
(102, '2026-05-27', 680, 41.0, TRUE,  'Eligible',     'Meets all thresholds.'),
(103, '2026-05-20', 702, 38.2, TRUE,  'Eligible',     'Meets all thresholds.'),
(104, '2026-05-30', 690, 44.8, TRUE,  'Eligible',     'Meets all thresholds.'),
(113, '2026-05-21', 560, 61.0, FALSE, 'Not Eligible', 'Credit score below 600 and DSR above 50%.'),
(114, '2026-05-26', 545, 58.0, FALSE, 'Not Eligible', 'Credit score below 600 and DSR above 50%.'),
(115, '2026-05-25', 572, 55.5, TRUE,  'Not Eligible', 'DSR above 50% threshold despite stable income.'),
(116, '2026-05-23', 530, 63.0, FALSE, 'Not Eligible', 'Credit score below 600 and DSR above 50%.');

-- ----------------------------------------------------------------------------
-- Consolidation offers — only for the 4 customers who passed screening.
-- offered_rate_pct is deliberately BELOW each customer's current blended
-- penalty rate, matching the FRD's "undercut the penalty rate" mechanism.
-- ----------------------------------------------------------------------------
INSERT INTO consolidation_offer (customer_id, screening_id, offer_date, total_amount, offered_rate_pct, monthly_payment, status) VALUES
(101, 1, '2026-05-23', 2000.00, 15.00, 180.00, 'Accepted'),
(102, 2, '2026-05-27', 4400.00, 15.00, 385.00, 'Accepted'),
(103, 3, '2026-05-20', 1730.00, 14.00, 149.00, 'Declined'),
(104, 4, '2026-05-30', 3335.00, 15.00, 291.00, 'Accepted');

-- ----------------------------------------------------------------------------
-- Subscriptions — every customer with linked accounts gets the free tier;
-- a subset has also turned on Auto-Pay. BOTH are free (Business Model
-- Decision #1/#5, locked 2026-09-16) — plan_type is a feature-engagement
-- flag only, never a billing tier, hence no fee column on this table.
-- ----------------------------------------------------------------------------
INSERT INTO subscription (customer_id, plan_type, start_date, status)
SELECT customer_id, 'Free', '2026-01-30', 'Active' FROM customer;

INSERT INTO subscription (customer_id, plan_type, start_date, status) VALUES
(101, 'AutoPay', '2026-02-01', 'Active'),
(102, 'AutoPay', '2026-02-01', 'Active'),
(103, 'AutoPay', '2026-02-05', 'Active'),
(105, 'AutoPay', '2026-02-10', 'Active'),
(106, 'AutoPay', '2026-02-15', 'Active'),
(107, 'AutoPay', '2026-02-01', 'Active'),
(108, 'AutoPay', '2026-02-20', 'Active'),
(109, 'AutoPay', '2026-03-01', 'Active'),
(113, 'AutoPay', '2026-02-25', 'Cancelled');

-- ----------------------------------------------------------------------------
-- Auto-pay runs — mostly successful, with one deliberate failure to support
-- the FRD Edge Case "Auto-Pay deduction fails (insufficient funds)".
-- ----------------------------------------------------------------------------
INSERT INTO auto_pay_run (subscription_id, run_date, total_deducted, run_status, failure_reason) VALUES
(1, '2026-05-15', 2000.00, 'Success', NULL),
(2, '2026-05-10', 4400.00, 'Success', NULL),
(3, '2026-05-05', 1600.00, 'Failed',  'Insufficient funds'),
(3, '2026-05-19', 1600.00, 'Success', NULL);

-- ============================================================================
-- Quick sanity counts (safe to run — SELECT only)
-- ============================================================================
-- SELECT (SELECT COUNT(*) FROM customer) AS customers,
--        (SELECT COUNT(*) FROM transaction) AS transactions,
--        (SELECT COUNT(*) FROM detected_obligation) AS obligations,
--        (SELECT COUNT(*) FROM late_payment_signal) AS late_signals,
--        (SELECT COUNT(*) FROM credit_screening_result) AS screenings,
--        (SELECT COUNT(*) FROM consolidation_offer) AS offers,
--        (SELECT COUNT(*) FROM subscription) AS subscriptions;
