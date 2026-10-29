-- =========================================================================
-- Barbería PRO — Precios de lanzamiento (RD$ al mes), 29-oct-2026
-- =========================================================================

update planes set precio_mensual = 400  where codigo = 'solo';
update planes set precio_mensual = 900  where codigo = 'barberia';
update planes set precio_mensual = 1600 where codigo = 'pro';
