# woori-won-database
우리 WON 데이베이스 실습

# 지역화폐 통합 플랫폼 데이터베이스

본 저장소는 여러 지역화폐를 하나의 통합 지갑처럼 제공하는 **지역화폐 통합 플랫폼**의 데이터베이스 스키마, 마이그레이션 스크립트 및 설계 문서를 관리합니다. 금융성 거래의 무결성, 감사 가능성, 그리고 개인정보 보호를 최우선으로 설계되었습니다.

## 1. 핵심 목표 및 특징

*   **통합 지갑 UX & 독립적 원장 관리:** 앱 사용자에게는 하나의 통합 지갑 화면을 제공하지만, 데이터베이스 내부적으로는 서울, 경기 등 지역별 계좌와 원장을 완전히 독립적으로 분리하여 관리합니다.
*   **투명한 거래 추적:** 충전, 결제, 캐시백 적립/사용, 예산 집행, 개인 한도, 가맹점 정산 등 모든 자금의 흐름을 추적 가능하도록 설계했습니다.
*   **무결성 및 성능 최적화:** 3정규형을 기본 지향하되, 조회 성능과 동시성 처리가 핵심인 잔액 및 집계 데이터는 선택적으로 비정규화하여 관리합니다.

---

## 2. ERD (Entity-Relationship Diagram)

전체 데이터베이스 모델링 및 관계도는 제공된 **ERD.pdf** 파일의 시각적 구조를 따르며, 아래 다이어그램은 전체 13개 테이블의 핵심 관계를 요약한 구조입니다.

```mermaid
erDiagram
    USERS ||--o{ LOCAL_ACCOUNT : owns
    USERS ||--o{ USER_LIMIT_MANAGEMENT : has
    USERS ||--o{ BUDGET_REGION_APPLY : applies
    USERS ||--o{ CHANNEL_USER_LOG : accesses

    LOCAL_ACCOUNT ||--o| CASHBACK_ACCOUNT : has
    LOCAL_ACCOUNT ||--o{ RECHARGE_TRANSACTION : recharges
    LOCAL_ACCOUNT ||--o{ PAYMENT_TRANSACTION : pays

    MERCHANT ||--o{ PAYMENT_TRANSACTION : accepts
    MERCHANT ||--o{ SETTLEMENT_DAILY : settles

    BUDGET_MASTER ||--o{ BUDGET_REGION : funds
    BUDGET_REGION ||--o{ BUDGET_REGION_APPLY : receives

    PAYMENT_TRANSACTION ||--o| EXTERNAL_TELEGRAM_LOG : maps

## 3. 주요 설계 의사결정

*   **사용자와 계좌 분리 (1:N):** `USERS` 테이블과 `LOCAL_ACCOUNT` 테이블을 1:N으로 설계하여, 사용자가 여러 지역의 계좌를 보유할 수 있도록 구성했습니다. 결제 시 타 지역 잔액에 영향을 미치지 않습니다.
*   **지역·정책별 캐시백률 적용:** `BUDGET_REGION.cashback_rate` 컬럼(예: `10.00`)을 통해 지역/연도/정책별 유연한 캐시백 비율 조절이 가능합니다. 실제 적립액은 기본 산정액, 개인 잔여 한도, 지역 가용 예산 중 최솟값(MIN)으로 결정됩니다.
*   **캐시백 우선 차감 원칙:** 결제 시 `PAYMENT_TRANSACTION`에서 캐시백을 우선 차감(`use_cashback_amt`)하고, 부족분을 실충전금(`pay_cash_amt`)에서 차감합니다[cite: 1]. 이 과정은 단일 트랜잭션으로 처리되어 롤백을 보장합니다.
*   **예산 및 인원 제한:** `BUDGET_MASTER`에서 총예산과 집행액을 관리하며, 하위 `BUDGET_REGION`에서 선착순 참여 인원(최대/현재 인원)을 통제합니다.
*   **개인정보 보호:** 주민등록번호는 암호화(`rrn_enc`) 및 해시(`rrn_hash`)로 분리 저장하며, `transaction_end_date`를 통해 신용정보법 기준 5년 보존 및 파기 정책을 준수합니다.

---

## 4. 기술 스택 및 개발 환경

*   **RDBMS:** MySQL 
*   **DB Client:** DBeaver
*   **Data Types:** 금액은 `NUMERIC(15,0)` (대규모 예산은 18,0), 거래 시각은 밀리초 단위 정밀도인 `TIMESTAMP(3)`을 기본으로 사용합니다.

---

## 5. 데이터베이스 구축 가이드

협업 시 개인이 DBeaver에서 임의로 스키마를 수정하지 않으며, 반드시 Git과 마이그레이션 디렉토리의 SQL 스크립트를 통해 구조를 반영해야 합니다.

### 권장 테이블 생성 순서 (FK 의존성 고려)

테이블은 반드시 부모 테이블부터 자식 테이블 순서로 생성해야 외래키(FK) 참조 오류가 발생하지 않습니다.

1. `USERS` (고객 정보)
2. `MERCHANT` (가맹점 정보)
3. `BUDGET_MASTER` (지역별 총예산)
4. `LOCAL_ACCOUNT` (사용자 지역 계좌)
5. `BUDGET_REGION` (지역 세부 정책)
6. `CASHBACK_ACCOUNT` (계좌별 캐시백)
7. `USER_LIMIT_MANAGEMENT` (월 누적 한도)
8. `BUDGET_REGION_APPLY` (정책 신청 내역)
9. `RECHARGE_TRANSACTION` (충전 거래 이력)
10. `PAYMENT_TRANSACTION` (결제 거래 이력)
11. `SETTLEMENT_DAILY` (일일 정산 내역)
12. `CHANNEL_USER_LOG` (앱 접속 로그)
13. `EXTERNAL_TELEGRAM_LOG` (대외 연계 로그)

