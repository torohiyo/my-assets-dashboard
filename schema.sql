-- ============================================================
-- My Assets — 家計資産管理 データベース設計
-- Supabase (PostgreSQL) 用スキーマ
-- ============================================================

-- ── 拡張機能 ──
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. ユーザー（Supabase Auth と連携）
-- ============================================================
CREATE TABLE users (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT NOT NULL,
  display_name  TEXT NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 2. 世帯（household）
-- ============================================================
CREATE TABLE households (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT NOT NULL,              -- 例: 「松本家」
  created_by  UUID REFERENCES users(id),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. 世帯メンバー（本人 / 妻 / その他）
-- ============================================================
CREATE TABLE household_members (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_id  UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  user_id       UUID REFERENCES users(id),   -- NULLの場合は非ログインメンバー（妻など）
  member_type   TEXT NOT NULL CHECK (member_type IN ('self','spouse','other')),
  display_name  TEXT NOT NULL,               -- 例: 「本人」「妻」
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. 金融機関（証券会社・取引所・銀行など）
-- ============================================================
CREATE TABLE institutions (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name             TEXT NOT NULL,
  institution_type TEXT NOT NULL CHECK (institution_type IN (
                     'securities',       -- 証券会社
                     'crypto_exchange',  -- 暗号資産取引所
                     'bank',             -- 銀行
                     'insurance',        -- 保険
                     'pension',          -- 年金・iDeCo
                     'other'
                   )),
  icon_emoji       TEXT DEFAULT '🏦',
  is_active        BOOLEAN DEFAULT TRUE,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- デフォルト金融機関データ
INSERT INTO institutions (name, institution_type, icon_emoji) VALUES
  ('SBI証券',           'securities',      '🏦'),
  ('楽天証券',          'securities',      '📗'),
  ('マネックス証券',    'securities',      '📊'),
  ('松井証券',          'securities',      '🏛️'),
  ('住信SBIネット銀行', 'bank',            '💴'),
  ('楽天銀行',          'bank',            '🏧'),
  ('Binance',           'crypto_exchange', '₿'),
  ('bitFlyer',          'crypto_exchange', '🔶'),
  ('Bybit',             'crypto_exchange', '🟡'),
  ('OKX',               'crypto_exchange', '⚫'),
  ('SBI VCトレード',    'crypto_exchange', '🔵');

-- ============================================================
-- 5. 口座（メンバー × 金融機関）
-- ============================================================
CREATE TABLE accounts (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_member_id  UUID NOT NULL REFERENCES household_members(id) ON DELETE CASCADE,
  institution_id       UUID NOT NULL REFERENCES institutions(id),
  account_name         TEXT,              -- 例: 「特定口座」「NISA口座」
  account_number       TEXT,              -- 任意（マスキング推奨）
  currency             TEXT DEFAULT 'JPY',
  is_active            BOOLEAN DEFAULT TRUE,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 6. 資産定義（マスタ）
-- ============================================================
CREATE TABLE assets (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  symbol            TEXT,                -- 例: BTC, 7203.T, VOO
  name              TEXT NOT NULL,       -- 例: Bitcoin, トヨタ自動車, eMAXIS Slim 全世界株式
  asset_class       TEXT NOT NULL CHECK (asset_class IN (
                      'cash',            -- 現預金
                      'stock',           -- 株式
                      'fund',            -- 投資信託 / ETF
                      'bond',            -- 債券
                      'crypto_spot',     -- 暗号資産（現物）
                      'crypto_active',   -- 暗号資産（アクティブ運用）
                      'defi',            -- DeFi
                      'other'
                    )),
  asset_subclass    TEXT,               -- 例: 国内株式, 米国株式, DeFiレンディング
  currency          TEXT DEFAULT 'JPY',
  is_defi           BOOLEAN DEFAULT FALSE,
  is_active_trading BOOLEAN DEFAULT FALSE,  -- アクティブ運用フラグ
  -- 流動性区分
  liquidity_tier    TEXT CHECK (liquidity_tier IN ('high','medium','low')),
  -- 価格取得プロバイダ設定（将来API連携用）
  price_provider    TEXT,               -- 'yahoo_finance','coingecko','manual' など
  price_symbol      TEXT,               -- プロバイダ固有のシンボル
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 7. 保有ポジション（実際の保有数量・コスト）
-- ============================================================
CREATE TABLE holdings (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id   UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  asset_id     UUID NOT NULL REFERENCES assets(id),
  quantity     NUMERIC(30,10) NOT NULL,         -- 保有数量
  average_cost NUMERIC(20,4),                   -- 平均取得単価
  total_cost   NUMERIC(20,4),                   -- 取得総額
  currency     TEXT DEFAULT 'JPY',
  notes        TEXT,
  is_active    BOOLEAN DEFAULT TRUE,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 8. 取引履歴
-- ============================================================
CREATE TABLE transactions (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  holding_id       UUID REFERENCES holdings(id),
  account_id       UUID NOT NULL REFERENCES accounts(id),
  asset_id         UUID NOT NULL REFERENCES assets(id),
  transaction_type TEXT NOT NULL CHECK (transaction_type IN (
                     'buy',           -- 購入
                     'sell',          -- 売却
                     'dividend',      -- 配当・分配金
                     'stake_reward',  -- ステーキング報酬
                     'defi_reward',   -- DeFi報酬
                     'transfer_in',   -- 入金
                     'transfer_out'   -- 出金
                   )),
  quantity         NUMERIC(30,10) NOT NULL,
  price            NUMERIC(20,4) NOT NULL,       -- 取引単価
  total_amount     NUMERIC(20,4) NOT NULL,       -- 取引総額
  fee              NUMERIC(20,4) DEFAULT 0,      -- 手数料
  transaction_date DATE NOT NULL,
  notes            TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 9. 価格履歴（時系列データ）
-- VaR・ボラティリティ計算の基礎データ
-- ============================================================
CREATE TABLE price_history (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  asset_id    UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  price_date  DATE NOT NULL,
  price       NUMERIC(20,6) NOT NULL,
  currency    TEXT DEFAULT 'JPY',
  source      TEXT DEFAULT 'manual',   -- 'api','manual'
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (asset_id, price_date)
);

-- インデックス（パフォーマンス最適化）
CREATE INDEX idx_price_history_asset_date ON price_history (asset_id, price_date DESC);

-- ============================================================
-- 10. ポートフォリオスナップショット（日次集計）
-- ============================================================
CREATE TABLE portfolio_snapshots (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_member_id  UUID NOT NULL REFERENCES household_members(id),
  snapshot_date        DATE NOT NULL,
  total_value          NUMERIC(20,4),          -- 評価総額
  total_cost           NUMERIC(20,4),          -- 取得総額
  unrealized_pnl       NUMERIC(20,4),          -- 含み損益
  -- 資産クラス別内訳（JSON）
  asset_class_breakdown JSONB,
  -- 例: {"cash":3000000,"fund":6156000,"crypto_spot":2250000,"crypto_active":400000}
  created_at           TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (household_member_id, snapshot_date)
);

-- ============================================================
-- 11. リスク指標（VaR・ボラティリティ等）
-- ============================================================
CREATE TABLE risk_metrics (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_member_id  UUID REFERENCES household_members(id),
  calculated_at        TIMESTAMPTZ DEFAULT NOW(),
  -- VaR（パラメトリック法）
  var_95_1day          NUMERIC(20,4),   -- 1日VaR 95%
  var_99_1day          NUMERIC(20,4),   -- 1日VaR 99%
  var_95_1month        NUMERIC(20,4),   -- 1ヶ月VaR 95%
  var_99_1month        NUMERIC(20,4),   -- 1ヶ月VaR 99%
  -- CVaR（条件付き期待損失）
  cvar_99              NUMERIC(20,4),
  -- ボラティリティ
  portfolio_volatility NUMERIC(10,6),   -- 年率ボラティリティ
  daily_volatility     NUMERIC(10,6),   -- 日次ボラティリティ
  -- その他指標
  sharpe_ratio         NUMERIC(10,4),
  expected_return      NUMERIC(10,6),   -- 期待収益率（年率）
  max_drawdown         NUMERIC(10,6),   -- 推計最大ドローダウン
  -- 計算設定
  calculation_method   TEXT DEFAULT 'parametric',  -- 'parametric','historical','monte_carlo'
  lookback_days        INTEGER DEFAULT 252,
  confidence_level     NUMERIC(5,4) DEFAULT 0.95,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Row Level Security（RLS）
-- ============================================================
ALTER TABLE users             ENABLE ROW LEVEL SECURITY;
ALTER TABLE households        ENABLE ROW LEVEL SECURITY;
ALTER TABLE household_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts          ENABLE ROW LEVEL SECURITY;
ALTER TABLE holdings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE price_history     ENABLE ROW LEVEL SECURITY;
ALTER TABLE portfolio_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE risk_metrics      ENABLE ROW LEVEL SECURITY;

-- 自分のデータのみアクセス可能
CREATE POLICY "users_own_data" ON users
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "household_access" ON households
  FOR ALL USING (created_by = auth.uid());

CREATE POLICY "members_access" ON household_members
  FOR ALL USING (
    household_id IN (SELECT id FROM households WHERE created_by = auth.uid())
  );

CREATE POLICY "accounts_access" ON accounts
  FOR ALL USING (
    household_member_id IN (
      SELECT hm.id FROM household_members hm
      JOIN households h ON h.id = hm.household_id
      WHERE h.created_by = auth.uid()
    )
  );

CREATE POLICY "holdings_access" ON holdings
  FOR ALL USING (
    account_id IN (
      SELECT a.id FROM accounts a
      JOIN household_members hm ON hm.id = a.household_member_id
      JOIN households h ON h.id = hm.household_id
      WHERE h.created_by = auth.uid()
    )
  );

CREATE POLICY "transactions_access" ON transactions
  FOR ALL USING (
    account_id IN (
      SELECT a.id FROM accounts a
      JOIN household_members hm ON hm.id = a.household_member_id
      JOIN households h ON h.id = hm.household_id
      WHERE h.created_by = auth.uid()
    )
  );

CREATE POLICY "price_history_read" ON price_history
  FOR SELECT USING (true);  -- 価格データは全ユーザー参照可

CREATE POLICY "snapshots_access" ON portfolio_snapshots
  FOR ALL USING (
    household_member_id IN (
      SELECT hm.id FROM household_members hm
      JOIN households h ON h.id = hm.household_id
      WHERE h.created_by = auth.uid()
    )
  );

CREATE POLICY "risk_metrics_access" ON risk_metrics
  FOR ALL USING (
    household_member_id IN (
      SELECT hm.id FROM household_members hm
      JOIN households h ON h.id = hm.household_id
      WHERE h.created_by = auth.uid()
    )
  );

-- ============================================================
-- ビュー：ポートフォリオ評価（VIEWs）
-- ============================================================

-- 保有ポジション + 最新価格の結合ビュー
CREATE VIEW v_holdings_with_price AS
SELECT
  h.id,
  h.account_id,
  h.asset_id,
  h.quantity,
  h.average_cost,
  h.total_cost,
  a.name        AS asset_name,
  a.symbol,
  a.asset_class,
  a.is_defi,
  a.is_active_trading,
  a.liquidity_tier,
  ph.price      AS current_price,
  ph.price_date AS price_date,
  -- 評価額・含み損益
  h.quantity * ph.price                           AS current_value,
  h.quantity * ph.price - h.total_cost            AS unrealized_pnl,
  CASE WHEN h.total_cost > 0
    THEN (h.quantity * ph.price - h.total_cost) / h.total_cost * 100
    ELSE 0
  END                                             AS pnl_rate
FROM holdings h
JOIN assets a ON a.id = h.asset_id
LEFT JOIN LATERAL (
  SELECT price, price_date FROM price_history
  WHERE asset_id = h.asset_id
  ORDER BY price_date DESC LIMIT 1
) ph ON true
WHERE h.is_active = true;

-- ============================================================
-- VaR計算に必要なデータ整理メモ
-- ============================================================
/*
  【VaR計算式（パラメトリック法）】

  1. 日次リターン（各資産）
     r_t = (P_t - P_{t-1}) / P_{t-1}

  2. 年率ボラティリティ
     σ_annual = std(r_daily) × √252

  3. ポートフォリオ分散
     σ²_p = Σ_i Σ_j (w_i × w_j × σ_i × σ_j × ρ_ij)

  4. VaR（1日、95%信頼水準）
     VaR_1day = z_0.95 × σ_daily × Portfolio_Value
     z_0.95 = 1.645

  5. VaR（Tデイ、95%）
     VaR_T = VaR_1day × √T

  【資産クラス別 想定ボラティリティ（年率）】
  ┌────────────────────────┬──────────┐
  │ 資産クラス              │ σ_annual │
  ├────────────────────────┼──────────┤
  │ 現預金 (cash)           │  0.1%    │
  │ 株式 (stock)            │ 18.0%    │
  │ 投資信託/ETF (fund)     │ 15.0%    │
  │ 債券 (bond)             │  5.0%    │
  │ 暗号資産現物 (crypto_s) │ 75.0%    │
  │ 暗号資産アクティブ      │ 90.0%    │
  │ DeFi                    │ 80.0%    │
  └────────────────────────┴──────────┘

  【想定相関係数（主要ペア）】
  fund     ↔ stock       : 0.95
  fund     ↔ crypto_spot : 0.20
  crypto_s ↔ crypto_a    : 0.90
  crypto_s ↔ defi        : 0.85
  bond     ↔ stock       : -0.10

  【想定期待収益率（年率）】
  cash=0.1%, stock=8%, fund=7%, bond=3%,
  crypto_spot=30%, crypto_active=40%, defi=25%

  【将来のAPI連携候補】
  - 株式・ETF・投信: Yahoo Finance API / J-Quants (日本株)
  - 暗号資産:        CoinGecko API / Binance API
  - 為替:            Open Exchange Rates / ExchangeRate-API
  - DeFi:            Zapper.fi API / DeBank API

  【価格プロバイダ abstraction layer】
  price_provider フィールドで差し替え可能に設計済み:
    'coingecko'     → CoinGecko REST API
    'yahoo_finance' → Yahoo Finance API
    'jquants'       → J-Quants (日本株)
    'manual'        → 手動入力（price_historyテーブル直接）
*/
