-- Menggunakan CTE untuk efisiensi dan pembacaan yang lebih baik
WITH daily_sales AS (
    SELECT 
        category,
        SUM(qty) AS total_qty,
        SUM(total_net) AS total_gmv
    FROM gacoan_transactions
    WHERE timestamp >= '2026-04-08 00:00:00' -- Optimasi: Filter waktu di awal
    GROUP BY category
)
SELECT 
    category,
    total_qty,
    total_gmv,
    -- Menghitung estimasi Gross Profit (asumsi margin 60%)
    ROUND(total_gmv * 0.6, 2) AS estimated_gross_profit,
    -- Menghitung kontribusi persentase terhadap total GMV
    ROUND(total_gmv * 100.0 / SUM(total_gmv) OVER(), 2) AS gmv_contribution_pct
FROM daily_sales
ORDER BY total_gmv DESC;

-- Query untuk menghitung rata-rata waktu makan per jenis meja
SELECT 
    area,
    COUNT(table_id) AS total_tables_used,
    AVG(dwell_time_min) AS avg_stay_duration,
    MAX(dwell_time_min) AS longest_stay,
    MIN(dwell_time_min) AS shortest_stay
FROM gacoan_table_turnover
WHERE status = 'Completed' -- Optimasi: Hanya hitung transaksi yang sudah selesai
GROUP BY area
HAVING AVG(dwell_time_min) > 0
ORDER BY avg_stay_duration ASC;

SELECT 
    customer_segment,
    COUNT(DISTINCT trx_id) AS total_transactions,
    SUM(total_net) AS total_spending,
    -- Menghitung Average Transaction Value (ATV)
    ROUND(SUM(total_net) / COUNT(DISTINCT trx_id), 2) AS atv
FROM gacoan_transactions
GROUP BY customer_segment
ORDER BY total_spending DESC;

-- Menggunakan CTE agar kode modular dan mudah dibaca (Good Practice)
WITH branch_sales AS (
    SELECT 
        category,
        menu_name,
        SUM(quantity) as total_qty,
        SUM(revenue) as total_gmv,
        SUM(margin) as total_profit
    FROM gacoan_final_data
    WHERE branch_name = 'Gacoan Malang Soekarno Hatta' -- Optimasi: Filter lokasi di awal (Filtering Early)
    GROUP BY 1, 2
)
SELECT 
    category,
    menu_name,
    total_gmv,
    total_profit,
    -- Menghitung Persentase Margin untuk melihat efisiensi menu
    ROUND((total_profit / NULLIF(total_gmv, 0)) * 100, 2) AS margin_percentage
FROM branch_sales
ORDER BY total_profit DESC;

SELECT 
    area,
    COUNT(table_id) as usage_count,
    AVG(CAST(dwell_time_min AS FLOAT)) as avg_dwell_time,
    -- Menghitung Standar Deviasi untuk melihat konsistensi pelayanan
    STDEV(CAST(dwell_time_min AS FLOAT)) as dwell_consistency
FROM gacoan_table_turnover
WHERE status = 'Completed' -- Optimasi: Hindari memproses data 'In-Progress' yang belum final
GROUP BY area
ORDER BY avg_dwell_time ASC;

-- Mencari menu yang paling sering dibeli bersamaan dengan Mie Gacoan
SELECT 
    t2.item_name as complementary_item,
    COUNT(*) as frequency
FROM gacoan_transactions t1
JOIN gacoan_transactions t2 ON t1.trx_id = t2.trx_id
WHERE t1.item_name LIKE 'Mie Gacoan%' 
  AND t2.item_name NOT LIKE 'Mie Gacoan%'
GROUP BY 1
ORDER BY frequency DESC
LIMIT 5;

-- STEP 1: STAGING (Extract)
-- Membuat tabel sementara untuk menampung data mentah dari CSV
CREATE TABLE stg_gacoan_transactions (
    trx_id VARCHAR(50),
    timestamp DATETIME,
    item_name VARCHAR(100),
    category VARCHAR(50),
    price_net DECIMAL(10,2),
    qty INT,
    total_net DECIMAL(10,2),
    customer_segment VARCHAR(50)
);

-- STEP 2: DIMENSION TABLE (Master Data)
-- Menyimpan data COGS (Modal) untuk perhitungan Margin
CREATE TABLE dim_menu_master (
    item_name VARCHAR(100) PRIMARY KEY,
    cogs_per_unit DECIMAL(10,2) -- Modal per porsi
);

-- STEP 3: TRANSFORMATION & LOADING (The Real ETL)
-- Menggabungkan data mentah dengan master data dan menghitung KPI
INSERT INTO fact_sales_analytics (
    order_date,
    category,
    total_revenue,
    total_cost,
    net_profit,
    profit_margin_pct
)
SELECT 
    CAST(timestamp AS DATE) as order_date,
    category,
    SUM(total_net) as total_revenue,
    SUM(qty * m.cogs_per_unit) as total_cost,
    SUM(total_net - (qty * m.cogs_per_unit)) as net_profit,
    -- Menghitung % Margin (KPI Utama)
    ROUND((SUM(total_net - (qty * m.cogs_per_unit)) / SUM(total_net)) * 100, 2) as profit_margin_pct
FROM stg_gacoan_transactions t
JOIN dim_menu_master m ON t.item_name = m.item_name
GROUP BY 1, 2;