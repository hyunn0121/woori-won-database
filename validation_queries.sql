-- ============================================================
-- 파일명: validation_queries.sql
-- 설명: 지역화폐 시스템 DB 검증용 쿼리 모음 (정상 4종 + 비정상 8종)
-- ============================================================

-- ============================================================
-- [PART 1] 정상 서비스 흐름 (4가지)
-- ============================================================

-- [정상 01] 사용자 계좌 충전
-- 설명: 김민준 고객(100001)이 서울 지역화폐 계좌(5000001)에 10만 원을 계좌이체로 충전
START TRANSACTION;

INSERT INTO RECHARGE_TRANSACTION (
    recharge_id, account_id, recharge_dt, recharge_amt, 
    recharge_method_cd, cash_yn, bal_after, device_info, retain_until
)
SELECT 
    8000014, 5000001, NOW(), 100000, 
    '계좌이체', 'N', (cash_balance + 100000), 
    'MOBILE-AOS', DATE_ADD(CURDATE(), INTERVAL 5 YEAR)
FROM LOCAL_ACCOUNT 
WHERE account_id = 5000001;

UPDATE LOCAL_ACCOUNT 
SET cash_balance = cash_balance + 100000 
WHERE account_id = 5000001;

COMMIT;


-- [정상 02] 가맹점 결제 및 캐시백 적립
-- 설명: 김민준 고객(100001)이 종로김밥 본점(700001)에서 3만 원 결제
--      (충전금 차감 + 서울시 캐시백 10% 적립 + 지자체 예산 소진 + 개인 월한도 누적)
START TRANSACTION;

INSERT INTO PAYMENT_TRANSACTION (
    payment_id, account_id, merchant_id, pay_dt, pay_status_cd, 
    total_tx_amt, use_cashback_amt, pay_cash_amt, earn_cashback_amt, 
    cash_bal_after, cashback_bal_after, device_info, retain_until
)
SELECT 
    9000025, 5000001, 700001, NOW(), '승인', 
    30000, 0, 30000, 3000, 
    (la.cash_balance - 30000), 
    (ca.cashback_balance + 3000), 
    'MOBILE-AOS', DATE_ADD(CURDATE(), INTERVAL 5 YEAR)
FROM LOCAL_ACCOUNT la
JOIN CASHBACK_ACCOUNT ca ON la.account_id = ca.account_id
WHERE la.account_id = 5000001;

UPDATE LOCAL_ACCOUNT SET cash_balance = cash_balance - 30000 WHERE account_id = 5000001;

UPDATE CASHBACK_ACCOUNT 
SET cashback_balance = cashback_balance + 3000, 
    total_accumulated_amt = total_accumulated_amt + 3000, 
    last_updated_dt = NOW()
WHERE account_id = 5000001;

UPDATE BUDGET_MASTER 
SET used_budget = used_budget + 3000, 
    available_budget = available_budget - 3000, 
    upd_dt = NOW()
WHERE region_code = '11000' AND target_year = '2026';

UPDATE USER_LIMIT_MANAGEMENT 
SET monthly_pay_amt = monthly_pay_amt + 30000, 
    monthly_earned_cashback = monthly_earned_cashback + 3000, 
    upd_dt = NOW()
WHERE user_id = 100001 AND target_month = '202609';

COMMIT;


-- [정상 03] 결제 취소 (역분개 원상복구)
-- 설명: 결제 취소 요청 시 음수 금액 거래를 기록하고 원장 및 예산을 복구
START TRANSACTION;

INSERT INTO PAYMENT_TRANSACTION (
    payment_id, account_id, merchant_id, pay_dt, pay_status_cd, 
    total_tx_amt, use_cashback_amt, pay_cash_amt, earn_cashback_amt, 
    cash_bal_after, cashback_bal_after, device_info, retain_until
)
SELECT 
    9000026, 5000001, 700001, NOW(), '취소완료', 
    -30000, 0, -30000, -3000, 
    (la.cash_balance + 30000), 
    (ca.cashback_balance - 3000), 
    'MOBILE-AOS', DATE_ADD(CURDATE(), INTERVAL 5 YEAR)
FROM LOCAL_ACCOUNT la
JOIN CASHBACK_ACCOUNT ca ON la.account_id = ca.account_id
WHERE la.account_id = 5000001;

UPDATE LOCAL_ACCOUNT SET cash_balance = cash_balance + 30000 WHERE account_id = 5000001;
UPDATE CASHBACK_ACCOUNT SET cashback_balance = cashback_balance - 3000, total_accumulated_amt = total_accumulated_amt - 3000 WHERE account_id = 5000001;
UPDATE BUDGET_MASTER SET used_budget = used_budget - 3000, available_budget = available_budget + 3000 WHERE region_code = '11000' AND target_year = '2026';

COMMIT;


-- [정상 04] 가맹점 일일 정산 (수수료 0.3% 공제)
-- 설명: 당일 승인 거래를 집계하여 정산 테이블(SETTLEMENT_DAILY) 생성
INSERT INTO SETTLEMENT_DAILY (
    settlement_id, settlement_date, merchant_id, 
    total_sales_amt, fee_amt, actual_payout_amt, payout_status
)
SELECT 
    3000025, CURDATE(), merchant_id, 
    SUM(total_tx_amt) AS total_sales_amt,
    ROUND(SUM(total_tx_amt) * 0.003, 0) AS fee_amt,
    SUM(total_tx_amt) - ROUND(SUM(total_tx_amt) * 0.003, 0) AS actual_payout_amt,
    '지급대기'
FROM PAYMENT_TRANSACTION
WHERE DATE(pay_dt) = CURDATE() AND pay_status_cd = '승인'
GROUP BY merchant_id;


-- ============================================================
-- [PART 2] 비정상 예외 상황 검증 (8가지)
-- ============================================================

-- [비정상 01] 지자체 예산 초과 결제 시도
-- 설명: 지자체 남은 예산(available_budget)보다 적립 예정 캐시백이 큰 경우 롤백
START TRANSACTION;

INSERT INTO PAYMENT_TRANSACTION (payment_id, account_id, merchant_id, pay_dt, pay_status_cd, total_tx_amt, cash_bal_after, cashback_bal_after)
SELECT 9000027, 5000001, 700001, NOW(), 'FAILED_NO_BUDGET', 3000000, la.cash_balance, ca.cashback_balance
FROM LOCAL_ACCOUNT la
JOIN CASHBACK_ACCOUNT ca ON la.account_id = ca.account_id
JOIN BUDGET_MASTER bm ON la.region_code = bm.region_code
WHERE la.account_id = 5000001 AND bm.target_year = '2026' AND bm.available_budget < 300000;

ROLLBACK;


-- [비정상 02] 개인별 월 결제 한도 초과
-- 설명: 최지은 고객(100004)의 당월 결제 한도(40만 원) 초과 여부 사전 검증
SELECT 
    ulm.user_id,
    ulm.monthly_pay_amt AS 당월누적결제액,
    br.individual_monthly_limit AS 월한도금액,
    CASE 
        WHEN (ulm.monthly_pay_amt + 50000) > br.individual_monthly_limit 
        THEN 'EXCEEDED_PAY_LIMIT (개인 월 결제 한도 초과)'
        ELSE 'APPROVED'
    END AS 검증결과
FROM USER_LIMIT_MANAGEMENT ulm
JOIN LOCAL_ACCOUNT la ON ulm.user_id = la.user_id
JOIN BUDGET_REGION br ON la.region_code = br.region_code
WHERE ulm.user_id = 100004 AND ulm.target_month = '202608' AND la.account_id = 5000006;


-- [비정상 03] 개인별 월 캐시백 적립 한도 초과
-- 설명: 최지은 고객(100004)의 캐시백 한도(4만 원) 도달 상태에서 추가 적립 차단 검증
SELECT 
    ulm.user_id,
    ulm.monthly_earned_cashback AS 당월누적캐시백,
    br.individual_cashback_limit AS 월캐시백한도,
    CASE 
        WHEN (ulm.monthly_earned_cashback + 1000) > br.individual_cashback_limit 
        THEN 'EXCEEDED_CASHBACK_LIMIT (월 캐시백 적립 한도 초과)'
        ELSE 'APPROVED'
    END AS 검증결과
FROM USER_LIMIT_MANAGEMENT ulm
JOIN LOCAL_ACCOUNT la ON ulm.user_id = la.user_id
JOIN BUDGET_REGION br ON la.region_code = br.region_code
WHERE ulm.user_id = 100004 AND ulm.target_month = '202608' AND la.account_id = 5000006;


-- [비정상 04] 연 매출 30억 초과 가맹점 결제 시도
-- 설명: 메가마트 부산중구점(700006, 매출 39.2억) 결제 시 거절 처리
INSERT INTO PAYMENT_TRANSACTION (payment_id, account_id, merchant_id, pay_dt, pay_status_cd, total_tx_amt, cash_bal_after, cashback_bal_after)
SELECT 9000028, 5000004, m.merchant_id, NOW(), 'REJECTED_ANNUAL_REVENUE_EXCEEDED', 15000, la.cash_balance, ca.cashback_balance
FROM MERCHANT m
JOIN LOCAL_ACCOUNT la ON la.account_id = 5000004
JOIN CASHBACK_ACCOUNT ca ON ca.account_id = 5000004
WHERE m.merchant_id = 700006 AND m.annual_revenue > 3000000000;


-- [비정상 05] 비활성화/해지 가맹점 결제 시도
-- 설명: 가맹점 상태가 '가맹해지'인 메가마트 부산중구점(700006) 결제 시 거절 처리
INSERT INTO PAYMENT_TRANSACTION (payment_id, account_id, merchant_id, pay_dt, pay_status_cd, total_tx_amt, cash_bal_after, cashback_bal_after)
SELECT 9000029, 5000004, m.merchant_id, NOW(), 'REJECTED_INACTIVE_MERCHANT', 10000, la.cash_balance, ca.cashback_balance
FROM MERCHANT m
JOIN LOCAL_ACCOUNT la ON la.account_id = 5000004
JOIN CASHBACK_ACCOUNT ca ON ca.account_id = 5000004
WHERE m.merchant_id = 700006 AND m.status_code != '정상';


-- [비정상 06] 계좌 잔액 부족 결제 시도
-- 설명: 강준우 고객 계좌(5000007, 잔액 56,500원)에서 100,000원 결제 시도 시 실패 처리
INSERT INTO PAYMENT_TRANSACTION (payment_id, account_id, merchant_id, pay_dt, pay_status_cd, total_tx_amt, cash_bal_after, cashback_bal_after)
SELECT 9000030, la.account_id, 700001, NOW(), 'FAILED_INSUFFICIENT_FUNDS', 100000, la.cash_balance, ca.cashback_balance
FROM LOCAL_ACCOUNT la
JOIN CASHBACK_ACCOUNT ca ON la.account_id = ca.account_id
WHERE la.account_id = 5000007 AND la.cash_balance < 100000;


-- [비정상 07] 지자체 모집 마감 정책 지역 결제 시도
-- 설명: 동백전 정책(9002) 상태가 '마감'일 때 결제 거절 처리
INSERT INTO PAYMENT_TRANSACTION (payment_id, account_id, merchant_id, pay_dt, pay_status_cd, total_tx_amt, cash_bal_after, cashback_bal_after)
SELECT 9000031, 5000004, 700005, NOW(), 'REJECTED_CLOSED_POLICY', 20000, la.cash_balance, ca.cashback_balance
FROM LOCAL_ACCOUNT la
JOIN CASHBACK_ACCOUNT ca ON ca.account_id = la.account_id
JOIN BUDGET_REGION br ON la.region_code = br.region_code
WHERE la.account_id = 5000004 AND br.status_code = '마감';


-- [비정상 08] 이미 취소 처리된 거래에 대한 재취소 시도
-- 설명: 이미 '취소완료' 처리된 결제건(9000002) 재취소 요청 차단
INSERT INTO PAYMENT_TRANSACTION (payment_id, account_id, merchant_id, pay_dt, pay_status_cd, total_tx_amt, cash_bal_after, cashback_bal_after)
SELECT 9000032, account_id, merchant_id, NOW(), 'ALREADY_CANCELLED', 0, cash_bal_after, cashback_bal_after
FROM PAYMENT_TRANSACTION
WHERE payment_id = 9000002 AND pay_status_cd = '취소완료';