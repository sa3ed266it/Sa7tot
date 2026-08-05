-- Sa7tot direct-remote schema draft. REVIEW ONLY; do not execute automatically.
-- Source audit commit: 8f8d4faf8ee07c9b8638a5b83a28dd8026718f05
-- TODO: confirm whether one account may hold multiple currencies before production.

create extension if not exists pgcrypto;

create type public.transaction_kind as enum ('expense','income','transfer');
create type public.transaction_origin as enum ('manual','wallet_shortcut','app_intent','recurring');
create type public.review_status as enum ('confirmed','needs_review');
create type public.account_kind as enum ('cash','bank','credit_card','other');
create type public.budget_period as enum ('weekly','monthly','yearly','custom');

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  timezone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  name text not null, kind public.account_kind not null default 'other',
  opening_balance numeric(20,6) not null default 0, currency_code char(3) not null,
  icon_name text not null default 'building.columns.fill', colour text not null default '#5E7CE2',
  wallet_label text, is_archived boolean not null default false, display_order integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint accounts_currency_ck check (currency_code ~ '^[A-Z]{3}$')
);

create table public.categories (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  name text not null, normalized_name text not null, is_income boolean not null default false,
  icon_identifier text not null default 'sf:tag.fill', colour text not null default '#FFFFFF', display_order bigint not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (user_id, is_income, normalized_name)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  kind public.transaction_kind not null, amount numeric(20,6) not null, currency_code char(3) not null,
  occurred_at timestamptz not null, note text not null default '', category_id uuid,
  account_id uuid, destination_account_id uuid, origin public.transaction_origin not null default 'manual',
  merchant text, normalized_merchant text, wallet_account_label text, external_reference text,
  review_status public.review_status not null default 'confirmed', fingerprint text,
  recurring_template_id uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint transactions_amount_ck check (amount > 0),
  constraint transactions_currency_ck check (currency_code ~ '^[A-Z]{3}$'),
  constraint transactions_transfer_ck check ((kind = 'transfer' and account_id is not null and destination_account_id is not null and account_id <> destination_account_id) or kind <> 'transfer'),
  constraint transactions_nontransfer_destination_ck check (kind = 'transfer' or destination_account_id is null)
);

-- Composite uniqueness is declared before composite foreign keys so PostgreSQL can validate
-- ownership of every referenced row.
alter table public.accounts add constraint accounts_user_id_id_uq unique (user_id, id);
alter table public.categories add constraint categories_user_id_id_uq unique (user_id, id);
alter table public.transactions add constraint transactions_account_fk foreign key (account_id, user_id) references public.accounts(id, user_id);
alter table public.transactions add constraint transactions_destination_fk foreign key (destination_account_id, user_id) references public.accounts(id, user_id);
alter table public.transactions add constraint transactions_category_fk foreign key (category_id, user_id) references public.categories(id, user_id);

create table public.budgets (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid, amount numeric(20,6) not null, currency_code char(3) not null,
  period public.budget_period not null, starts_at timestamptz not null, ends_at timestamptz not null,
  is_main boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint budgets_amount_ck check (amount >= 0), constraint budgets_range_ck check (ends_at > starts_at),
  constraint budgets_category_fk foreign key (category_id, user_id) references public.categories(id, user_id)
);

create table public.recurring_transactions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid, category_id uuid, kind public.transaction_kind not null, amount numeric(20,6) not null,
  currency_code char(3) not null, note text not null default '', interval_unit text not null,
  interval_count smallint not null, next_occurrence_at timestamptz not null, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint recurring_amount_ck check (amount > 0), constraint recurring_interval_ck check (interval_count > 0),
  constraint recurring_account_fk foreign key (account_id, user_id) references public.accounts(id, user_id),
  constraint recurring_category_fk foreign key (category_id, user_id) references public.categories(id, user_id)
);

create unique index transactions_external_reference_uq on public.transactions(user_id, external_reference) where external_reference is not null and external_reference <> '';
create unique index transactions_fingerprint_uq on public.transactions(user_id, fingerprint) where fingerprint is not null;
create index transactions_user_date_idx on public.transactions(user_id, occurred_at desc);
create index transactions_user_account_idx on public.transactions(user_id, account_id, occurred_at desc);
create index transactions_user_category_idx on public.transactions(user_id, category_id, occurred_at desc);
create index budgets_user_period_idx on public.budgets(user_id, starts_at, ends_at);

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
do $$ declare t text; begin foreach t in array array['profiles','accounts','categories','transactions','budgets','recurring_transactions'] loop execute format('create trigger %I_updated_at before update on public.%I for each row execute function public.touch_updated_at()', t, t); end loop; end $$;

alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.recurring_transactions enable row level security;
-- Every policy is ownership based. Composite foreign keys prevent cross-user references.
create policy profiles_owner_all on public.profiles for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy accounts_owner_all on public.accounts for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy categories_owner_all on public.categories for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy transactions_owner_all on public.transactions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy budgets_owner_all on public.budgets for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy recurring_owner_all on public.recurring_transactions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Recommended RPC: create_transfer(user_id, source_id, destination_id, amount, currency, occurred_at, note).
-- It must validate ownership/currency and insert one transfer atomically. Do not implement as two client writes.
-- Derived values: account balance, budget spent, category totals, day/month grouping. Use SQL views/RPC with the
-- authenticated user's timezone; store only occurred_at UTC. Swift maps numeric to Decimal/String, never Double.
-- Realtime: enable only accounts, categories, transactions, budgets, and recurring_transactions after RLS tests.
