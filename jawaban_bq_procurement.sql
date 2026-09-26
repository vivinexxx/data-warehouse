-- ============ BQ1 ============
SELECT v.vendor_name,
       v.city,
       COUNT(*)                                        AS jumlah_pengiriman,
       ROUND(AVG(dd.full_date - dp.full_date), 2)      AS lead_time_rata2_hari,
       MIN(dd.full_date - dp.full_date)                AS lead_time_min,
       MAX(dd.full_date - dp.full_date)                AS lead_time_maks
FROM fact_purchase_order f
JOIN dim_product    p  ON f.product_key       = p.product_key
JOIN dim_vendor     v  ON f.vendor_key        = v.vendor_key
JOIN dim_date       dp ON f.po_date_key       = dp.date_key
JOIN dim_date       dd ON f.delivery_date_key = dd.date_key
JOIN dim_po_profile pp ON f.po_profile_key    = pp.po_profile_key
WHERE p.product_type = 'Bahan Baku Utama'
  AND f.delivery_date_key <> 99991231          -- hanya yang sudah dikirim
  AND pp.po_status <> 'Cancelled'
GROUP BY v.vendor_name, v.city
ORDER BY lead_time_rata2_hari;
-- ============ BQ2 ============
SELECT d.year,
       d.month_number,
       d.month_name,
       ROUND(SUM(CASE WHEN p.allocation_line = 'Susu UHT'     THEN f.net_amount ELSE 0 END) / 1e9, 2) AS susu_uht,
       ROUND(SUM(CASE WHEN p.allocation_line = 'Yoghurt'      THEN f.net_amount ELSE 0 END) / 1e9, 2) AS yoghurt,
       ROUND(SUM(CASE WHEN p.allocation_line = 'Keju Cheddar' THEN f.net_amount ELSE 0 END) / 1e9, 2) AS keju_cheddar,
       ROUND(SUM(CASE WHEN p.allocation_line = 'Mentega'      THEN f.net_amount ELSE 0 END) / 1e9, 2) AS mentega,
       ROUND(SUM(CASE WHEN p.allocation_line = 'Umum'         THEN f.net_amount ELSE 0 END) / 1e9, 2) AS umum,
       ROUND(SUM(f.net_amount) / 1e9, 2)                                                              AS total
FROM fact_purchase_order f
JOIN dim_date       d  ON f.po_date_key    = d.date_key
JOIN dim_product    p  ON f.product_key    = p.product_key
JOIN dim_po_profile pp ON f.po_profile_key = pp.po_profile_key
WHERE pp.po_status <> 'Cancelled'
GROUP BY d.year, d.month_number, d.month_name
ORDER BY d.year, d.month_number;
-- ============ BQ3 ============
-- Asumsi: tanggal janji kirim = tanggal PO + 2 hari (SLA standar susu segar),
-- karena star schema belum punya kolom promised_delivery_date_key.
WITH kirim AS (
  SELECT f.vendor_key,
         (dd.full_date - dp.full_date) - 2 AS selisih_hari   -- positif = terlambat
  FROM fact_purchase_order f
  JOIN dim_product    p  ON f.product_key       = p.product_key
  JOIN dim_date       dp ON f.po_date_key       = dp.date_key
  JOIN dim_date       dd ON f.delivery_date_key = dd.date_key
  JOIN dim_po_profile pp ON f.po_profile_key    = pp.po_profile_key
  WHERE p.product_id IN ('PRD-001', 'PRD-002')   -- Susu Sapi Segar Grade A & B
    AND f.delivery_date_key <> 99991231
    AND pp.po_status <> 'Cancelled'
)
SELECT v.vendor_name,
       COUNT(*)                                                         AS jumlah_pengiriman,
       SUM(CASE WHEN selisih_hari > 0 THEN 1 ELSE 0 END)                AS jumlah_terlambat,
       ROUND(100.0 * AVG(CASE WHEN selisih_hari > 0 THEN 1 ELSE 0 END), 1) AS persen_terlambat,
       ROUND(AVG(GREATEST(selisih_hari, 0)), 2)                         AS rata2_delay_semua_kiriman,
       ROUND(AVG(CASE WHEN selisih_hari > 0 THEN selisih_hari END), 2)  AS rata2_delay_saat_terlambat,
       MAX(selisih_hari)                                                AS delay_maks_hari
FROM kirim k
JOIN dim_vendor v ON k.vendor_key = v.vendor_key
GROUP BY v.vendor_name
ORDER BY rata2_delay_semua_kiriman DESC;
-- ============ BQ4 ============
WITH per_kuartal AS (
  SELECT d.year, d.quarter, SUM(f.net_amount) AS belanja
  FROM fact_purchase_order f
  JOIN dim_date       d  ON f.po_date_key    = d.date_key
  JOIN dim_product    p  ON f.product_key    = p.product_key
  JOIN dim_po_profile pp ON f.po_profile_key = pp.po_profile_key
  WHERE p.product_type = 'Material Kemasan'
    AND pp.po_status <> 'Cancelled'
    AND d.year IN (2024, 2025)
  GROUP BY d.year, d.quarter
)
SELECT quarter,
       ROUND(SUM(CASE WHEN year = 2024 THEN belanja END) / 1e9, 2) AS belanja_2024,
       ROUND(SUM(CASE WHEN year = 2025 THEN belanja END) / 1e9, 2) AS belanja_2025,
       ROUND(AVG(belanja) / 1e9, 2)                                AS rata2_miliar,
       ROUND(100.0 * AVG(belanja) / (SELECT AVG(belanja) FROM per_kuartal), 1) AS indeks_musiman
FROM per_kuartal
GROUP BY quarter
ORDER BY quarter;
-- ============ BQ5 ============
WITH belanja_vendor AS (
  SELECT d.year, d.month_number, d.month_name, v.vendor_name,
         SUM(f.net_amount) AS belanja
  FROM fact_purchase_order f
  JOIN dim_date       d  ON f.po_date_key    = d.date_key
  JOIN dim_vendor     v  ON f.vendor_key     = v.vendor_key
  JOIN dim_po_profile pp ON f.po_profile_key = pp.po_profile_key
  WHERE pp.po_status <> 'Cancelled'
    AND d.year BETWEEN 2024 AND 2026
  GROUP BY d.year, d.month_number, d.month_name, v.vendor_name
),
ranking AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY year, month_number ORDER BY belanja DESC) AS peringkat
  FROM belanja_vendor
)
SELECT year, month_number, month_name, vendor_name,
       ROUND(belanja / 1e9, 2) AS belanja_miliar_rp
FROM ranking
WHERE peringkat = 1
ORDER BY year, month_number;
