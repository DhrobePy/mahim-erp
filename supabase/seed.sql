-- Seed reference data for Mahim Packaging ERP (run after 0001_init.sql).

insert into uoms (code, name) values
  ('KG',  'Kilogram'),
  ('TON', 'Metric Ton'),
  ('PCS', 'Pieces'),
  ('SHT', 'Sheet'),
  ('RLL', 'Roll'),
  ('SQM', 'Square Metre'),
  ('LTR', 'Litre')
on conflict (company_id, code) do nothing;

insert into item_categories (name) values
  ('Paper & Board'),
  ('Ink & Chemicals'),
  ('Film & Poly'),
  ('Adhesives'),
  ('Finished Cartons'),
  ('Finished Bags'),
  ('Consumables')
on conflict (company_id, name) do nothing;

insert into warehouses (code, name) values
  ('RM',  'Raw Material Store'),
  ('FG',  'Finished Goods Store'),
  ('WIP', 'Work In Progress')
on conflict (company_id, code) do nothing;

-- A few illustrative items (packaging manufacturer).
insert into items (sku, name, item_type, gsm, size_spec, uom_id, category_id)
values
  ('RM-BOARD-250', 'Duplex Board 250gsm', 'raw_material', 250, '25x36 inch',
     (select id from uoms where code='SHT'),
     (select id from item_categories where name='Paper & Board')),
  ('RM-INK-BLK', 'Offset Ink - Black', 'raw_material', null, null,
     (select id from uoms where code='KG'),
     (select id from item_categories where name='Ink & Chemicals')),
  ('RM-GLUE', 'Corrugation Adhesive', 'raw_material', null, null,
     (select id from uoms where code='KG'),
     (select id from item_categories where name='Adhesives')),
  ('FG-CARTON-A', 'Printed Carton - Model A', 'finished_good', null, '300x200x150 mm',
     (select id from uoms where code='PCS'),
     (select id from item_categories where name='Finished Cartons'))
on conflict (company_id, sku) do nothing;

-- Factory cost centers (mother company).
insert into cost_centers (code, name) values
  ('CORR', 'Corrugation'),
  ('PRNT', 'Printing'),
  ('DIEC', 'Die Cutting'),
  ('PAST', 'Pasting & Gluing'),
  ('BOIL', 'Boiler / Steam'),
  ('GENR', 'Generator / Captive Power'),
  ('ADMN', 'Admin & Overhead')
on conflict (company_id, code) do nothing;

-- Document number series (mother company). Statutory vs internal series
-- are deliberately separate doc_types so official sequences stay gapless.
insert into document_series (company_id, doc_type, prefix) values
  ('00000000-0000-0000-0000-000000000001', 'production_order', 'PRD')
on conflict (company_id, doc_type) do nothing;
