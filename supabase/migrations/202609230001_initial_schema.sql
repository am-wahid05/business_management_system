create extension if not exists pgcrypto;

do $$
begin
  create type public.user_role as enum ('admin', 'secretary');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.supplier_type as enum ('farmer', 'company');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text not null,
  role public.user_role not null default 'secretary',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  supplier_id text not null unique,
  normalized_name text not null,
  name text not null,
  type public.supplier_type not null,
  phone text,
  town text not null default '',
  district text not null default '',
  region text not null default '',
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id),
  product_id uuid not null references public.products(id),
  recorded_at timestamptz not null,
  recorded_by_user_id uuid not null references public.profiles(id),
  status text not null,
  synchronization_status text not null default 'synced',
  supplier_name text not null,
  product_name text not null,
  supplier_type public.supplier_type not null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.delivery_bag_weights (
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  bag_number integer not null check (bag_number > 0),
  weight numeric(12, 3) not null check (weight > 0),
  primary key (delivery_id, bag_number)
);

create table if not exists public.receipt_sends (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  phone text not null,
  channel text not null,
  status text not null,
  sent_at timestamptz not null default now(),
  provider_reference text
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(coalesce(new.email, ''), '@', 1)),
    'secretary'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create index if not exists deliveries_recorded_at_idx on public.deliveries(recorded_at);
create index if not exists deliveries_supplier_id_idx on public.deliveries(supplier_id);
create index if not exists deliveries_product_id_idx on public.deliveries(product_id);
create index if not exists delivery_bag_weights_delivery_id_idx on public.delivery_bag_weights(delivery_id);
create index if not exists receipt_sends_delivery_id_idx on public.receipt_sends(delivery_id);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin' and is_active
  );
$$;

create or replace function public.prevent_profile_role_change()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Profile roles can only be changed by a trusted server operation';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_role_guard on public.profiles;
create trigger profiles_role_guard before update on public.profiles
for each row execute function public.prevent_profile_role_change();

alter table public.profiles enable row level security;
alter table public.suppliers enable row level security;
alter table public.products enable row level security;
alter table public.deliveries enable row level security;
alter table public.delivery_bag_weights enable row level security;
alter table public.receipt_sends enable row level security;

drop policy if exists profiles_select_authenticated on public.profiles;
create policy profiles_select_authenticated on public.profiles for select to authenticated
using ((select auth.uid()) = id or (select public.is_admin()));

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
using ((select auth.uid()) = id or (select public.is_admin()))
with check ((select auth.uid()) = id or (select public.is_admin()));

drop policy if exists suppliers_select_authenticated on public.suppliers;
create policy suppliers_select_authenticated on public.suppliers for select to authenticated
using (true);

drop policy if exists suppliers_admin_write on public.suppliers;
create policy suppliers_admin_write on public.suppliers for all to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists products_select_authenticated on public.products;
create policy products_select_authenticated on public.products for select to authenticated
using (true);

drop policy if exists products_admin_write on public.products;
create policy products_admin_write on public.products for all to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists deliveries_select_authorized on public.deliveries;
create policy deliveries_select_authorized on public.deliveries for select to authenticated
using ((select public.is_admin()) or (select auth.uid()) = recorded_by_user_id);

drop policy if exists deliveries_insert_authorized on public.deliveries;
create policy deliveries_insert_authorized on public.deliveries for insert to authenticated
with check ((select auth.uid()) = recorded_by_user_id or (select public.is_admin()));

drop policy if exists deliveries_update_authorized on public.deliveries;
create policy deliveries_update_authorized on public.deliveries for update to authenticated
using ((select public.is_admin()) or (select auth.uid()) = recorded_by_user_id)
with check ((select public.is_admin()) or (select auth.uid()) = recorded_by_user_id);

drop policy if exists deliveries_delete_admin on public.deliveries;
create policy deliveries_delete_admin on public.deliveries for delete to authenticated
using ((select public.is_admin()));

drop policy if exists delivery_bag_weights_authorized on public.delivery_bag_weights;
create policy delivery_bag_weights_authorized on public.delivery_bag_weights for all to authenticated
using (exists (
  select 1 from public.deliveries d
  where d.id = delivery_id
    and ((select public.is_admin()) or d.recorded_by_user_id = (select auth.uid()))
))
with check (exists (
  select 1 from public.deliveries d
  where d.id = delivery_id
    and ((select public.is_admin()) or d.recorded_by_user_id = (select auth.uid()))
));

drop policy if exists receipt_sends_authorized on public.receipt_sends;
create policy receipt_sends_authorized on public.receipt_sends for all to authenticated
using (exists (
  select 1 from public.deliveries d
  where d.id = delivery_id
    and ((select public.is_admin()) or d.recorded_by_user_id = (select auth.uid()))
))
with check (exists (
  select 1 from public.deliveries d
  where d.id = delivery_id
    and ((select public.is_admin()) or d.recorded_by_user_id = (select auth.uid()))
));