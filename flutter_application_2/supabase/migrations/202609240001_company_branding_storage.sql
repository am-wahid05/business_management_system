-- Company branding foundation. Requires the multi-company schema from
-- 202609230002_multi_company.sql; it deliberately does not rewrite that file.
do $$
begin
  if to_regclass('public.companies') is null
     or to_regclass('public.company_memberships') is null
     or to_regtype('public.company_role') is null
     or to_regprocedure('public.has_company_role(uuid,public.company_role[])') is null then
    raise exception 'Apply and verify 202609230002_multi_company.sql before this migration';
  end if;
end
$$;

alter table public.companies add column if not exists logo_path text;
alter table public.companies enable row level security;

revoke update on public.companies from public, authenticated;
revoke update (id, created_by, created_at, updated_at)
  on public.companies from public, authenticated;
grant update (name, logo_path) on public.companies to authenticated;
drop policy if exists companies_owner_admin_update on public.companies;
create policy companies_owner_admin_update
  on public.companies for update to authenticated
  using (public.has_company_role(id, array['owner','admin']::public.company_role[]))
  with check (public.has_company_role(id, array['owner','admin']::public.company_role[]));
drop policy if exists companies_owner_admin_update_boundary on public.companies;
create policy companies_owner_admin_update_boundary
  on public.companies as restrictive for update to authenticated
  using (public.has_company_role(id, array['owner','admin']::public.company_role[]))
  with check (public.has_company_role(id, array['owner','admin']::public.company_role[]));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('company-logos', 'company-logos', false, 5242880, array['image/png'])
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists company_logos_member_read on storage.objects;
create policy company_logos_member_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'company-logos'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
    and exists (
      select 1 from public.company_memberships membership
      where membership.company_id::text = split_part(storage.objects.name, '/', 1)
        and membership.user_id = auth.uid()
        and membership.is_active
    )
  );
drop policy if exists company_logos_member_read_boundary on storage.objects;
create policy company_logos_member_read_boundary
  on storage.objects as restrictive for select to public
  using (
    bucket_id <> 'company-logos'
    or (
      name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
      and exists (
        select 1 from public.company_memberships membership
        where membership.company_id::text = split_part(storage.objects.name, '/', 1)
          and membership.user_id = auth.uid()
          and membership.is_active
      )
    )
  );

drop policy if exists company_logos_owner_admin_insert on storage.objects;
create policy company_logos_owner_admin_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'company-logos'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
    and exists (
      select 1 from public.company_memberships membership
      where membership.company_id::text = split_part(storage.objects.name, '/', 1)
        and membership.user_id = auth.uid()
        and membership.is_active
        and membership.role in ('owner', 'admin')
    )
  );
drop policy if exists company_logos_owner_admin_insert_boundary on storage.objects;
create policy company_logos_owner_admin_insert_boundary
  on storage.objects as restrictive for insert to public
  with check (
    bucket_id <> 'company-logos'
    or (
      name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
      and exists (
        select 1 from public.company_memberships membership
        where membership.company_id::text = split_part(storage.objects.name, '/', 1)
          and membership.user_id = auth.uid()
          and membership.is_active
          and membership.role in ('owner', 'admin')
      )
    )
  );

drop policy if exists company_logos_owner_admin_update on storage.objects;
create policy company_logos_owner_admin_update
  on storage.objects for update to authenticated
  using (
    bucket_id = 'company-logos'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
    and exists (
      select 1 from public.company_memberships membership
      where membership.company_id::text = split_part(storage.objects.name, '/', 1)
        and membership.user_id = auth.uid()
        and membership.is_active
        and membership.role in ('owner', 'admin')
    )
  )
  with check (
    bucket_id = 'company-logos'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
    and exists (
      select 1 from public.company_memberships membership
      where membership.company_id::text = split_part(storage.objects.name, '/', 1)
        and membership.user_id = auth.uid()
        and membership.is_active
        and membership.role in ('owner', 'admin')
    )
  );
drop policy if exists company_logos_owner_admin_update_boundary on storage.objects;
create policy company_logos_owner_admin_update_boundary
  on storage.objects as restrictive for update to public
  using (
    bucket_id <> 'company-logos'
    or (
      name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
      and exists (
        select 1 from public.company_memberships membership
        where membership.company_id::text = split_part(storage.objects.name, '/', 1)
          and membership.user_id = auth.uid()
          and membership.is_active
          and membership.role in ('owner', 'admin')
      )
    )
  )
  with check (
    bucket_id <> 'company-logos'
    or (
      name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
      and exists (
        select 1 from public.company_memberships membership
        where membership.company_id::text = split_part(storage.objects.name, '/', 1)
          and membership.user_id = auth.uid()
          and membership.is_active
          and membership.role in ('owner', 'admin')
      )
    )
  );

drop policy if exists company_logos_owner_admin_delete on storage.objects;
create policy company_logos_owner_admin_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'company-logos'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
    and exists (
      select 1 from public.company_memberships membership
      where membership.company_id::text = split_part(storage.objects.name, '/', 1)
        and membership.user_id = auth.uid()
        and membership.is_active
        and membership.role in ('owner', 'admin')
    )
  );
drop policy if exists company_logos_owner_admin_delete_boundary on storage.objects;
create policy company_logos_owner_admin_delete_boundary
  on storage.objects as restrictive for delete to public
  using (
    bucket_id <> 'company-logos'
    or (
      name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo[.]png$'
      and exists (
        select 1 from public.company_memberships membership
        where membership.company_id::text = split_part(storage.objects.name, '/', 1)
          and membership.user_id = auth.uid()
          and membership.is_active
          and membership.role in ('owner', 'admin')
      )
    )
  );
