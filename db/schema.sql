-- =====================================================================
-- シーシャバー「ひふみ」店舗管理サブシステム
-- スキーマ定義 (Version 1.0 FIX)
-- 対応ドキュメント: docs/02_データベース設計書.pdf 5章
--
-- 実行方法: Supabase ダッシュボード > SQL Editor に貼り付けて実行
-- =====================================================================

-- 拡張(gen_random_uuid用)
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ---------------------------------------------------------------------
-- マスタ系
-- ---------------------------------------------------------------------

-- 卓マスタ。ダッシュボードの描画座標を保持する。
CREATE TABLE tables (
  id            SERIAL PRIMARY KEY,
  table_number  INTEGER     NOT NULL UNIQUE,
  label         VARCHAR(20) NOT NULL,
  capacity      INTEGER,
  pos_x         INTEGER     NOT NULL,  -- 基準キャンバス450x490上の座標
  pos_y         INTEGER     NOT NULL,
  is_active     BOOLEAN     NOT NULL DEFAULT true
);

-- スタッフマスタ。V1では権限差を設けない。
CREATE TABLE staff (
  id            SERIAL PRIMARY KEY,
  login_id      VARCHAR(50)  NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,  -- bcryptハッシュ。平文を入れないこと
  name          VARCHAR(100) NOT NULL,
  is_active     BOOLEAN      NOT NULL DEFAULT true
);

-- 商品マスタ。シーシャは「プラン」を1商品として扱い、フレーバーは口頭で受ける。
--
-- 【価格の扱い】price は「税込価格」を保持する。店頭メニューが総額表示であり、
-- 税抜で保持して表示時に税込へ換算すると端数処理で printed menu と1円ずれる
-- ケースがあるため(例: 税込1,000円は floor(b*1.1) では表現できない)。
-- 表示はこの値をそのまま出す。税額の内訳計算は本システムの対象外(レジ側の責務)。
--
-- 【価格変動商品の扱い】GUESTジン等、仕入れにより価格が変わる商品は、
-- 都度の手入力ではなく price を直接UPDATEして当日の価格に固定する運用とする
-- (スタッフ用商品管理画面から編集する。手入力(is_custom)は本当にメニュー外の
-- 一品や口頭注文にのみ使う)。
CREATE TABLE products (
  id          SERIAL PRIMARY KEY,
  name        VARCHAR(100)  NOT NULL,
  category    VARCHAR(50)   NOT NULL,   -- 画面のタブ(シーシャ/コーヒー・ティー/…)
  subcategory VARCHAR(50),              -- タブ内の見出し(Coffee/Tea/焼酎ベース/…)
  price       INTEGER       NOT NULL CHECK (price >= 0),   -- 税込
  is_sold_out BOOLEAN       NOT NULL DEFAULT false,
  sort_order  INTEGER       NOT NULL DEFAULT 0
);


-- ---------------------------------------------------------------------
-- トランザクション系
-- ---------------------------------------------------------------------

-- 伝票。開栓のたびに1レコード作成され、session_tokenが再発行される。
--
-- 【呼び出し理由について】is_calling は「呼び出し中かどうか」のみを保持し、
-- 理由(炭の交換/ドリンクのおかわり/お会計/その他)は call_reason に持つ。
-- 呼び出しの発生・解消そのものの履歴は残らないため、集計が要る場合は
-- 下記 call_events を参照する。
CREATE TABLE orders (
  id                SERIAL PRIMARY KEY,
  table_id          INTEGER     NOT NULL REFERENCES tables(id),
  session_token     UUID        NOT NULL DEFAULT gen_random_uuid(),
  status            VARCHAR(20) NOT NULL DEFAULT 'Active'
                    CHECK (status IN ('Active','Deactivated')),
  checkout_staff_id INTEGER     REFERENCES staff(id),  -- 日次バッチ由来のクリアはNULLのまま
  is_calling        BOOLEAN     NOT NULL DEFAULT false,
  call_reason       VARCHAR(20) CHECK (call_reason IN ('charcoal','drink','checkout','other')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at         TIMESTAMPTZ
);

-- 同一卓にActiveな伝票を1件しか作れないようにする(開栓の二重実行防止)
CREATE UNIQUE INDEX orders_one_active_per_table
  ON orders (table_id) WHERE status = 'Active';

CREATE INDEX orders_status_idx ON orders (status);

-- 注文明細。価格(税込)は注文時点の値をスナップショットとして保持する。
CREATE TABLE order_items (
  id          SERIAL PRIMARY KEY,
  order_id    INTEGER      NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id  INTEGER      REFERENCES products(id),  -- 手入力時はNULL
  is_custom   BOOLEAN      NOT NULL DEFAULT false,
  custom_name VARCHAR(100),
  price       INTEGER      NOT NULL CHECK (price >= 0),   -- 税込。注文時点のスナップショット
  quantity    INTEGER      NOT NULL DEFAULT 1 CHECK (quantity > 0),
  status      VARCHAR(20)  NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending','served','cancelled')),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  -- 通常商品ならproduct_id必須、カスタムならcustom_name必須
  CONSTRAINT order_items_source_chk CHECK (
    (is_custom = false AND product_id  IS NOT NULL)
    OR
    (is_custom = true  AND custom_name IS NOT NULL)
  )
);

CREATE INDEX order_items_order_status_idx ON order_items (order_id, status);

-- 呼び出しの簡易ログ。「炭の交換が多い時間帯」等の後追い集計と、
-- 呼び出しへの応答時間の把握のためだけの最小限のテーブル。
-- 呼び出し発生時(callStaff)に1行INSERTし、解消時(対応しました/会計クリア)に
-- resolved_at をUPDATEする。個別のUI・APIは持たず、必要なときにSQLで
-- 集計する運用を想定する(例: 理由別件数、平均対応時間)。
CREATE TABLE call_events (
  id          SERIAL PRIMARY KEY,
  order_id    INTEGER      NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  reason      VARCHAR(20)  NOT NULL CHECK (reason IN ('charcoal','drink','checkout','other')),
  called_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

CREATE INDEX call_events_order_idx ON call_events (order_id);


-- ---------------------------------------------------------------------
-- 行レベルセキュリティ(RLS)
--
-- RLSを有効化したうえでポリシーを一切作成しないことで、
-- Anon Key / Authenticated Key からのアクセスは全て拒否される。
-- Service Role Key はRLSをbypassするため、Backendのみが通過できる。
-- ---------------------------------------------------------------------
ALTER TABLE tables      ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff       ENABLE ROW LEVEL SECURITY;
ALTER TABLE products    ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE call_events ENABLE ROW LEVEL SECURITY;
