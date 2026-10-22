
create policy "service_role_manage_plus8_admin_users"
on public.plus8_admin_users
for all
to service_role
using (true)
with check (true);

create policy "service_role_manage_plus8_admin_audit_log"
on public.plus8_admin_audit_log
for all
to service_role
using (true)
with check (true);
;
