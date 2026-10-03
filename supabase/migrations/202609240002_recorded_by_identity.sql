-- Attribute new deliveries and individual bag weights to the authenticated
-- user. Existing rows are intentionally left unchanged; NULL means unknown.
do $$
begin
  if to_regclass('public.deliveries') is null
     or to_regclass('public.delivery_bag_weights') is null
     or to_regclass('public.profiles') is null
     or to_regclass('public.company_memberships') is null then
    raise exception 'Apply the existing company schema before this migration';
  end if;
end
$$;

alter table public.deliveries
  alter column recorded_by_user_id drop not null;

alter table public.delivery_bag_weights
  add column if not exists recorded_by_user_id uuid
    references public.profiles(id);

alter table public.deliveries enable row level security;
alter table public.delivery_bag_weights enable row level security;

drop policy if exists deliveries_recorded_by_insert_boundary
  on public.deliveries;
create policy deliveries_recorded_by_insert_boundary
  on public.deliveries as restrictive for insert to authenticated
  with check (recorded_by_user_id = auth.uid());

drop policy if exists bag_weights_recorded_by_insert_boundary
  on public.delivery_bag_weights;
create policy bag_weights_recorded_by_insert_boundary
  on public.delivery_bag_weights as restrictive for insert to authenticated
  with check (recorded_by_user_id = auth.uid());

create index if not exists deliveries_company_recorded_by_idx
  on public.deliveries(company_id, recorded_by_user_id);
create index if not exists bag_weights_company_recorded_by_idx
  on public.delivery_bag_weights(company_id, recorded_by_user_id);

create or replace function public.enforce_recorded_by_user_id()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    -- A normal client cannot choose another user's identity. Service-side
    -- maintenance with no user JWT may preserve an explicitly supplied value.
    if actor_id is not null then
      new.recorded_by_user_id := actor_id;
    end if;
  elsif actor_id is not null
        and new.recorded_by_user_id is distinct from old.recorded_by_user_id then
    raise exception 'recorded_by_user_id is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists deliveries_recorded_by_guard on public.deliveries;
create trigger deliveries_recorded_by_guard
before insert or update of recorded_by_user_id on public.deliveries
for each row execute function public.enforce_recorded_by_user_id();

drop trigger if exists bag_weights_recorded_by_guard on public.delivery_bag_weights;
create trigger bag_weights_recorded_by_guard
before insert or update of recorded_by_user_id on public.delivery_bag_weights
for each row execute function public.enforce_recorded_by_user_id();
