-- Company printing preferences.
--
-- Additive only. It adds nullable columns to public.companies and widens the
-- UPDATE grant to those columns. It does not touch existing data, does not
-- drop or alter any existing column, index, policy or table, and is therefore
-- safe to apply to a live database and safe to roll back by dropping the four
-- columns.
--
-- Requires the multi-company schema (202609230002_multi_company.sql) and the
-- company branding migration (202609240001), exactly like the branding
-- migration that introduced the existing companies_owner_admin_update policy.
do $$
begin
  if to_regclass('public.companies') is null
     or to_regclass('public.company_memberships') is null
     or to_regprocedure('public.has_company_role(uuid,public.company_role[])') is null then
    raise exception 'Apply and verify the multi-company schema before this migration';
  end if;
end
$$;

-- Paper sizes are stored as the stable PaperSize ids from the client
-- (thermal58, thermal80, a5, a4, letter, legal) rather than as millimetres, so
-- the meaning of a stored value does not drift if a physical size is ever
-- revised. An unknown or NULL value is treated by the client as "use the
-- default", so a row written by an older build still prints.
alter table public.companies
  add column if not exists receipt_paper_size text,
  add column if not exists report_paper_size text,
  add column if not exists statement_paper_size text,
  add column if not exists print_show_preview boolean;

-- Backfill only the rows that are still NULL, so a value that was already
-- chosen is never overwritten if this migration is re-applied.
update public.companies set receipt_paper_size = 'thermal80'
  where receipt_paper_size is null;
update public.companies set report_paper_size = 'a4'
  where report_paper_size is null;
update public.companies set statement_paper_size = 'a4'
  where statement_paper_size is null;
update public.companies set print_show_preview = true
  where print_show_preview is null;

-- Constrain the stored paper sizes to the ids the client understands. NULL is
-- still allowed so a company row created by a different tool is not rejected.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'companies_paper_size_ids'
  ) then
    alter table public.companies add constraint companies_paper_size_ids
      check (
        (receipt_paper_size is null
          or receipt_paper_size in ('thermal58','thermal80','a5','a4','letter','legal'))
        and (report_paper_size is null
          or report_paper_size in ('thermal58','thermal80','a5','a4','letter','legal'))
        and (statement_paper_size is null
          or statement_paper_size in ('thermal58','thermal80','a5','a4','letter','legal'))
      );
  end if;
end
$$;

-- Widen the existing column-level UPDATE grant. The company_owner_admin_update
-- policy created by the branding migration is unchanged and still gates every
-- write on has_company_role(id, owner|admin), so this only adds which columns
-- may be written, never who may write them. No new policy is created, so there
-- is no way for this migration to widen row access to a company.
grant update (receipt_paper_size, report_paper_size, statement_paper_size, print_show_preview)
  on public.companies to authenticated;
