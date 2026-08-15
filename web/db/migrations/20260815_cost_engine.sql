-- IBEX Honey centralized cost/profit engine
-- 2026-08-15
-- Purpose: derive sales item cost from product base cost, selected unit conversion,
-- and transaction currency. Frontend-provided estimated cost is not trusted.

CREATE OR REPLACE FUNCTION public.ibex_had_convert_currency(
  p_business_id uuid,
  p_amount numeric,
  p_from text,
  p_to text
)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO public, pg_temp
AS '
WITH rates AS (
  SELECT
    max(CASE WHEN setting_key = ''sar_rate_to_yer'' THEN (setting_value #>> ''{}'')::numeric END) AS sar_to_yer,
    max(CASE WHEN setting_key = ''usd_rate_to_yer'' THEN (setting_value #>> ''{}'')::numeric END) AS usd_to_yer
  FROM public.ibex_had_settings
  WHERE business_id = p_business_id
), normalized AS (
  SELECT upper(trim(p_from)) AS f, upper(trim(p_to)) AS t, p_amount AS a, sar_to_yer, usd_to_yer
  FROM rates
)
SELECT round(
  CASE
    WHEN f = t THEN a
    WHEN f = ''SAR'' AND t = ''YER'' THEN a * sar_to_yer
    WHEN f = ''YER'' AND t = ''SAR'' THEN a / nullif(sar_to_yer, 0)
    WHEN f = ''USD'' AND t = ''YER'' THEN a * usd_to_yer
    WHEN f = ''YER'' AND t = ''USD'' THEN a / nullif(usd_to_yer, 0)
    WHEN f = ''SAR'' AND t = ''USD'' THEN (a * sar_to_yer) / nullif(usd_to_yer, 0)
    WHEN f = ''USD'' AND t = ''SAR'' THEN (a * usd_to_yer) / nullif(sar_to_yer, 0)
    ELSE NULL
  END,
  4
)
FROM normalized;
';

CREATE OR REPLACE FUNCTION public.ibex_had_calculate_product_unit_cost(
  p_product_id uuid,
  p_unit_name text,
  p_target_currency text
)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO public, pg_temp
AS '
WITH p AS (
  SELECT p.id, p.business_id, p.default_cost,
         p.default_currency::text AS source_currency,
         p.notes, u.unit_name AS default_unit_name
  FROM public.ibex_had_products p
  LEFT JOIN public.ibex_had_units u ON u.id = p.default_unit_id
  WHERE p.id = p_product_id
), meta AS (
  SELECT p.*,
         CASE WHEN p.notes LIKE ''[IBEX_UNITS_JSON_V2]:%''
              THEN substring(p.notes FROM length(''[IBEX_UNITS_JSON_V2]:'') + 1)::jsonb
              ELSE NULL::jsonb END AS units_meta
  FROM p
), factor AS (
  SELECT meta.*,
         COALESCE(
           (
             SELECT (x->>''conversion_factor'')::numeric
             FROM jsonb_array_elements(COALESCE(units_meta->''units'', ''[]''::jsonb)) x
             WHERE lower(trim(x->>''unit_name'')) = lower(trim(p_unit_name))
               AND COALESCE((x->>''enabled'')::boolean, true) = true
             LIMIT 1
           ),
           CASE WHEN lower(trim(default_unit_name)) = lower(trim(p_unit_name))
                THEN 1::numeric ELSE NULL::numeric END
         ) AS unit_factor
  FROM meta
)
SELECT round(
  public.ibex_had_convert_currency(
    business_id,
    default_cost * unit_factor,
    source_currency,
    p_target_currency
  ),
  2
)
FROM factor
WHERE unit_factor IS NOT NULL;
';

CREATE OR REPLACE FUNCTION public.ibex_had_apply_sales_item_cost()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO public, pg_temp
AS E'DECLARE\n  v_currency text;\n  v_type text;\n  v_cost numeric;\nBEGIN\n  SELECT t.currency::text, t.transaction_type::text INTO v_currency, v_type\n  FROM public.ibex_had_transactions t\n  WHERE t.id = NEW.transaction_id;\n\n  NEW.line_total := round((NEW.quantity * NEW.unit_price)::numeric, 2);\n\n  IF v_type = ''sales_invoice'' AND NEW.product_id IS NOT NULL AND NEW.unit_name_snapshot IS NOT NULL THEN\n    v_cost := public.ibex_had_calculate_product_unit_cost(NEW.product_id, NEW.unit_name_snapshot, v_currency);\n    IF v_cost IS NULL THEN\n      RAISE EXCEPTION ''Unable to resolve product unit cost for product % unit %'', NEW.product_id, NEW.unit_name_snapshot;\n    END IF;\n    NEW.estimated_unit_cost := v_cost;\n  END IF;\n\n  NEW.estimated_line_cost := round((NEW.quantity * COALESCE(NEW.estimated_unit_cost, 0))::numeric, 2);\n  NEW.estimated_line_profit := round((NEW.line_total - NEW.estimated_line_cost)::numeric, 2);\n  RETURN NEW;\nEND;';

DROP TRIGGER IF EXISTS trg_ibex_had_apply_sales_item_cost
ON public.ibex_had_transaction_items;

CREATE TRIGGER trg_ibex_had_apply_sales_item_cost
BEFORE INSERT OR UPDATE OF transaction_id, product_id, unit_name_snapshot, quantity, unit_price, estimated_unit_cost
ON public.ibex_had_transaction_items
FOR EACH ROW
EXECUTE FUNCTION public.ibex_had_apply_sales_item_cost();

CREATE OR REPLACE FUNCTION public.ibex_had_recalculate_transaction_profit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO public, pg_temp
AS E'DECLARE\n  v_transaction_id uuid;\nBEGIN\n  v_transaction_id := COALESCE(NEW.transaction_id, OLD.transaction_id);\n\n  UPDATE public.ibex_had_transactions t\n  SET estimated_profit = round((t.total_amount - COALESCE((\n    SELECT sum(i.estimated_line_cost)\n    FROM public.ibex_had_transaction_items i\n    WHERE i.transaction_id = v_transaction_id\n  ), 0))::numeric, 2)\n  WHERE t.id = v_transaction_id\n    AND t.transaction_type = ''sales_invoice'';\n\n  RETURN COALESCE(NEW, OLD);\nEND;';

DROP TRIGGER IF EXISTS trg_ibex_had_recalculate_transaction_profit
ON public.ibex_had_transaction_items;

CREATE TRIGGER trg_ibex_had_recalculate_transaction_profit
AFTER INSERT OR UPDATE OF estimated_line_cost, line_total, quantity, unit_price OR DELETE
ON public.ibex_had_transaction_items
FOR EACH ROW
EXECUTE FUNCTION public.ibex_had_recalculate_transaction_profit();

CREATE OR REPLACE FUNCTION public.ibex_had_create_transaction_v2(p_payload jsonb)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SET search_path TO public, pg_temp
AS '
WITH r AS (
  SELECT public.ibex_had_create_transaction(p_payload) AS result
), t AS (
  SELECT tr.estimated_profit
  FROM r
  JOIN public.ibex_had_transactions tr
    ON tr.id = (r.result->>''transaction_id'')::uuid
)
SELECT r.result || jsonb_build_object(''estimated_profit'', t.estimated_profit)
FROM r, t;
';

REVOKE ALL ON FUNCTION public.ibex_had_convert_currency(uuid,numeric,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ibex_had_calculate_product_unit_cost(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ibex_had_apply_sales_item_cost() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ibex_had_recalculate_transaction_profit() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ibex_had_create_transaction_v2(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.ibex_had_convert_currency(uuid,numeric,text,text) TO ibex_backend;
GRANT EXECUTE ON FUNCTION public.ibex_had_calculate_product_unit_cost(uuid,text,text) TO ibex_backend;
GRANT EXECUTE ON FUNCTION public.ibex_had_create_transaction_v2(jsonb) TO ibex_backend;
