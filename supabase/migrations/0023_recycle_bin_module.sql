-- Nav/permission entry for the recycle bin page added in 0022.
insert into permission_modules (key, group_label, label, sort_order) values
  ('recycle_bin', 'Admin', 'Recycle bin', 91)
on conflict (key) do nothing;
