-- =====================================================================
-- Mahim Packaging ERP — 0027_carton_costing
-- Phase 1 costing engine: turns the carton recipe's material quantities
-- (already computed by save_carton_recipe, see 0010_carton_recipes.sql)
-- into a suggested selling price. Three pieces:
--   1. companies gets company-wide reference figures (a period's actual
--      material cost + factory cost) so the UI can SUGGEST an overhead %
--      from real history, plus a default target margin %.
--   2. carton_specs gets per-recipe overrides: a flat "other direct
--      materials" cost per box (starch/glue/ink — not modelled as a
--      per-layer quantity yet), and optional overhead/margin overrides
--      for a specific recipe that need to deviate from the company default.
--   3. save_carton_recipe() persists the three new recipe-level fields.
-- Paper cost itself is NOT stored here — it's computed live client-side
-- from bom_lines × items.standard_cost, so it always reflects today's
-- prices rather than a frozen number from when the recipe was saved.
-- =====================================================================

alter table companies
  add column if not exists ref_material_cost numeric,
  add column if not exists ref_factory_cost  numeric,
  add column if not exists default_margin_pct numeric not null default 15;

-- Seed the mother company with the actual 2025 full-year figures
-- (Material Cost / Factory Cost from the P&L — gives a real starting
-- overhead ratio of ~20.5% instead of a guessed number).
update companies
   set ref_material_cost = 71026129, ref_factory_cost = 14539727
 where id = '00000000-0000-0000-0000-000000000001' and ref_material_cost is null;

alter table carton_specs
  add column if not exists other_materials_cost_per_box numeric not null default 0,
  add column if not exists overhead_pct_override numeric,
  add column if not exists margin_pct_override numeric;

create or replace function save_carton_recipe(
  p_item_id       uuid,
  p_ply_count     int,
  p_length_mm     numeric,
  p_width_mm      numeric,
  p_height_mm     numeric,
  p_allowance_mm  numeric,
  p_wastage_pct   numeric,
  p_layers        jsonb,
  p_other_materials_cost_per_box numeric default 0,
  p_overhead_pct_override         numeric default null,
  p_margin_pct_override           numeric default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_company     uuid;
  v_spec_id     uuid;
  v_bom_id      uuid;
  v_blank_len   numeric;
  v_blank_wid   numeric;
  v_layer       jsonb;
  v_take_up     numeric;
  v_kg          numeric;
  v_expected_liners  int;
  v_expected_mediums int;
  v_seen_liners  int := 0;
  v_seen_mediums int := 0;
  v_agg jsonb := '{}'::jsonb;   -- raw_item_id (text) -> {kg, notes[]}
  v_key text;
  v_entry jsonb;
  v_snapshot jsonb;
  v_flute_summary text := '';
begin
  select company_id into v_company from items where id = p_item_id;
  if v_company is null then raise exception 'Item not found'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_company), false) then
    raise exception 'Not permitted to edit recipes for this company';
  end if;
  if p_ply_count not in (3, 5, 7) then raise exception 'Ply count must be 3, 5 or 7'; end if;

  v_expected_liners  := (p_ply_count + 1) / 2;
  v_expected_mediums := (p_ply_count - 1) / 2;

  select blank_length_mm, blank_width_mm into v_blank_len, v_blank_wid
    from carton_blank_dims(p_length_mm, p_width_mm, p_height_mm, p_allowance_mm);

  -- ---- replace the spec ----
  insert into carton_specs (company_id, item_id, ply_count, length_mm, width_mm,
                            height_mm, manufacturing_allowance_mm, wastage_pct, created_by,
                            other_materials_cost_per_box, overhead_pct_override, margin_pct_override)
  values (v_company, p_item_id, p_ply_count, p_length_mm, p_width_mm,
          p_height_mm, coalesce(p_allowance_mm, 40), coalesce(p_wastage_pct, 5), auth.uid(),
          coalesce(p_other_materials_cost_per_box, 0), p_overhead_pct_override, p_margin_pct_override)
  on conflict (item_id) do update
    set ply_count = excluded.ply_count, length_mm = excluded.length_mm,
        width_mm = excluded.width_mm, height_mm = excluded.height_mm,
        manufacturing_allowance_mm = excluded.manufacturing_allowance_mm,
        wastage_pct = excluded.wastage_pct,
        other_materials_cost_per_box = excluded.other_materials_cost_per_box,
        overhead_pct_override = excluded.overhead_pct_override,
        margin_pct_override = excluded.margin_pct_override
  returning id into v_spec_id;

  delete from carton_spec_layers where carton_spec_id = v_spec_id;

  -- ---- walk layers: validate, compute kg, aggregate by raw material ----
  for v_layer in select * from jsonb_array_elements(p_layers) loop
    if (v_layer->>'role') = 'liner' then
      v_seen_liners := v_seen_liners + 1;
      v_take_up := 1.0;
    else
      v_seen_mediums := v_seen_mediums + 1;
      select take_up_factor into v_take_up from flute_types
       where code = v_layer->>'flute_code' and is_active;
      if v_take_up is null then
        raise exception 'Unknown flute type "%"', v_layer->>'flute_code';
      end if;
      v_flute_summary := v_flute_summary || case when v_flute_summary = '' then '' else '/' end
        || (v_layer->>'flute_code');
    end if;

    insert into carton_spec_layers (carton_spec_id, company_id, layer_no, role,
                                    flute_code, gsm, raw_item_id)
    values (v_spec_id, v_company, (v_layer->>'layer_no')::int,
            (v_layer->>'role')::carton_layer_role,
            v_layer->>'flute_code', (v_layer->>'gsm')::numeric,
            (v_layer->>'raw_item_id')::uuid);

    v_kg := round((v_blank_len / 1000.0) * (v_blank_wid / 1000.0)
                  * v_take_up * (v_layer->>'gsm')::numeric / 1000.0, 5);

    v_key := v_layer->>'raw_item_id';
    v_entry := coalesce(v_agg->v_key, jsonb_build_object('kg', 0, 'notes', '[]'::jsonb));
    v_agg := v_agg || jsonb_build_object(v_key, jsonb_build_object(
      'kg', (v_entry->>'kg')::numeric + v_kg,
      'notes', (v_entry->'notes') || to_jsonb(
        initcap(v_layer->>'role') || ' L' || (v_layer->>'layer_no')
        || case when v_layer->>'flute_code' is not null then ' (' || (v_layer->>'flute_code') || '-flute)' else '' end
      )
    ));
  end loop;

  if v_seen_liners <> v_expected_liners or v_seen_mediums <> v_expected_mediums then
    raise exception '% ply needs % liner(s) + % medium(s) — got % + %',
      p_ply_count, v_expected_liners, v_expected_mediums, v_seen_liners, v_seen_mediums;
  end if;

  -- ---- retire the previous auto-generated BOM, write a fresh one ----
  update boms set is_active = false
   where finished_item_id = p_item_id and is_auto_generated and is_active;

  v_snapshot := jsonb_build_object(
    'ply_count', p_ply_count, 'length_mm', p_length_mm, 'width_mm', p_width_mm,
    'height_mm', p_height_mm, 'flute_summary', v_flute_summary,
    'blank_length_mm', round(v_blank_len, 1), 'blank_width_mm', round(v_blank_wid, 1),
    'total_kg', (select round(sum((v->>'kg')::numeric), 5) from jsonb_each(v_agg) as t(k, v))
  );

  insert into boms (company_id, finished_item_id, name, output_qty,
                    is_auto_generated, carton_spec_snapshot)
  select v_company, p_item_id,
         (select sku from items where id = p_item_id) || ' — ' || p_ply_count || 'ply '
           || v_flute_summary || ' ' || p_length_mm || '×' || p_width_mm || '×' || p_height_mm || 'mm',
         1, true, v_snapshot
  returning id into v_bom_id;

  for v_key, v_entry in select * from jsonb_each(v_agg) loop
    insert into bom_lines (bom_id, component_item_id, qty_per, wastage_pct, note)
    values (v_bom_id, v_key::uuid, (v_entry->>'kg')::numeric, coalesce(p_wastage_pct, 5),
            (select string_agg(x, ' + ') from jsonb_array_elements_text(v_entry->'notes') x));
  end loop;

  return v_bom_id;
end; $$;
revoke execute on function save_carton_recipe(uuid, int, numeric, numeric, numeric, numeric, numeric, jsonb, numeric, numeric, numeric) from anon;
