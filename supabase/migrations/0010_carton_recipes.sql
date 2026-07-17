-- =====================================================================
-- Mahim Packaging ERP — 0010_carton_recipes
-- Structured corrugated-carton specs (ply count, flute, RSC dimensions)
-- and a physics-based BOM generator: given box dimensions and which
-- paper reel covers each liner/medium layer, computes the RSC blank
-- size and the kg of each paper consumed per box, then writes that as
-- an ordinary BOM (bom_lines) — production posting is unchanged.
--
-- Formula (standard RSC — Regular Slotted Container — approximation
-- used industry-wide for material planning/costing):
--   blank_length_mm = 2*(L+W) + manufacturing_allowance_mm   (glue flap)
--   blank_width_mm  = H + W                                  (top+bottom flaps)
--   layer_kg = (blank_length_m * blank_width_m) * take_up_factor * gsm / 1000
--   take_up_factor = 1.0 for a flat liner; > 1.0 for a fluted medium
--   (the flute's wave shape consumes more paper than the flat span)
-- =====================================================================

-- ======================== FLUTE REFERENCE ============================
-- Universal physical reference data (not company-scoped — a C-flute's
-- take-up factor doesn't change between companies).
create table flute_types (
  code            text primary key,       -- A, B, C, E, F...
  name            text not null,
  flute_height_mm numeric not null,
  take_up_factor  numeric not null,       -- linear paper consumed per flat span
  typical_use     text,
  is_active       boolean not null default true
);

insert into flute_types (code, name, flute_height_mm, take_up_factor, typical_use) values
  ('A', 'A-Flute', 4.7, 1.53, 'Cushioning, fragile goods'),
  ('B', 'B-Flute', 2.5, 1.36, 'Printing surface, die-cut cartons'),
  ('C', 'C-Flute', 3.6, 1.42, 'General-purpose shipping cartons (most common)'),
  ('E', 'E-Flute', 1.5, 1.24, 'Fine printing, retail/consumer boxes'),
  ('F', 'F-Flute', 0.8, 1.18, 'Micro-flute, premium retail packaging')
on conflict (code) do nothing;

alter table flute_types enable row level security;
create policy flute_types_read on flute_types for select to authenticated using (true);

-- ========================= CARTON SPECS ==============================
-- One structural spec per finished-good item: how many plies, what
-- size, which flute/GSM/raw-material feeds each layer.
create type carton_layer_role as enum ('liner', 'medium');

create table carton_specs (
  id                      uuid primary key default gen_random_uuid(),
  company_id              uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  item_id                 uuid not null references items(id) on delete cascade,
  ply_count               int not null check (ply_count in (3, 5, 7)),
  box_style               text not null default 'RSC',
  length_mm               numeric not null check (length_mm > 0),
  width_mm                numeric not null check (width_mm > 0),
  height_mm               numeric not null check (height_mm > 0),
  manufacturing_allowance_mm numeric not null default 40,
  wastage_pct             numeric not null default 5,
  created_by              uuid references auth.users(id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (item_id)
);
create trigger trg_carton_specs_updated before update on carton_specs
  for each row execute function set_updated_at();

create table carton_spec_layers (
  id             uuid primary key default gen_random_uuid(),
  carton_spec_id uuid not null references carton_specs(id) on delete cascade,
  company_id     uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  layer_no       int not null,             -- 1 = outermost
  role           carton_layer_role not null,
  flute_code     text references flute_types(code),   -- required when role = 'medium'
  gsm            numeric not null check (gsm > 0),
  raw_item_id    uuid not null references items(id),
  unique (carton_spec_id, layer_no),
  check ((role = 'medium') = (flute_code is not null))
);

-- ==================== BOM AUTO-GENERATION EXTRAS ======================
alter table boms
  add column if not exists is_auto_generated  boolean not null default false,
  add column if not exists carton_spec_snapshot jsonb;

alter table bom_lines
  add column if not exists note text;

-- ==================== RSC BLANK-DIMENSION HELPER ======================
create or replace function carton_blank_dims(
  p_length_mm numeric, p_width_mm numeric, p_height_mm numeric,
  p_allowance_mm numeric default 40
) returns table(blank_length_mm numeric, blank_width_mm numeric)
language sql immutable as $$
  select
    2 * (p_length_mm + p_width_mm) + coalesce(p_allowance_mm, 40),
    p_height_mm + p_width_mm;
$$;

-- ===================== SAVE RECIPE + GENERATE BOM ======================
-- One transactional call: replaces the carton_specs/layers for the item,
-- computes the blank size and per-layer paper weight, retires the
-- previous auto-generated BOM (if any) and writes a fresh one. p_layers:
--   [{"layer_no":1,"role":"liner","flute_code":null,"gsm":150,"raw_item_id":"..."},
--    {"layer_no":2,"role":"medium","flute_code":"C","gsm":120,"raw_item_id":"..."}, ...]
create or replace function save_carton_recipe(
  p_item_id       uuid,
  p_ply_count     int,
  p_length_mm     numeric,
  p_width_mm      numeric,
  p_height_mm     numeric,
  p_allowance_mm  numeric,
  p_wastage_pct   numeric,
  p_layers        jsonb
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
                            height_mm, manufacturing_allowance_mm, wastage_pct, created_by)
  values (v_company, p_item_id, p_ply_count, p_length_mm, p_width_mm,
          p_height_mm, coalesce(p_allowance_mm, 40), coalesce(p_wastage_pct, 5), auth.uid())
  on conflict (item_id) do update
    set ply_count = excluded.ply_count, length_mm = excluded.length_mm,
        width_mm = excluded.width_mm, height_mm = excluded.height_mm,
        manufacturing_allowance_mm = excluded.manufacturing_allowance_mm,
        wastage_pct = excluded.wastage_pct
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
revoke execute on function save_carton_recipe(uuid, int, numeric, numeric, numeric, numeric, numeric, jsonb) from anon;

-- ============================ RLS ===================================
alter table carton_specs       enable row level security;
alter table carton_spec_layers enable row level security;

create policy carton_specs_read on carton_specs for select to authenticated
  using (is_member(company_id));
create policy carton_specs_write on carton_specs for all to authenticated
  using (can_write_company(company_id)) with check (can_write_company(company_id));
create policy carton_spec_layers_read on carton_spec_layers for select to authenticated
  using (is_member(company_id));
create policy carton_spec_layers_write on carton_spec_layers for all to authenticated
  using (can_write_company(company_id)) with check (can_write_company(company_id));

create trigger trg_audit_carton_specs after insert or update or delete on carton_specs
  for each row execute function audit_row_change();
create trigger trg_audit_carton_spec_layers after insert or update or delete on carton_spec_layers
  for each row execute function audit_row_change();
