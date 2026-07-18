-- =====================================================================
-- Mahim Packaging ERP — 0018_carton_recipe_templates
-- Reusable, admin-editable carton recipe templates (ply + flute/GSM
-- pattern only — no dimensions, no raw-material mapping) that seed the
-- carton recipe wizard on /boms. Three general-purpose starting points
-- are provided; admins can edit them or add their own.
-- =====================================================================

create table carton_recipe_templates (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  name         text not null,
  ply_count    int not null check (ply_count in (3, 5, 7)),
  layers       jsonb not null,  -- [{layer_no, role, flute_code, gsm}] — no raw_item_id
  created_by   uuid references auth.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger trg_carton_recipe_templates_updated before update on carton_recipe_templates
  for each row execute function set_updated_at();

alter table carton_recipe_templates enable row level security;
create policy carton_recipe_templates_read on carton_recipe_templates for select to authenticated
  using (is_member(company_id));
create policy carton_recipe_templates_write on carton_recipe_templates for all to authenticated
  using (can_write_company(company_id)) with check (can_write_company(company_id));

-- ==================== SEED: 3 general-purpose templates ================
insert into carton_recipe_templates (name, ply_count, layers) values
(
  '3-Ply — General Purpose (C-flute)', 3,
  '[
    {"layer_no": 1, "role": "liner",  "flute_code": null, "gsm": 150},
    {"layer_no": 2, "role": "medium", "flute_code": "C",  "gsm": 120},
    {"layer_no": 3, "role": "liner",  "flute_code": null, "gsm": 150}
  ]'::jsonb
),
(
  '5-Ply — Double Wall (BC-flute)', 5,
  '[
    {"layer_no": 1, "role": "liner",  "flute_code": null, "gsm": 170},
    {"layer_no": 2, "role": "medium", "flute_code": "B",  "gsm": 140},
    {"layer_no": 3, "role": "liner",  "flute_code": null, "gsm": 150},
    {"layer_no": 4, "role": "medium", "flute_code": "C",  "gsm": 140},
    {"layer_no": 5, "role": "liner",  "flute_code": null, "gsm": 170}
  ]'::jsonb
),
(
  '7-Ply — Triple Wall Heavy Duty (ACA-flute)', 7,
  '[
    {"layer_no": 1, "role": "liner",  "flute_code": null, "gsm": 200},
    {"layer_no": 2, "role": "medium", "flute_code": "A",  "gsm": 150},
    {"layer_no": 3, "role": "liner",  "flute_code": null, "gsm": 170},
    {"layer_no": 4, "role": "medium", "flute_code": "C",  "gsm": 150},
    {"layer_no": 5, "role": "liner",  "flute_code": null, "gsm": 170},
    {"layer_no": 6, "role": "medium", "flute_code": "A",  "gsm": 150},
    {"layer_no": 7, "role": "liner",  "flute_code": null, "gsm": 200}
  ]'::jsonb
);
