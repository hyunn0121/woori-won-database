-- 데이터베이스가 없다면 생성 및 사용 지정 (필요시 주석 해제)
-- CREATE DATABASE IF NOT EXISTS local_currency DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
-- USE local_currency;

-- ==========================================
-- 1. USERS (최상위 부모 - FK 없음)
-- ==========================================
CREATE TABLE USERS (
    user_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '고객 고유 식별자',
    rrn_enc VARCHAR(255) COMMENT '주민등록번호 암호문',
    rrn_hash VARCHAR(255) COMMENT '주민번호 검색용 해시',
    user_name VARCHAR(100) NOT NULL COMMENT '고객명',
    status_code VARCHAR(20) NOT NULL COMMENT '상태 (정상/거래종료/분리보관)',
    transaction_end_date DATE COMMENT '거래종료일 (신용정보법 5년 파기용)',
    reg_dt DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '등록일시'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='고객 원장';

-- ==========================================
-- 2. BUDGET_MASTER (최상위 부모 - FK 없음, 복합 PK)
-- ==========================================
CREATE TABLE BUDGET_MASTER (
    region_code VARCHAR(20) NOT NULL COMMENT '지자체 지역 코드',
    target_year VARCHAR(4) NOT NULL COMMENT '해당 연도 (YYYY)',
    total_budget DECIMAL(15, 2) NOT NULL DEFAULT 0.00 COMMENT '지자체 총 캐시백 예산',
    used_budget DECIMAL(15, 2) NOT NULL DEFAULT 0.00 COMMENT '현재 집행된 캐시백 총액',
    available_budget DECIMAL(15, 2) NOT NULL DEFAULT 0.00 COMMENT '남은 예산 잔액',
    upd_dt DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '최종 갱신일시',
    PRIMARY KEY (region_code, target_year)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='지자체 예산 마스터';

-- ==========================================
-- 3. MERCHANT (최상위 부모 - FK 없음)
-- ==========================================
CREATE TABLE MERCHANT (
    merchant_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '가맹점 ID',
    biz_no VARCHAR(20) NOT NULL COMMENT '사업자등록번호',
    merchant_name VARCHAR(100) NOT NULL COMMENT '가맹점명',
    category_code VARCHAR(20) COMMENT '업종 코드',
    annual_revenue DECIMAL(15, 2) DEFAULT 0.00 COMMENT '연 매출액 (30억 제한 검증용)',
    status_code VARCHAR(20) NOT NULL COMMENT '가맹점 상태',
    reg_dt DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '등록일시'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='가맹점 원장';

-- ==========================================
-- 4. LOCAL_ACCOUNT (USERS 참조: user_id)
-- ==========================================
CREATE TABLE LOCAL_ACCOUNT (
    account_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '지역화폐 계좌 번호',
    user_id BIGINT NOT NULL COMMENT '고객 ID',
    region_code VARCHAR(20) NOT NULL COMMENT '지자체 지역 코드',
    cash_balance DECIMAL(15, 2) NOT NULL DEFAULT 0.00 COMMENT '실 충전금 잔액 (원금)',
    status_code VARCHAR(20) NOT NULL COMMENT '계좌 상태',
    reg_dt DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '개설일시',
    CONSTRAINT FK_LOCAL_ACCOUNT_USERS FOREIGN KEY (user_id) REFERENCES USERS (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='지역화폐 계좌';

-- ==========================================
-- 5. CASHBACK_ACCOUNT (LOCAL_ACCOUNT 참조: account_id)
-- ==========================================
CREATE TABLE CASHBACK_ACCOUNT (
    cashback_account_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '캐시백 원장 ID',
    account_id BIGINT NOT NULL UNIQUE COMMENT '지역화폐 계좌 ID (1:1 관계)',
    cashback_balance DECIMAL(15, 2) NOT NULL DEFAULT 0.00 COMMENT '현재 사용 가능한 캐시백 잔액',
    total_accumulated_amt DECIMAL(15, 2) NOT NULL DEFAULT 0.00 COMMENT '누적 적립 총액',
    last_updated_dt DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '최종 변동일시',
    CONSTRAINT FK_CASHBACK_ACCOUNT_LOCAL_ACCOUNT FOREIGN KEY (account_id) REFERENCES LOCAL_ACCOUNT (account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='캐시백 원장';

-- ==========================================
-- 6. BUDGET_REGION (BUDGET_MASTER 참조: region_code, target_year)
-- ==========================================
CREATE TABLE BUDGET_REGION (
    policy_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '정책/모집 ID',
    region_code VARCHAR(20) NOT NULL COMMENT '지자체 코드',
    target_year VARCHAR(4) NOT NULL COMMENT '대상 연도 (YYYY)',
    policy_name VARCHAR(100) NOT NULL COMMENT '정책명',
    max_participants INT DEFAULT 0 COMMENT '최대 제한 인원수',
    current_participants INT DEFAULT 0 COMMENT '현재 참여 인원수',
    individual_monthly_limit DECIMAL(15, 2) DEFAULT 0.00 COMMENT '개인별 월 결제 한도',
    individual_cashback_limit DECIMAL(15, 2) DEFAULT 0.00 COMMENT '개인별 월 캐시백 한도',
    status_code VARCHAR(20) NOT NULL COMMENT '상태 (모집중/마감)',
    start_date DATE COMMENT '시작일',
    end_date DATE COMMENT '종료일',
    CONSTRAINT FK_BUDGET_REGION_BUDGET_MASTER FOREIGN KEY (region_code, target_year)
        REFERENCES BUDGET_MASTER (region_code, target_year)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='예산 기반 인원 제약/정책';

-- ==========================================
-- 7. BUDGET_REGION_APPLY (USERS, BUDGET_REGION 참조)
-- ==========================================
CREATE TABLE BUDGET_REGION_APPLY (
    apply_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '신청 ID',
    policy_id BIGINT NOT NULL COMMENT '정책 ID',
    user_id BIGINT NOT NULL COMMENT '고객 ID',
    apply_status VARCHAR(20) NOT NULL COMMENT '신청상태',
    applied_dt DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '신청 일시',
    CONSTRAINT FK_BUDGET_REGION_APPLY_POLICY FOREIGN KEY (policy_id) REFERENCES BUDGET_REGION (policy_id),
    CONSTRAINT FK_BUDGET_REGION_APPLY_USERS FOREIGN KEY (user_id) REFERENCES USERS (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='인원제한 정책 모집 신청';

-- ==========================================
-- 8. USER_LIMIT_MANAGEMENT (USERS 참조: user_id)
-- ==========================================
CREATE TABLE USER_LIMIT_MANAGEMENT (
    limit_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '한도 관리 ID',
    user_id BIGINT NOT NULL COMMENT '고객 ID',
    target_month VARCHAR(6) NOT NULL COMMENT '대상 월 (YYYYMM)',
    monthly_pay_amt DECIMAL(15, 2) DEFAULT 0.00 COMMENT '당월 누적 실결제 금액',
    monthly_earned_cashback DECIMAL(15, 2) DEFAULT 0.00 COMMENT '당월 누적 받은 캐시백',
    upd_dt DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '최종 갱신일시',
    CONSTRAINT FK_USER_LIMIT_USERS FOREIGN KEY (user_id) REFERENCES USERS (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='개인별 한도 관리';

-- ==========================================
-- 9. RECHARGE_TRANSACTION (LOCAL_ACCOUNT 참조: account_id)
-- ==========================================
CREATE TABLE RECHARGE_TRANSACTION (
    recharge_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '충전 거래 고유 번호',
    account_id BIGINT NOT NULL COMMENT '지역화폐 계좌 ID',
    recharge_dt DATETIME(3) DEFAULT CURRENT_TIMESTAMP(3) COMMENT '충전일시 (DATETIME3)',
    recharge_amt DECIMAL(15, 2) NOT NULL COMMENT '충전 금액',
    recharge_method_cd VARCHAR(20) NOT NULL COMMENT '충전 수단',
    cash_yn VARCHAR(1) DEFAULT 'N' COMMENT '현금여부 (Y/N - 특금법 CTR용)',
    bal_after DECIMAL(15, 2) NOT NULL COMMENT '충전 후 실 충전금 잔액',
    device_info VARCHAR(255) COMMENT '단말/매체 정보',
    retain_until DATE COMMENT '보존만료일 (5년 법적 보관)',
    CONSTRAINT FK_RECHARGE_TX_ACCOUNT FOREIGN KEY (account_id) REFERENCES LOCAL_ACCOUNT (account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='충전 거래 내역';

-- ==========================================
-- 10. PAYMENT_TRANSACTION (LOCAL_ACCOUNT, MERCHANT 참조)
-- ==========================================
CREATE TABLE PAYMENT_TRANSACTION (
    payment_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '결제 거래 고유 번호',
    account_id BIGINT NOT NULL COMMENT '지역화폐 계좌 ID',
    merchant_id BIGINT NOT NULL COMMENT '가맹점 ID',
    pay_dt DATETIME(3) DEFAULT CURRENT_TIMESTAMP(3) COMMENT '결제일시 (DATETIME3)',
    pay_status_cd VARCHAR(20) NOT NULL COMMENT '결제 상태',
    total_tx_amt DECIMAL(15, 2) NOT NULL COMMENT '총 결제 요청 금액',
    use_cashback_amt DECIMAL(15, 2) DEFAULT 0.00 COMMENT '우선 차감된 캐시백 사용액',
    pay_cash_amt DECIMAL(15, 2) DEFAULT 0.00 COMMENT '차감된 실현금 결제액',
    earn_cashback_amt DECIMAL(15, 2) DEFAULT 0.00 COMMENT '신규 적립 캐시백',
    cash_bal_after DECIMAL(15, 2) NOT NULL COMMENT '결제 후 실충전금 잔액',
    cashback_bal_after DECIMAL(15, 2) NOT NULL COMMENT '결제 후 캐시백 잔액',
    device_info VARCHAR(255) COMMENT '단말/매체 정보',
    retain_until DATE COMMENT '보존만료일 (5년 법적 보관)',
    CONSTRAINT FK_PAYMENT_TX_ACCOUNT FOREIGN KEY (account_id) REFERENCES LOCAL_ACCOUNT (account_id),
    CONSTRAINT FK_PAYMENT_TX_MERCHANT FOREIGN KEY (merchant_id) REFERENCES MERCHANT (merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='결제 거래 내역';

-- ==========================================
-- 11. SETTLEMENT_DAILY (MERCHANT 참조: merchant_id)
-- ==========================================
CREATE TABLE SETTLEMENT_DAILY (
    settlement_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '정산 ID',
    settlement_date DATE NOT NULL COMMENT '정산 일자',
    merchant_id BIGINT NOT NULL COMMENT '가맹점 ID',
    total_sales_amt DECIMAL(15, 2) DEFAULT 0.00 COMMENT '총 결제 매출액',
    fee_amt DECIMAL(15, 2) DEFAULT 0.00 COMMENT '수수료 금액',
    actual_payout_amt DECIMAL(15, 2) DEFAULT 0.00 COMMENT '실지급액',
    payout_status VARCHAR(20) NOT NULL COMMENT '지급 상태',
    payout_dt DATETIME COMMENT '지급 완료 일시',
    CONSTRAINT FK_SETTLEMENT_MERCHANT FOREIGN KEY (merchant_id) REFERENCES MERCHANT (merchant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='일일 정산 내역';

-- ==========================================
-- 12-1. CHANNEL_USER_LOG (USERS 참조: user_id)
-- ==========================================
CREATE TABLE CHANNEL_USER_LOG (
    log_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '로그 ID',
    user_id BIGINT NOT NULL COMMENT '고객 ID',
    access_dt DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '접속 일시',
    access_ip VARCHAR(45) COMMENT '접속 IP 주소',
    device_id VARCHAR(100) COMMENT '등록 기기 식별값',
    login_success_yn VARCHAR(1) DEFAULT 'Y' COMMENT '로그인 성공 여부',
    CONSTRAINT FK_CHANNEL_LOG_USERS FOREIGN KEY (user_id) REFERENCES USERS (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='앱 접속 기록';

-- ==========================================
-- 12-2. EXTERNAL_TELEGRAM_LOG (PAYMENT_TRANSACTION 참조: payment_id)
-- ==========================================
CREATE TABLE EXTERNAL_TELEGRAM_LOG (
    telegram_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '전문 ID',
    payment_id BIGINT NOT NULL COMMENT '결제 거래 ID',
    external_org_code VARCHAR(20) NOT NULL COMMENT '연계 기관 코드',
    telegram_type VARCHAR(20) NOT NULL COMMENT '전문 종별',
    response_code VARCHAR(10) COMMENT '응답 코드',
    transmit_dt DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '송수신 일시',
    CONSTRAINT FK_TELEGRAM_LOG_PAYMENT FOREIGN KEY (payment_id) REFERENCES PAYMENT_TRANSACTION (payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='대외 연계 전문 매핑 로그';

