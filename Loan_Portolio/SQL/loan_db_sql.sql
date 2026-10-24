CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY,
    customer_name VARCHAR(100),
    age INTEGER,
    gender VARCHAR(20),
    employment_type VARCHAR(30),
    annual_income NUMERIC(12,2),
    credit_score INTEGER
);

CREATE TABLE branches (
    branch_id INTEGER ,
    branch_name VARCHAR(100),
    city VARCHAR(100)
);

CREATE TABLE loans (
    loan_id INTEGER PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id),
    loan_type VARCHAR(30),
    loan_amount NUMERIC(14,2),
    interest_rate NUMERIC(5,2),
    loan_term_months INTEGER,
    loan_status VARCHAR(20)
);

CREATE TABLE payments (
    payment_id  BIGINT PRIMARY KEY,
    loan_id INTEGER REFERENCES loans(loan_id),
    payment_date DATE,
    amount_paid NUMERIC(14,2),
    payment_status VARCHAR(20)
);

--customers data
SELECT * FROM customers;

--branches data
SELECT * FROM branches;

--loans data
SELECT * FROM loans;

--payments data 
SELECT * FROM payments;

--1. Overall loan portfolio summary
--(question: How many loans do we have, how much money has been lent, and how many loans are in default?)

SELECT
    COUNT(*) AS total_loans,
    COUNT(DISTINCT customer_id) AS total_customers,
    SUM(loan_amount) AS total_loan_amount,
    ROUND(AVG(loan_amount), 2) AS average_loan_amount,
    COUNT(*) FILTER (
        WHERE LOWER(loan_status) = 'default'
    ) AS defaulted_loans,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE LOWER(loan_status) = 'default'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS default_rate_percentage
FROM loans;

--2. Loan status distribution
--(question: What percentage of loans are fully paid, active, or in default?)
SELECT
    loan_status,
    COUNT(*) AS total_loans,
    SUM(loan_amount) AS total_loan_amount,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage_of_loans
FROM loans
GROUP BY loan_status
ORDER BY total_loans DESC;

--3.Default rate by loan type
--(Business question: Which loan types have the highest default rate?)
SELECT
    loan_type,
    COUNT(*) AS total_loans,
    COUNT(*) FILTER (
        WHERE LOWER(loan_status) = 'default'
    ) AS defaulted_loans,
    SUM(loan_amount) AS total_loan_amount,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE LOWER(loan_status) = 'default'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS default_rate_percentage
FROM loans
GROUP BY loan_type
ORDER BY default_rate_percentage DESC;

--4.Default rate by employment type — JOIN
--(Business question: Which employment groups have higher loan default rates?)
SELECT
    c.employment_type,
    COUNT(l.loan_id) AS total_loans,
    COUNT(l.loan_id) FILTER (
        WHERE LOWER(l.loan_status) = 'default'
    ) AS defaulted_loans,
    ROUND(AVG(c.annual_income), 2) AS average_annual_income,
    ROUND(
        100.0 * COUNT(l.loan_id) FILTER (
            WHERE LOWER(l.loan_status) = 'default'
        ) / NULLIF(COUNT(l.loan_id), 0),
        2
    ) AS default_rate_percentage
FROM customers c
INNER JOIN loans l
    ON c.customer_id = l.customer_id
GROUP BY c.employment_type
ORDER BY default_rate_percentage DESC;

--5. Default rate by credit score group
--(Business question: Are loans belonging to lower-credit-score customers more likely to default?)

SELECT
    CASE
        WHEN c.credit_score < 600 THEN 'Below 600'
        WHEN c.credit_score < 700 THEN '600-699'
        WHEN c.credit_score < 750 THEN '700-749'
        ELSE '750 and above'
    END AS credit_score_group,
    COUNT(l.loan_id) AS total_loans,
    COUNT(l.loan_id) FILTER (
        WHERE LOWER(l.loan_status) = 'default'
    ) AS defaulted_loans,
    ROUND(
        100.0 * COUNT(l.loan_id) FILTER (
            WHERE LOWER(l.loan_status) = 'default'
        ) / NULLIF(COUNT(l.loan_id), 0),
        2
    ) AS default_rate_percentage
FROM customers c
INNER JOIN loans l
    ON c.customer_id = l.customer_id
WHERE c.credit_score IS NOT NULL
GROUP BY
    CASE
        WHEN c.credit_score < 600 THEN 'Below 600'
        WHEN c.credit_score < 700 THEN '600-699'
        WHEN c.credit_score < 750 THEN '700-749'
        ELSE '750 and above'
    END
ORDER BY default_rate_percentage DESC;

--6. Identify potentially high-risk customers — CTE
--(Business question: Which customers have multiple loans and a high default rate?)
WITH customer_loan_summary AS (
    SELECT
        c.customer_id,
        c.customer_name,
        c.annual_income,
        c.credit_score,
        COUNT(l.loan_id) AS total_loans,
        COUNT(l.loan_id) FILTER (
            WHERE LOWER(l.loan_status) = 'default'
        ) AS defaulted_loans,
        SUM(l.loan_amount) AS total_loan_amount
    FROM customers c
    INNER JOIN loans l
        ON c.customer_id = l.customer_id
    GROUP BY
        c.customer_id,
        c.customer_name,
        c.annual_income,
        c.credit_score
)
SELECT
    customer_id,
    customer_name,
    annual_income,
    credit_score,
    total_loans,
    defaulted_loans,
    total_loan_amount,
    ROUND(
        100.0 * defaulted_loans / NULLIF(total_loans, 0),
        2
    ) AS default_rate_percentage
FROM customer_loan_summary
WHERE total_loans >= 2
  AND 1.0 * defaulted_loans / NULLIF(total_loans, 0) > 0.20
ORDER BY default_rate_percentage DESC, total_loan_amount DESC;

--7. Rank loan types by total lending — Window function
--Business question: Which loan types account for the largest lending amounts?

WITH loan_type_summary AS (
    SELECT
        loan_type,
        COUNT(*) AS total_loans,
        SUM(loan_amount) AS total_loan_amount
    FROM loans
    GROUP BY loan_type
)
SELECT
    loan_type,
    total_loans,
    total_loan_amount,
    RANK() OVER (
        ORDER BY total_loan_amount DESC
    ) AS lending_rank
FROM loan_type_summary
ORDER BY lending_rank;

--8. Customer-level loan exposure — JOIN and GROUP BY
--Business question: Which customers have the largest total loan amounts?

SELECT
    c.customer_id,
    c.customer_name,
    c.employment_type,
    c.annual_income,
    COUNT(l.loan_id) AS total_loans,
    SUM(l.loan_amount) AS total_loan_amount,
    ROUND(AVG(l.interest_rate), 2) AS average_interest_rate,
    COUNT(l.loan_id) FILTER (
        WHERE LOWER(l.loan_status) = 'default'
    ) AS defaulted_loans
FROM customers c
INNER JOIN loans l
    ON c.customer_id = l.customer_id
GROUP BY
    c.customer_id,
    c.customer_name,
    c.employment_type,
    c.annual_income
ORDER BY total_loan_amount DESC
LIMIT 20;

--9.Compare loan amounts with recorded payments — LEFT JOIN
--Business question: Which loans have no payment records, and how much has been paid against each loan?

SELECT
    l.loan_id,
    l.customer_id,
    l.loan_type,
    l.loan_amount,
    l.loan_status,
    COUNT(p.payment_id) AS payment_records,
    COALESCE(SUM(p.amount_paid), 0) AS total_recorded_payments,
    l.loan_amount
        - COALESCE(SUM(p.amount_paid), 0) AS amount_difference
FROM loans l
LEFT JOIN payments p
    ON l.loan_id = p.loan_id
GROUP BY
    l.loan_id,
    l.customer_id,
    l.loan_type,
    l.loan_amount,
    l.loan_status
ORDER BY amount_difference DESC;

--10. Monthly payment trend
--Business question: How do recorded payment amounts change month by month?

SELECT
    DATE_TRUNC('month', payment_date)::DATE AS payment_month,
    COUNT(*) AS payment_records,
    SUM(amount_paid) AS total_amount_paid,
    ROUND(AVG(amount_paid), 2) AS average_payment
FROM payments
WHERE payment_date IS NOT NULL
GROUP BY DATE_TRUNC('month', payment_date)::DATE
ORDER BY payment_month;