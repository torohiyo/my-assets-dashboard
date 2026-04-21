# My Assets — 家計資産管理ダッシュボード

## 概要
家計の余剰資金による資産運用を管理するダッシュボード。本人・妻・世帯合算の3ビューで資産を管理し、VaRによるリスク分析まで対応。

## スクリーン一覧

| 画面 | 機能 |
|------|------|
| ダッシュボード | 評価総額・含み損益・**流動性の高い資産**・月次変化 |
| 保有資産 | 金融機関別アコーディオン表示（SBI証券/Binanceなど） |
| 資産登録 | 手入力フォーム（金融機関・資産クラス・数量・取得単価） |
| 資産配分 | 資産クラス別 / 暗号資産内訳（現物・アクティブ・DeFi）/ 流動性別 |
| リスク分析 | VaRスライダー（保守的〜積極的）・期待収益シミュレーション |
| 損益推移 | 12ヶ月ポートフォリオ推移チャート・銘柄別損益テーブル |
| 収益見通し | **運用益のみ**（配当・ステーキング・キャピタルゲイン） |
| リバランス | 現在配分 vs 目標配分・優先アクション |

## 使い方

### 1. そのまま開く（デモモード）
`index.html` をブラウザで開くだけで動作します。データはブラウザのlocalStorageに保存されます。

### 2. Supabase連携（クラウド保存）
1. [supabase.com](https://supabase.com) でプロジェクトを作成
2. `schema.sql` をSupabaseのSQL Editorで実行
3. ダッシュボードの「資産登録」→「Supabase接続設定」にURLとAnon Keyを入力
4. 以降のデータはSupabase（PostgreSQL）に保存されます

## データ設計
`schema.sql` を参照。主要テーブル：

```
users → households → household_members
                          ↓
                       accounts → holdings → transactions
                                      ↓
assets ←──────────────────────────────┘
  ↓
price_history（時系列価格・VaR計算の基礎データ）

portfolio_snapshots（日次スナップショット）
risk_metrics（VaR・ボラティリティ等）
```

## VaR計算の考え方

**パラメトリック法（正規分布仮定）**

```
日次リターン:        r_t = (P_t - P_{t-1}) / P_{t-1}
年率ボラティリティ:  σ = std(r_daily) × √252
1ヶ月VaR(95%):      1.645 × σ_daily × √22 × 評価総額
```

想定ボラティリティ（年率）：
- 現預金 0.1% / 投資信託 15% / 暗号資産現物 75% / アクティブ運用 90%

## 将来API連携ポイント

assets テーブルの `price_provider` フィールドで差し替え可能：
- `coingecko` → CoinGecko API（BTC/ETH等）
- `yahoo_finance` → 米国株・ETF
- `jquants` → 日本株（J-Quants API）
- `manual` → 手動入力（デフォルト）
