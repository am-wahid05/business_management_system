-- Multi-company tenant foundation. A company is the data boundary; a user may
-- have a different role in each company.
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$ begin
  create type public.company_role as enum ('owner', 'admin', 'secretary');
exception when duplicate_object then null;
end $$;

create table if not exists public.company_memberships (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.company_role not null default 'secretary',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (company_id, user_id)
);

-- Policies can depend on the types and keys being changed below. Remove every
-- policy created by the initial migration or a prior attempt before touching
-- any business-table columns. They are recreated after the tenant schema is in
-- place. IF EXISTS also makes recovery from a rolled-back/partial attempt safe.
drop policy if exists suppliers_select_authenticated on public.suppliers;
drop policy if exists suppliers_admin_write on public.suppliers;
drop policy if exists suppliers_company_read on public.suppliers;
drop policy if exists suppliers_company_insert on public.suppliers;
drop policy if exists suppliers_company_update on public.suppliers;
drop policy if exists suppliers_company_delete on public.suppliers;

drop policy if exists products_select_authenticated on public.products;
drop policy if exists products_admin_write on public.products;
drop policy if exists products_company_read on public.products;
drop policy if exists products_company_write on public.products;

drop policy if exists deliveries_select_authorized on public.deliveries;
drop policy if exists deliveries_insert_authorized on public.deliveries;
drop policy if exists deliveries_update_authorized on public.deliveries;
drop policy if exists deliveries_delete_admin on public.deliveries;
drop policy if exists deliveries_company_read on public.deliveries;
drop policy if exists deliveries_company_insert on public.deliveries;
drop policy if exists deliveries_company_update on public.deliveries;
drop policy if exists deliveries_company_delete on public.deliveries;

drop policy if exists delivery_bag_weights_authorized on public.delivery_bag_weights;
drop policy if exists weights_company_access on public.delivery_bag_weights;
drop policy if exists receipt_sends_authorized on public.receipt_sends;
drop policy if exists receipt_company_access on public.receipt_sends;

-- The offline client uses stable text IDs; the initial schema incorrectly used
-- UUID business IDs. Remove dependent FKs before converting those key columns.
do $$
declare c record;
begin
  for c in
    select conrelid::regclass as tbl, conname
    from pg_constraint
    where contype = 'f' and conrelid in (
      'public.deliveries'::regclass,
      'public.delivery_bag_weights'::regclass,
      'public.receipt_sends'::regclass
    )
  loop
    execute format('alter table %s drop constraint %I', c.tbl, c.conname);
  end loop;
end $$;

-- Remove the key indexes before changing their key-column types. All referenced
-- foreign keys were removed above and the tenant-aware keys are rebuilt below.
alter table public.suppliers drop constraint if exists suppliers_pkey;
alter table public.products drop constraint if exists products_pkey;
alter table public.deliveries drop constraint if exists deliveries_pkey;
alter table public.delivery_bag_weights drop constraint if exists delivery_bag_weights_pkey;

-- Convert old UUID supplier references to their human-readable supplier codes
-- before changing supplier primary keys to the text IDs used by the client.
alter table public.deliveries alter column supplier_id type text using supplier_id::text;
update public.deliveries d
set supplier_id = s.supplier_id
from public.suppliers s
where d.supplier_id = s.id::text;

alter table public.suppliers alter column id drop default;
alter table public.suppliers alter column id type text using supplier_id;
alter table public.products alter column id drop default;
alter table public.products alter column id type text using id::text;
alter table public.deliveries alter column id drop default;
alter table public.deliveries alter column id type text using id::text;
alter table public.deliveries alter column product_id type text using product_id::text;
alter table public.delivery_bag_weights alter column delivery_id type text using delivery_id::text;
alter table public.receipt_sends alter column delivery_id type text using delivery_id::text;

alter table public.suppliers add column if not exists company_id uuid;
alter table public.products add column if not exists company_id uuid;
alter table public.deliveries add column if not exists company_id uuid;
alter table public.receipt_sends add column if not exists company_id uuid;

-- Existing deployments receive one AL-BNC tenant and preserve current records.
do $$
declare
  legacy_company_id uuid;
  bootstrap_user_id uuid;
  has_unassigned_business_data boolean;
begin
  select id into bootstrap_user_id from public.profiles order by created_at limit 1;
  select exists(select 1 from public.suppliers where company_id is null) or
         exists(select 1 from public.products where company_id is null) or
         exists(select 1 from public.deliveries where company_id is null) or
         exists(select 1 from public.receipt_sends where company_id is null)
    into has_unassigned_business_data;

  if has_unassigned_business_data and bootstrap_user_id is null then
    raise exception 'Existing business records have no profile to own the legacy company; assign a bootstrap profile before applying this migration.';
  end if;

  -- Also create the initial tenant for a pre-existing profile-only install.
  -- Reuse it if a previous partial attempt already created it.
  if bootstrap_user_id is not null and
     (has_unassigned_business_data or not exists(select 1 from public.companies)) then
    select id into legacy_company_id
    from public.companies
    where name = 'AL-BNC Ventures' and created_by = bootstrap_user_id
    order by created_at
    limit 1;
    if legacy_company_id is null then
      insert into public.companies(name, created_by)
      values ('AL-BNC Ventures', bootstrap_user_id) returning id into legacy_company_id;
    end if;
    insert into public.company_memberships(company_id, user_id, role, is_active)
    select legacy_company_id, p.id,
      case when p.id = bootstrap_user_id then 'owner'::public.company_role
           when p.role = 'admin' then 'admin'::public.company_role else 'secretary'::public.company_role end,
      p.is_active
    from public.profiles p
    on conflict (company_id, user_id) do nothing;
    update public.suppliers set company_id = legacy_company_id where company_id is null;
    update public.products set company_id = legacy_company_id where company_id is null;
    update public.deliveries set company_id = legacy_company_id where company_id is null;
    update public.receipt_sends set company_id = legacy_company_id where company_id is null;
  end if;
end $$;

-- Make business keys unique within a tenant, so separate companies can each
-- use the same default product IDs and supplier numbering.
alter table public.suppliers drop constraint if exists suppliers_pkey;
alter table public.suppliers drop constraint if exists suppliers_supplier_id_key;
alter table public.suppliers drop constraint if exists suppliers_company_supplier_id_key;
alter table public.suppliers alter column company_id set not null;
alter table public.suppliers alter column id set not null;
alter table public.suppliers alter column supplier_id set not null;
alter table public.suppliers add constraint suppliers_pkey primary key (company_id, id);
alter table public.suppliers add constraint suppliers_company_supplier_id_key unique (company_id, supplier_id);

alter table public.products drop constraint if exists products_pkey;
alter table public.products drop constraint if exists products_name_key;
alter table public.products drop constraint if exists products_company_name_key;
alter table public.products alter column company_id set not null;
alter table public.products alter column id set not null;
alter table public.products add constraint products_pkey primary key (company_id, id);
alter table public.products add constraint products_company_name_key unique (company_id, name);
insert into public.products(id, company_id, name)
select defaults.id, c.id, defaults.name
from public.companies c
cross join (values ('cashew', 'Cashew'), ('cocoa', 'Cocoa'), ('shea_nuts', 'Shea Nuts')) as defaults(id, name)
on conflict (company_id, id) do nothing;

alter table public.deliveries alter column company_id set not null;
alter table public.deliveries drop constraint if exists deliveries_pkey;
alter table public.deliveries alter column id set not null;
alter table public.deliveries add constraint deliveries_pkey primary key (company_id, id);
alter table public.delivery_bag_weights add column if not exists company_id uuid;
update public.delivery_bag_weights w set company_id = d.company_id
from public.deliveries d where d.id = w.delivery_id and w.company_id is null;
alter table public.delivery_bag_weights alter column company_id set not null;
alter table public.delivery_bag_weights drop constraint if exists delivery_bag_weights_pkey;
alter table public.delivery_bag_weights add constraint delivery_bag_weights_pkey primary key (company_id, delivery_id, bag_number);
update public.receipt_sends r set company_id = d.company_id
from public.deliveries d where d.id = r.delivery_id and r.company_id is null;
alter table public.receipt_sends alter column company_id set not null;

-- Rebuild every foreign key that was removed before the key/type conversions.
-- Named drops also handle a retry if an earlier execution stopped partway here.
alter table public.suppliers drop constraint if exists suppliers_company_fk;
alter table public.products drop constraint if exists products_company_fk;
alter table public.deliveries drop constraint if exists deliveries_company_fk;
alter table public.deliveries drop constraint if exists deliveries_supplier_company_fk;
alter table public.deliveries drop constraint if exists deliveries_product_company_fk;
alter table public.deliveries drop constraint if exists deliveries_recorded_by_user_fk;
alter table public.delivery_bag_weights drop constraint if exists bag_weights_company_fk;
alter table public.delivery_bag_weights drop constraint if exists bag_weights_delivery_company_fk;
alter table public.receipt_sends drop constraint if exists receipt_company_fk;
alter table public.receipt_sends drop constraint if exists receipt_delivery_company_fk;

alter table public.suppliers add constraint suppliers_company_fk
  foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.products add constraint products_company_fk
  foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.deliveries add constraint deliveries_company_fk
  foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.deliveries add constraint deliveries_supplier_company_fk
  foreign key (company_id, supplier_id) references public.suppliers(company_id, supplier_id);
alter table public.deliveries add constraint deliveries_product_company_fk
  foreign key (company_id, product_id) references public.products(company_id, id);
alter table public.deliveries add constraint deliveries_recorded_by_user_fk
  foreign key (recorded_by_user_id) references public.profiles(id);
alter table public.delivery_bag_weights add constraint bag_weights_company_fk
  foreign key (company_id) references public.companies(id) on delete cascade;
alter table public.delivery_bag_weights add constraint bag_weights_delivery_company_fk
  foreign key (company_id, delivery_id) references public.deliveries(company_id, id) on delete cascade;
alter table public.receipt_sends add constraint receipt_delivery_company_fk
  foreign key (company_id, delivery_id) references public.deliveries(company_id, id) on delete cascade;
alter table public.receipt_sends add constraint receipt_company_fk
  foreign key (company_id) references public.companies(id) on delete cascade;

-- Provision a company and its owner membership atomically for the authenticated
-- user. A caller cannot assign the owner role to another user.
create or replace function public.create_company(company_name text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare new_company_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if length(trim(company_name)) = 0 then raise exception 'Company name is required'; end if;
  insert into public.companies(name, created_by)
  values (trim(company_name), auth.uid()) returning id into new_company_id;
  insert into public.company_memberships(company_id, user_id, role)
  values (new_company_id, auth.uid(), 'owner');
  insert into public.products(id, company_id, name) values
    ('cashew', new_company_id, 'Cashew'),
    ('cocoa', new_company_id, 'Cocoa'),
    ('shea_nuts', new_company_id, 'Shea Nuts');
  return new_company_id;
end;
$$;
revoke all on function public.create_company(text) from public;
grant execute on function public.create_company(text) to authenticated;

-- Account and first-company provisioning also works when email confirmation is
-- enabled, because it occurs inside the auth.users trigger transaction.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  new_company_id uuid;
  company_name text;
begin
  insert into public.profiles (id, email, display_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(coalesce(new.email, ''), '@', 1)),
    'secretary'
  ) on conflict (id) do nothing;

  company_name := nullif(trim(new.raw_user_meta_data ->> 'company_name'), '');
  if company_name is not null then
    insert into public.companies(name, created_by)
    values (company_name, new.id) returning id into new_company_id;
    insert into public.company_memberships(company_id, user_id, role)
    values (new_company_id, new.id, 'owner');
    insert into public.products(id, company_id, name) values
      ('cashew', new_company_id, 'Cashew'),
      ('cocoa', new_company_id, 'Cocoa'),
      ('shea_nuts', new_company_id, 'Shea Nuts');
  end if;
  return new;
end;
$$;

create or replace function public.is_company_member(target_company uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.company_memberships m
    where m.company_id = target_company and m.user_id = auth.uid() and m.is_active
  );
$$;

create or replace function public.has_company_role(target_company uuid, allowed_roles public.company_role[])
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.company_memberships m
    where m.company_id = target_company and m.user_id = auth.uid()
      and m.is_active and m.role = any(allowed_roles)
  );
$$;

alter table public.companies enable row level security;
alter table public.company_memberships enable row level security;
grant select on public.companies, public.company_memberships to authenticated;
grant select, insert, update, delete on public.profiles, public.suppliers, public.products,
  public.deliveries, public.delivery_bag_weights, public.receipt_sends to authenticated;
drop policy if exists companies_read_member on public.companies;
create policy companies_read_member on public.companies for select to authenticated
using (public.is_company_member(id));
drop policy if exists memberships_read_same_company on public.company_memberships;
create policy memberships_read_same_company on public.company_memberships for select to authenticated
using (public.is_company_member(company_id));
drop policy if exists memberships_admin_manage on public.company_memberships;
create policy memberships_admin_manage on public.company_memberships for all to authenticated
using (
  public.has_company_role(company_id, array['owner','admin']::public.company_role[]) and
  (role = 'secretary' or public.has_company_role(company_id, array['owner']::public.company_role[]))
)
with check (
  (role = 'secretary' and public.has_company_role(company_id, array['owner','admin']::public.company_role[])) or
  (role in ('admin','owner') and public.has_company_role(company_id, array['owner']::public.company_role[]))
);

-- Remove global-role policies and replace them with company membership checks.
drop policy if exists profiles_select_authenticated on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
drop policy if exists profiles_update_self_company on public.profiles;
create policy profiles_update_self_company on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());
create or replace function public.prevent_profile_role_change()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if (new.role is distinct from old.role or new.is_active is distinct from old.is_active)
     and coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Profile roles and active status can only be changed by a trusted server operation';
  end if;
  return new;
end;
$$;
drop policy if exists deliveries_select_authorized on public.deliveries;
drop policy if exists deliveries_insert_authorized on public.deliveries;
drop policy if exists deliveries_update_authorized on public.deliveries;
drop policy if exists deliveries_delete_admin on public.deliveries;
drop policy if exists suppliers_select_authenticated on public.suppliers;
drop policy if exists suppliers_admin_write on public.suppliers;
drop policy if exists products_select_authenticated on public.products;
drop policy if exists products_admin_write on public.products;
drop policy if exists delivery_bag_weights_authorized on public.delivery_bag_weights;
drop policy if exists receipt_sends_authorized on public.receipt_sends;

create policy suppliers_company_read on public.suppliers for select to authenticated
using (public.is_company_member(company_id));
create policy suppliers_company_insert on public.suppliers for insert to authenticated
with check (public.is_company_member(company_id));
create policy suppliers_company_update on public.suppliers for update to authenticated
using (public.is_company_member(company_id)) with check (public.is_company_member(company_id));
create policy suppliers_company_delete on public.suppliers for delete to authenticated
using (public.has_company_role(company_id, array['owner','admin']::public.company_role[]));
create policy products_company_read on public.products for select to authenticated
using (public.is_company_member(company_id));
create policy products_company_write on public.products for all to authenticated
using (public.has_company_role(company_id, array['owner','admin']::public.company_role[]))
with check (public.has_company_role(company_id, array['owner','admin']::public.company_role[]));
create policy deliveries_company_read on public.deliveries for select to authenticated
using (public.is_company_member(company_id));
create policy deliveries_company_insert on public.deliveries for insert to authenticated
with check (public.is_company_member(company_id) and (recorded_by_user_id = auth.uid() or public.has_company_role(company_id, array['owner','admin']::public.company_role[])));
create policy deliveries_company_update on public.deliveries for update to authenticated
using (public.is_company_member(company_id) and (recorded_by_user_id = auth.uid() or public.has_company_role(company_id, array['owner','admin']::public.company_role[])))
with check (public.is_company_member(company_id) and (recorded_by_user_id = auth.uid() or public.has_company_role(company_id, array['owner','admin']::public.company_role[])));
create policy deliveries_company_delete on public.deliveries for delete to authenticated
using (public.has_company_role(company_id, array['owner','admin']::public.company_role[]));
create policy weights_company_access on public.delivery_bag_weights for all to authenticated
using (exists (
  select 1 from public.deliveries d where d.company_id = delivery_bag_weights.company_id
    and d.id = delivery_bag_weights.delivery_id
    and (d.recorded_by_user_id = auth.uid() or public.has_company_role(d.company_id, array['owner','admin']::public.company_role[]))
))
with check (exists (
  select 1 from public.deliveries d where d.company_id = delivery_bag_weights.company_id
    and d.id = delivery_bag_weights.delivery_id
    and (d.recorded_by_user_id = auth.uid() or public.has_company_role(d.company_id, array['owner','admin']::public.company_role[]))
));
create policy receipt_company_access on public.receipt_sends for all to authenticated
using (public.is_company_member(company_id)) with check (public.is_company_member(company_id));

drop policy if exists profiles_company_member_read on public.profiles;
create policy profiles_company_member_read on public.profiles for select to authenticated
using (exists (
  select 1 from public.company_memberships target
  join public.company_memberships actor on actor.company_id = target.company_id
  where target.user_id = profiles.id and actor.user_id = auth.uid()
    and actor.is_active
));

create index if not exists suppliers_company_idx on public.suppliers(company_id);
create index if not exists products_company_idx on public.products(company_id);
create index if not exists deliveries_company_recorded_at_idx on public.deliveries(company_id, recorded_at);
create index if not exists memberships_user_idx on public.company_memberships(user_id);
