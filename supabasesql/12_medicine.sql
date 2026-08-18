-- ============================================================
-- 12 — Medicine tracker (CRUD + daily-dose check-off)
-- ============================================================
-- Safe to re-run. Only side effects: creates two new tables
-- (medicines, medicine_doses) and 7 new RPCs plus a couple of
-- helper functions. Nothing existing is touched.
--
-- Why this exists:
-- Many Amar Diet users are elderly people managing multiple daily
-- medicines (BP, sugar, thyroid, etc.). They asked for a screen
-- that mirrors the existing custom-meal-plan flow but for meds:
--   * catalogue row per medicine (name, form, strength, dose,
--     meal relation, scheduled times, start/end date, notes)
--   * one dose row per scheduled slot per day so we can answer
--     "did I take the 8 AM Metformin?" with a tap
--   * 7/30-day adherence summary + current streak so the dashboard
--     can show progress without extra UI work
--
-- Time-of-day grouping (morning / noon / afternoon / night) is
-- computed both on the client (so the UI previews instantly while
-- the user is editing) and stored on every dose row (so a later
-- schedule edit doesn't reclassify history).

-- ---------- 1. MEDICINE CATALOGUE ----------
create table if not exists public.medicines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  -- Bangla name is the headline label shown everywhere in the UI.
  name_bn text not null,
  -- Optional English / generic name (e.g. "Metformin").
  name_en text,
  -- Pill form. Free-text fallback "other" for niche formats.
  form text not null check (form in (
    'tablet','capsule','drop','syrup','injection','inhaler','cream','other'
  )),
  -- Free-text strength, e.g. "500 mg" or "5 mg/ml". Format isn't enforced
  -- so pharmacists can write what they wrote on the pack.
  strength text,
  -- Numeric dose per intake, e.g. 1, 0.5, 2.
  dose_amount numeric(6,2) not null default 1,
  -- Bangla unit suffix shown next to dose_amount. Defaults to "unit"
  -- so the UI never has to special-case missing data.
  dose_unit text not null default 'unit',
  -- When the pill should be taken relative to a meal.
  meal_relation text not null default 'any'
    check (meal_relation in (
      'before_food','with_food','after_food','empty_stomach','any'
    )),
  -- Schedule is an array of {time: 'HH:mm', bucket: 'morning'/'noon'/'afternoon'/'night'}.
  schedule jsonb not null default '[]'::jsonb,
  -- Course window. start_date defaults to today; end_date null means ongoing.
  start_date date not null default ((now() at time zone 'Asia/Dhaka')::date),
  end_date date,
  -- Optional accent colour for the row (hex string, e.g. '#5C6B4F').
  -- Null lets the UI pick the default ink tone.
  color text,
  -- Free-form user notes (doctor instructions, side-effects, refills).
  notes text,
  -- Soft-delete flag. We hard-delete on demand but keep the flag
  -- so the UI can offer "archive" without losing history forever.
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists medicines_user_active
  on public.medicines (user_id) where is_active;

create index if not exists medicines_user_dates
  on public.medicines (user_id, start_date, end_date);

alter table public.medicines enable row level security;
drop policy if exists "Users manage their own medicines" on public.medicines;
create policy "Users manage their own medicines"
  on public.medicines for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ---------- 2. PER-DOSE CHECK-OFF LOG ----------
create table if not exists public.medicine_doses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  medicine_id uuid not null references public.medicines(id) on delete cascade,
  dose_date date not null,
  scheduled_time time not null,
  -- bucket is duplicated from the medicine at insert time so editing
  -- the medicine later doesn't reclassify history.
  bucket text not null check (bucket in ('morning','noon','afternoon','night')),
  -- status: 'taken' = confirmed, 'skipped' = user explicitly skipped,
  -- 'missed' = auto-flagged past the scheduled time with no action.
  status text not null default 'taken'
    check (status in ('taken','skipped','missed')),
  -- Exact timestamp when the user confirmed. Null until logged.
  taken_at timestamptz,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists medicine_doses_user_date
  on public.medicine_doses (user_id, dose_date);

create index if not exists medicine_doses_medicine
  on public.medicine_doses (medicine_id, dose_date);

create unique index if not exists medicine_doses_unique
  on public.medicine_doses (medicine_id, dose_date, scheduled_time);

alter table public.medicine_doses enable row level security;
drop policy if exists "Users manage their own medicine doses" on public.medicine_doses;
create policy "Users manage their own medicine doses"
  on public.medicine_doses for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ---------- 3. AUTO-TOUCH updated_at ON MEDICINES ----------
create or replace function public.touch_medicines_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_medicines_touch on public.medicines;
create trigger trg_medicines_touch
  before update on public.medicines
  for each row execute function public.touch_medicines_updated_at();


-- ---------- 4. TIME-OF-DAY CLASSIFIER ----------
-- 5-11 morning, 11-15 noon, 15-19 afternoon, 19-5 night.
-- Called by both the SQL RPCs and the Flutter client (with the
-- identical thresholds) so the UI preview matches what's stored.
create or replace function public.classify_time_bucket(p_time time)
returns text
language sql
immutable
as $$
  select case
    when p_time >= '05:00'::time and p_time <  '11:00'::time then 'morning'
    when p_time >= '11:00'::time and p_time <  '15:00'::time then 'noon'
    when p_time >= '15:00'::time and p_time <  '19:00'::time then 'afternoon'
    else 'night'
  end;
$$;


-- ---------- 5. LIST MEDICINES ----------
create or replace function public.list_medicines()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(m) order by m.is_active desc, m.created_at desc)
    from (
      select m.id, m.user_id, m.name_bn, m.name_en, m.form, m.strength,
             m.dose_amount, m.dose_unit, m.meal_relation, m.schedule,
             m.start_date, m.end_date, m.color, m.notes,
             m.is_active, m.created_at, m.updated_at
      from public.medicines m
      where m.user_id = v_user
    ) m
  ), '[]'::jsonb);
end;
$$;


-- ---------- 6. CREATE MEDICINE ----------
create or replace function public.create_medicine(
  p_name_bn text,
  p_name_en text default null,
  p_form text default 'tablet',
  p_strength text default null,
  p_dose_amount numeric default 1,
  p_dose_unit text default 'unit',
  p_meal_relation text default 'any',
  p_schedule jsonb default '[]'::jsonb,
  p_start_date date default ((now() at time zone 'Asia/Dhaka')::date),
  p_end_date date default null,
  p_color text default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_user uuid := auth.uid();
  v_clean_schedule jsonb;
  v_entry jsonb;
  v_new_schedule jsonb := '[]'::jsonb;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  if p_name_bn is null or length(trim(p_name_bn)) = 0 then
    raise exception 'Medicine name is required';
  end if;
  if p_form not in ('tablet','capsule','drop','syrup','injection','inhaler','cream','other') then
    raise exception 'Invalid form';
  end if;
  if p_meal_relation not in ('before_food','with_food','after_food','empty_stomach','any') then
    raise exception 'Invalid meal relation';
  end if;

  -- Normalise schedule: each entry becomes {time: 'HH:mm', bucket: 'morning'/'noon'/...}
  -- so the UI never has to re-classify. Drop entries with missing/invalid times.
  if p_schedule is null or jsonb_typeof(p_schedule) <> 'array' then
    v_clean_schedule := '[]'::jsonb;
  else
    for v_entry in select * from jsonb_array_elements(p_schedule)
    loop
      if (v_entry ? 'time') and (v_entry->>'time') ~ '^[0-2][0-9]:[0-5][0-9]$' then
        v_new_schedule := v_new_schedule || jsonb_build_array(
          jsonb_build_object(
            'time',  (v_entry->>'time'),
            'bucket', public.classify_time_bucket(((v_entry->>'time')::time))
          )
        );
      end if;
    end loop;
    v_clean_schedule := v_new_schedule;
  end if;

  insert into public.medicines
    (user_id, name_bn, name_en, form, strength, dose_amount,
     dose_unit, meal_relation, schedule, start_date, end_date,
     color, notes, is_active)
  values
    (v_user,
     nullif(trim(p_name_bn), ''),
     nullif(trim(p_name_en), ''),
     p_form,
     nullif(trim(p_strength), ''),
     p_dose_amount,
     coalesce(nullif(trim(p_dose_unit), ''), 'unit'),
     p_meal_relation,
     v_clean_schedule,
     coalesce(p_start_date, ((now() at time zone 'Asia/Dhaka')::date)),
     p_end_date,
     nullif(trim(p_color), ''),
     nullif(trim(p_notes), ''),
     true)
  returning id into v_id;
  return v_id;
end;
$$;


-- ---------- 7. UPDATE MEDICINE ----------
-- Same shape as update_user_meal_plan — null params leave the column
-- unchanged, but explicit "clear_*" flags force a column to NULL.
-- Pass p_schedule as a jsonb array to replace the entire schedule.
create or replace function public.update_medicine(
  p_id uuid,
  p_name_bn text default null,
  p_name_en text default null,
  p_form text default null,
  p_strength text default null,
  p_dose_amount numeric default null,
  p_dose_unit text default null,
  p_meal_relation text default null,
  p_schedule jsonb default null,
  p_start_date date default null,
  p_end_date date default null,
  p_clear_end_date boolean default false,
  p_color text default null,
  p_notes text default null,
  p_is_active boolean default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_owner uuid;
  v_clean_schedule jsonb;
  v_entry jsonb;
  v_new_schedule jsonb := '[]'::jsonb;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  select user_id into v_owner from public.medicines where id = p_id;
  if v_owner is null then raise exception 'Medicine not found'; end if;
  if v_owner <> v_user then raise exception 'Not authorized'; end if;

  if p_schedule is not null then
    if jsonb_typeof(p_schedule) <> 'array' then
      raise exception 'Schedule must be a json array';
    end if;
    for v_entry in select * from jsonb_array_elements(p_schedule)
    loop
      if (v_entry ? 'time') and (v_entry->>'time') ~ '^[0-2][0-9]:[0-5][0-9]$' then
        v_new_schedule := v_new_schedule || jsonb_build_array(
          jsonb_build_object(
            'time',  (v_entry->>'time'),
            'bucket', public.classify_time_bucket(((v_entry->>'time')::time))
          )
        );
      end if;
    end loop;
    v_clean_schedule := v_new_schedule;
  end if;

  update public.medicines
    set name_bn       = coalesce(nullif(trim(p_name_bn), ''), name_bn),
        name_en       = case when p_name_en is not null
                             then nullif(trim(p_name_en), '') else name_en end,
        form          = coalesce(p_form, form),
        strength      = case when p_strength is not null
                             then nullif(trim(p_strength), '') else strength end,
        dose_amount   = coalesce(p_dose_amount, dose_amount),
        dose_unit     = coalesce(nullif(trim(p_dose_unit), ''), dose_unit),
        meal_relation = coalesce(p_meal_relation, meal_relation),
        schedule      = coalesce(v_clean_schedule, schedule),
        start_date    = coalesce(p_start_date, start_date),
        end_date      = case when p_clear_end_date then null
                             when p_end_date is not null then p_end_date
                             else end_date end,
        color         = case when p_color is not null
                             then nullif(trim(p_color), '') else color end,
        notes         = case when p_notes is not null
                             then nullif(trim(p_notes), '') else notes end,
        is_active     = coalesce(p_is_active, is_active)
  where id = p_id and user_id = v_user;
end;
$$;


-- ---------- 8. DELETE MEDICINE ----------
-- CASCADE removes every dose row thanks to the FK on medicine_doses.
create or replace function public.delete_medicine(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  delete from public.medicines
    where id = p_id and user_id = v_user;
end;
$$;


-- ---------- 9. GET TODAY'S DOSE TIMELINE ----------
-- Combines every active medicine's schedule with the dose log so
-- the UI gets a single, ordered list of pending / taken doses.
-- Past-due doses with no taken_at within 60 min are flagged 'missed'.
create or replace function public.get_medicine_doses(p_date date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := coalesce(p_date, ((now() at time zone 'Asia/Dhaka')::date));
  v_now   time := (now() at time zone 'Asia/Dhaka')::time;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(row) order by row.sort_time, row.medicine_name)
    from (
      -- Expand every (medicine, schedule-time) pair into one row.
      with slots as (
        select m.id as medicine_id, m.name_bn, m.name_en, m.form, m.strength,
               m.dose_amount, m.dose_unit, m.meal_relation, m.color,
               m.notes as medicine_notes, m.is_active,
               (s->>'time')::time as scheduled_time,
               s->>'bucket' as bucket
        from public.medicines m
        cross join lateral jsonb_array_elements(m.schedule) s
        where m.user_id = v_user
          and m.is_active = true
          and m.start_date <= v_today
          and (m.end_date is null or m.end_date >= v_today)
      ),
      merged as (
        select s.medicine_id, s.name_bn, s.name_en, s.form, s.strength,
               s.dose_amount, s.dose_unit, s.meal_relation, s.color,
               s.medicine_notes, s.scheduled_time, s.bucket,
               d.id as dose_id, d.status, d.taken_at, d.note,
               case when d.id is not null then d.scheduled_time end as sort_time
        from slots s
        left join public.medicine_doses d
          on d.medicine_id = s.medicine_id
         and d.dose_date = v_today
         and d.scheduled_time = s.scheduled_time
      )
      select
        medicine_id, name_bn, name_en, form, strength,
        dose_amount, dose_unit, meal_relation, color, medicine_notes,
        scheduled_time, bucket, dose_id, status, taken_at, note,
        case
          when dose_id is not null then scheduled_time
          else scheduled_time
        end as sort_time,
        -- a stable "false" sort key so jsonb_agg's outer ORDER BY works.
        name_bn as medicine_name,
        case
          when dose_id is not null then true   -- already logged
          when status = 'missed' then true
          else false
        end as is_resolved,
        case
          when dose_id is null
               and v_now > scheduled_time
               and (scheduled_time + interval '60 min') < ((now() at time zone 'Asia/Dhaka')::time)
            then true
          else false
        end as is_overdue
      from merged
    ) row
  ), '[]'::jsonb);
end;
$$;


-- ---------- 10. MARK A DOSE ----------
-- Idempotent. Creates the row on first call, updates on subsequent.
-- Pass p_status to override ('taken', 'skipped', 'missed').
create or replace function public.mark_dose(
  p_medicine_id uuid,
  p_dose_date date,
  p_scheduled_time time,
  p_status text default 'taken',
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_owner_med uuid;
  v_bucket text;
  v_id uuid;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;

  -- Verify ownership of the medicine.
  select user_id into v_owner_med from public.medicines where id = p_medicine_id;
  if v_owner_med is null then raise exception 'Medicine not found'; end if;
  if v_owner_med <> v_user then raise exception 'Not authorized'; end if;
  if p_status not in ('taken','skipped','missed') then
    raise exception 'Invalid status';
  end if;

  v_bucket := public.classify_time_bucket(p_scheduled_time);

  insert into public.medicine_doses
    (user_id, medicine_id, dose_date, scheduled_time, bucket,
     status, taken_at, note)
  values
    (v_user, p_medicine_id, p_dose_date, p_scheduled_time, v_bucket,
     p_status, case when p_status = 'taken' then now() else null end,
     nullif(trim(p_note), ''))
  on conflict (medicine_id, dose_date, scheduled_time) do update
    set status   = excluded.status,
        taken_at = case when excluded.status = 'taken' then now() else medicine_doses.taken_at end,
        note     = excluded.note
  returning id into v_id;
  return v_id;
end;
$$;


-- ---------- 11. ADHERENCE SUMMARY ----------
-- Returns totals + percentage + a "current streak" — consecutive days
-- (ending today) where every scheduled dose was either taken or
-- explicitly skipped (i.e. neither missed nor pending).
-- Drop any prior overloads so we can safely change the return type
-- (jsonb vs table vs setof record). Running 12_*.sql twice should
-- be idempotent, so we drop first then re-create.
drop function if exists public.get_medicine_adherence(integer);
drop function if exists public.get_medicine_adherence(int);
create or replace function public.get_medicine_adherence(p_days int default 7)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_total int := 0;
  v_taken int := 0;
  v_skipped int := 0;
  v_missed int := 0;
  v_pct numeric(5,1) := 0;
  v_streak int := 0;
  v_today date := ((now() at time zone 'Asia/Dhaka')::date);
begin
  if v_user is null then raise exception 'Not authenticated'; end if;

  -- Aggregate across the requested window (default 7 days, max 90).
  select
    count(*),
    count(*) filter (where d.status = 'taken'),
    count(*) filter (where d.status = 'skipped'),
    count(*) filter (where d.status = 'missed')
  into v_total, v_taken, v_skipped, v_missed
  from public.medicine_doses d
  where d.user_id = v_user
    and d.dose_date >= (v_today - greatest(p_days, 1) + 1)
    and d.dose_date <= v_today;

  if v_total > 0 then
    v_pct := round((v_taken::numeric / v_total) * 100, 1);
  end if;

  -- Streak: walk backwards from today; a day counts when nothing is
  -- unresolved. Stop at the first day with unresolved doses.
  with daily as (
    select d.dose_date::date as d,
           count(*) filter (where d.status = 'taken' or d.status = 'skipped') as resolved,
           count(*) as total
    from public.medicine_doses d
    where d.user_id = v_user
      and d.dose_date <= v_today
    group by d.dose_date
  )
  select coalesce((
    select count(*) from (
      select d.dose_date as d,
             case when count(*) filter (where d.status = 'taken' or d.status = 'skipped') = count(*)
                  then 1 else 0 end as clean
      from public.medicine_doses d
      where d.user_id = v_user
        and d.dose_date <= v_today
      group by d.dose_date
      having count(*) > 0
      order by d.dose_date desc
    ) s
    where s.clean = 1
  ), 0) into v_streak
  from (select 1) dummy;

  -- A cleaner streak computation: find the longest run of days ending
  -- today where every logged dose is taken or skipped. Walk one day at a time.
  v_streak := 0;
  for i in 0..greatest(p_days - 1, 0) loop
    declare day_total int;
            day_done  int;
            day_date  date := v_today - i;
    begin
      select count(*),
             count(*) filter (where status = 'taken' or status = 'skipped')
        into day_total, day_done
        from public.medicine_doses
        where user_id = v_user
          and dose_date = day_date;
      if day_total = day_done then
        v_streak := v_streak + 1;
      else
        exit;
      end if;
    end;
  end loop;

  return jsonb_build_object(
    'total_doses',        v_total,
    'taken',              v_taken,
    'skipped',            v_skipped,
    'missed',             v_missed,
    'taken_pct',          v_pct,
    'current_streak_days', v_streak,
    'window_days',        greatest(p_days, 1)
  );
end;
$$;
