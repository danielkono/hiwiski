-- A later migration, run by the server's role after the move from the superuser
-- (DatabaseRoleIT): it changes a table the superuser created.
alter table instance_setting add column role_probe text;
create index instance_setting_role_probe on instance_setting (role_probe);
alter table instance_setting drop column role_probe;
