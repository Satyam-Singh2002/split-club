-- Run once in a NEW Supabase project's SQL Editor. Re-running this script is
-- safe for the same schema; it does not delete results or uploaded screenshots.
-- No Supabase Auth, participant accounts, server, secret key or paid feature.
--
-- Trust model: anyone with the public website may submit under any name.
-- Runs are public; evidence is optional and public by URL. Crop private details
-- before uploading. Only the organizer's dashboard can edit/delete a result.
-- The 10-submissions-per-name-per-UTC-day rule is a convenience limit, not
-- identity verification or a robust bot/abuse defense. Anonymous uploads can
-- consume the storage quota; remove abandoned uploads in the dashboard.
-- Requires UTF8 and PostgreSQL's standard ICU root collation und-x-icu.

begin;

create table if not exists public.runs (
  id uuid primary key default gen_random_uuid(),
  runner_name text not null,
  runner_key text generated always as (
    -- Match JS cleanSpace().normalize('NFKC').toLowerCase().normalize('NFC').
    -- Use the ECMAScript whitespace set; POSIX [:space:] differs for NBSP/BOM.
    normalize(lower(normalize(
      btrim(regexp_replace(runner_name,
        U&'[\0009-\000D\0020\00A0\1680\2000-\200A\2028\2029\202F\205F\3000\FEFF]+', ' ', 'g')),
      NFKC) collate pg_catalog."und-x-icu"), NFC)
  ) stored,
  category_id text not null check (category_id in ('3k', '5k', '10k', 'half')),
  run_date date not null check (run_date >= date '2000-01-01'),
  duration_seconds integer not null check (duration_seconds between 1 and 86400),
  activity_url text,
  evidence_path text unique,
  created_at timestamptz not null default now(),
  constraint runs_name_length check (char_length(runner_name) between 2 and 60),
  constraint runs_name_characters check (runner_name !~ '[[:cntrl:]<>]'),
  constraint runs_activity_url check (
    activity_url is null or (
      char_length(activity_url) <= 2048 and
      activity_url ~ '^https://[^[:space:]/?#@]+([/?#][^[:space:]]*)?$'
    )
  ),
  constraint runs_evidence_path check (
    evidence_path is null or
    evidence_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$'
  ),
  constraint runs_no_identical_duplicates unique (runner_key, category_id, run_date, duration_seconds)
);

create index if not exists runs_recent_idx on public.runs (created_at desc, id desc);
create index if not exists runs_runner_created_idx on public.runs (runner_key, created_at);

alter table public.runs enable row level security;
revoke all on table public.runs from public, anon, authenticated;
grant usage on schema public to anon;
grant select on table public.runs to anon;
-- The service role remains usable only from the organizer's protected tools.
grant all on table public.runs to service_role;

drop policy if exists "Anyone can read run results" on public.runs;
create policy "Anyone can read run results" on public.runs
  for select to anon using (true);
-- Intentionally no client INSERT, UPDATE or DELETE policies.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('run-evidence', 'run-evidence', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can add a run screenshot" on storage.objects;
create policy "Anyone can add a run screenshot" on storage.objects
  for insert to anon with check (
    bucket_id = 'run-evidence' and
    name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$'
  );
-- No listing, overwrite, update or delete policy. Public object GETs are served
-- by Storage; public does not grant object listing or writes. Existing project
-- policies must not independently grant broader storage permissions.

create or replace function public.submit_run(
  p_runner_name text,
  p_category_id text,
  p_run_date date,
  p_duration_seconds integer,
  p_activity_url text default null,
  p_evidence_path text default null
) returns public.runs
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_runner_name text;
  v_runner_key text;
  v_activity_url text;
  v_saved public.runs;
begin
  if p_runner_name is null then
    raise exception 'Enter a runner name.';
  end if;
  v_runner_name := normalize(pg_catalog.btrim(pg_catalog.regexp_replace(p_runner_name,
    U&'[\0009-\000D\0020\00A0\1680\2000-\200A\2028\2029\202F\205F\3000\FEFF]+', ' ', 'g')), NFC);
  if v_runner_name ~ '[[:cntrl:]<>]' then
    raise exception 'Use a plain-text runner name without markup or control characters.';
  end if;
  if pg_catalog.char_length(v_runner_name) not between 2 and 60 then
    raise exception 'Runner names must contain 2 to 60 characters.';
  end if;
  -- normalize() uses PostgreSQL's special SQL syntax and resolves to pg_catalog
  -- even with the empty search_path. ICU root casing avoids locale-specific
  -- lower() differences from JavaScript, such as dotted I and final Greek sigma.
  v_runner_key := normalize(pg_catalog.lower(normalize(v_runner_name, NFKC)
    collate pg_catalog."und-x-icu"), NFC);
  if p_category_id is null or p_category_id not in ('3k', '5k', '10k', 'half') then
    raise exception 'Choose a 3K, 5K, 10K or half marathon category.';
  end if;
  -- A local calendar day can be ahead of UTC. Browsers reject dates later than
  -- their local today; the backend permits UTC tomorrow for this time-zone gap.
  if p_run_date is null or p_run_date < date '2000-01-01' or p_run_date > current_date + 1 then
    raise exception 'Choose a valid run date from 2000 onward, no later than today.';
  end if;
  if p_duration_seconds is null or p_duration_seconds not between 1 and 86400 then
    raise exception 'Enter a completion time greater than zero and no longer than 24 hours.';
  end if;
  v_activity_url := nullif(pg_catalog.btrim(p_activity_url), '');
  if v_activity_url is not null and (
    pg_catalog.char_length(v_activity_url) > 2048 or
    v_activity_url !~ '^https://[^[:space:]/?#@]+([/?#][^[:space:]]*)?$'
  ) then
    raise exception 'Activity links must be valid HTTPS links without login credentials.';
  end if;
  if p_evidence_path is not null then
    if p_evidence_path !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$' then
      raise exception 'The screenshot filename is invalid. Upload it again.';
    end if;
    if not exists (
      select 1 from storage.objects
      where bucket_id = 'run-evidence' and name = p_evidence_path
    ) then
      raise exception 'The screenshot was not uploaded. Please upload it again.';
    end if;
  end if;

  -- Serialize submissions for the canonical name, including concurrent tabs,
  -- so the daily cap cannot be exceeded by simultaneous requests.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_runner_key, 0));
  if exists (
    select 1 from public.runs
    where runner_key = v_runner_key and category_id = p_category_id
      and run_date = p_run_date and duration_seconds = p_duration_seconds
  ) then
    raise exception 'This run has already been submitted. Check the leaderboard.';
  end if;
  if (select pg_catalog.count(*) from public.runs
      where runner_key = v_runner_key and created_at >= current_date) >= 10 then
    raise exception 'This name has reached 10 submissions today. Ask the organizer for help.';
  end if;
  if p_evidence_path is not null and exists (
    select 1 from public.runs where evidence_path = p_evidence_path
  ) then
    raise exception 'This screenshot has already been attached to a run.';
  end if;

  insert into public.runs (runner_name, category_id, run_date, duration_seconds, activity_url, evidence_path)
  values (v_runner_name, p_category_id, p_run_date, p_duration_seconds, v_activity_url, p_evidence_path)
  returning * into v_saved;
  return v_saved;
end;
$$;

-- Postgres otherwise makes new functions executable by PUBLIC by default.
revoke all on function public.submit_run(text, text, date, integer, text, text) from public, anon, authenticated;
grant execute on function public.submit_run(text, text, date, integer, text, text) to anon;

commit;

-- Organizer corrections: use the Supabase Table Editor while signed in to your
-- personal organizer account. Never put a secret/service_role key in config.js.
-- To suspend incoming submissions, run both statements below in SQL Editor:
-- revoke execute on function public.submit_run(text, text, date, integer, text, text) from anon;
-- drop policy if exists "Anyone can add a run screenshot" on storage.objects;
