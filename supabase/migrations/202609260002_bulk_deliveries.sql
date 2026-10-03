-- Bulk / weighing-bridge deliveries.
--
-- Additive only. Existing individual deliveries keep working untouched: their
-- bag weight rows stay authoritative and their totals are unchanged.
--
-- A bulk record is one weighing-bridge transaction. The scale produced a single
-- total and the bags were never individually weighed, so there are deliberately
-- NO rows in delivery_bag_weights. Nothing here invents bag weights.

-- 1. Columns. Defaults are chosen so a pre-existing row reads as individual.
alter table public.deliveries
  add column if not exists record_type text not null default 'individual',
  add column if not exists total_weight numeric(12, 3),
  add column if not exists bag_count integer,
  add column if not exists notes text;

-- 2. Backfill the individual rows from the bag weights that already exist.
--    A delivery with bag weights is individual and its total is their sum.
--    Nothing is recalculated for a row that already has a value.
update public.deliveries d
   set total_weight = b.total,
       bag_count = b.count
  from (
    select delivery_id, sum(weight) as total, count(*) as count
      from public.delivery_bag_weights
     group by delivery_id
  ) b
 where b.delivery_id = d.id
   and d.record_type = 'individual'
   and d.total_weight is null;

-- Every pre-existing delivery is individual, whatever the backfill found.
update public.deliveries
   set record_type = 'individual'
 where record_type is null;

-- 3. Constraints.
--    record_type is a closed set.
alter table public.deliveries
  drop constraint if exists deliveries_record_type_check;
alter table public.deliveries
  add constraint deliveries_record_type_check
  check (record_type in ('individual', 'bulk'));

--    A bulk row must carry a positive stored total and bag count, and must not
--    pretend to have individual bags. An individual row keeps the existing rule
--    that its weight comes from delivery_bag_weights, so it is not constrained
--    here and cannot be broken by this migration.
alter table public.deliveries
  drop constraint if exists deliveries_bulk_weight_check;
alter table public.deliveries
  add constraint deliveries_bulk_weight_check
  check (
    record_type <> 'bulk'
    or (total_weight is not null and total_weight > 0
        and bag_count is not null and bag_count > 0)
  );

-- 4. Indexes that support the reporting queries which now read these columns.
create index if not exists deliveries_company_record_type_idx
  on public.deliveries(company_id, record_type);

create index if not exists deliveries_company_recorded_at_type_idx
  on public.deliveries(company_id, recorded_at, record_type);
