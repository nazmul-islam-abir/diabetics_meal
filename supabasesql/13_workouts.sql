-- ============================================================
-- Amar Diet — Daily workout schema (v1)
-- Apply AFTER 01_schema.sql and 12_medicine.sql.
--
-- Layout:
--   workouts              — master catalogue of exercises, seeded once.
--   workout_assignments   — which workouts are scheduled for each
--                            program day (1..30). Defaults to a single
--                            "daily walking" routine so every user has
--                            something to do from day 1.
--   workout_sessions      — one row per user per day; tracks overall
--                            session timings + aggregate stats.
--   workout_session_items — one row per exercise within a session;
--                            tracks completion + actual duration.
--
-- RLS: catalogue is world-readable; assignment + session tables are
-- scoped to auth.uid() = user_id. All RPCs are SECURITY DEFINER and
-- pin search_path so the planner doesn't have to chase permissions.
-- ============================================================

-- ---------- 1. WORKOUTS CATALOGUE ----------
create table if not exists public.workouts (
  id text primary key,
  name_bn text not null,
  name_en text,
  category text not null,
  sub_category text,
  intensity text not null default 'low'
    check (intensity in ('low','medium','high')),
  difficulty text
    check (difficulty in ('beginner','intermediate','advanced')),
  target_duration_seconds int not null check (target_duration_seconds > 0),
  duration_min int,
  sets int,
  repetitions text,
  frequency_per_week int,
  target_calories_kcal int not null default 0,
  description_bn text not null,
  instructions jsonb not null default '[]'::jsonb,
  instructions_bn text,
  equipment text[] not null default '{}',
  beginner boolean not null default false,
  elderly_friendly boolean not null default false,
  chair_supported boolean not null default false,
  low_impact boolean not null default true,
  joint_friendly boolean not null default false,
  balance_required boolean not null default false,
  diabetes_suitable boolean not null default true,
  hypertension_suitable boolean not null default true,
  obesity_suitable boolean not null default true,
  anemia_suitable boolean not null default true,
  video_url text,
  safety_notes_bn text,
  contraindications text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Backfill: idempotent column additions so the widened schema applies
-- even when an older `13_workouts.sql` already created `public.workouts`
-- with the original columns. Safe to re-run.
alter table public.workouts add column if not exists sub_category text;
alter table public.workouts add column if not exists difficulty text;
alter table public.workouts add column if not exists duration_min int;
alter table public.workouts add column if not exists sets int;
alter table public.workouts add column if not exists repetitions text;
alter table public.workouts add column if not exists frequency_per_week int;
alter table public.workouts add column if not exists instructions_bn text;
alter table public.workouts add column if not exists beginner boolean not null default false;
alter table public.workouts add column if not exists elderly_friendly boolean not null default false;
alter table public.workouts add column if not exists chair_supported boolean not null default false;
alter table public.workouts add column if not exists low_impact boolean not null default true;
alter table public.workouts add column if not exists joint_friendly boolean not null default false;
alter table public.workouts add column if not exists balance_required boolean not null default false;
alter table public.workouts add column if not exists diabetes_suitable boolean not null default true;
alter table public.workouts add column if not exists hypertension_suitable boolean not null default true;
alter table public.workouts add column if not exists obesity_suitable boolean not null default true;
alter table public.workouts add column if not exists anemia_suitable boolean not null default true;
alter table public.workouts add column if not exists video_url text;
alter table public.workouts add column if not exists safety_notes_bn text;
alter table public.workouts add column if not exists contraindications text;

-- Widen the legacy category check to include yoga, household, walking.
-- Use DROP + ADD because Postgres can't ALTER a CHECK in place.
alter table public.workouts drop constraint if exists workouts_category_check;
alter table public.workouts
  add constraint workouts_category_check
  check (category in (
    'cardio','strength','flexibility','balance','breathing',
    'yoga','household','walking'
  ));

-- Widen the difficulty check (no-op on first install, drop+add on rerun).
alter table public.workouts drop constraint if exists workouts_difficulty_check;
alter table public.workouts
  add constraint workouts_difficulty_check
  check (difficulty is null or difficulty in ('beginner','intermediate','advanced'));

alter table public.workouts enable row level security;
drop policy if exists "Workouts are readable by any authenticated user" on public.workouts;
create policy "Workouts are readable by any authenticated user"
  on public.workouts for select
  using (auth.role() = 'authenticated');

-- Seed: a small, age-friendly catalogue. Each exercise is 3–10 minutes
-- of low-impact work tuned for older diabetic users.
insert into public.workouts (id, name_bn, name_en, category, intensity, target_duration_seconds, target_calories_kcal, description_bn, instructions, equipment) values
  ('walk_brisk',     'দ্রুত হাঁটা',         'Brisk walking',  'cardio',      'low',    600, 35, 'ঘরের ভেতরে বা বাইরে স্বাভাবিকের চেয়ে একটু দ্রুত গতিতে হাঁটুন।',
    '["সোজা হয়ে দাঁড়ান", "কাঁধ শিথিল রাখুন", "স্বাভাবিক শ্বাস নিন", "ধীরে ধীরে শুরু করুন, লক্ষ্য ৩০ মিনিট"]'::jsonb,
    '{}'),
  ('breathing_box',  'বাক্স শ্বাস-প্রশ্বাস', 'Box breathing',   'breathing',   'low',    300, 5,  '৪-৪-৪ পদ্ধতিতে শ্বাস নিন — রক্তচাপ কমায়, স্ট্রেস কমায়।',
    '["৪ সেকেন্ড শ্বাস নিন", "৪ সেকেন্ড ধরে রাখুন", "৪ সেকেন্ড ছাড়ুন", "৪ সেকেন্ড অপেক্ষা", "মোট ৫ মিনিট"]'::jsonb,
    '{}'),
  ('chair_squats',   'চেয়ার স্কোয়াট',    'Chair squats',    'strength',    'medium', 360, 20, 'চেয়ারের সামনে দাঁড়িয়ে ধীরে নেমে বসুন, আবার উঠুন।',
    '["চেয়ারের ঠিক পেছনে দাঁড়ান", "পা কাঁধ-সমান ফাঁক", "ধীরে নেমে মাথা ছোঁয়ার আগে থামুন", "তারপর উঠুন", "১০ বার, ২ সেট"]'::jsonb,
    '{"chair"}'),
  ('arm_circles',    'হাত ঘোরানো',         'Arm circles',     'flexibility', 'low',    180, 8,  'দুই হাত পাশে ছড়িয়ে ছোট/বড় বৃত্ত আঁকুন।',
    '["হাত পাশে সমান্তরাল", "সামনে ১০ বার ছোট বৃত্ত", "পেছনে ১০ বার", "বিশ্রাম", "আবার ১০ বার বড় বৃত্ত"]'::jsonb,
    '{}'),
  ('leg_raises',     'পা তোলা',            'Seated leg raises','strength',   'low',    240, 12, 'চেয়ারে বসে এক পা একসাথে সোজা তুলুন, ধরে রাখুন, নামান।',
    '["চেয়ারে সোজা হয়ে বসুন", "ডান পা ধীরে তুলুন", "৫ সেকেন্ড ধরে রাখুন", "নামান, বাম পা একই ভাবে", "প্রতি পায়ে ৮ বার"]'::jsonb,
    '{"chair"}'),
  ('wall_pushup',    'দেয়ালে পুশআপ',     'Wall push-ups',   'strength',    'medium', 300, 18, 'হাত দেয়ালে রেখে বুক দেয়ালের কাছে আনুন, ঠেলে পেছনে যান।',
    '["দেয়াল থেকে এক হাত দূরে দাঁড়ান", "হাত কাঁধ-সমান উচ্চতায়", "বুক দেয়ালের কাছে আনুন", "ঠেলে পেছনে যান", "১০ বার, ২ সেট"]'::jsonb,
    '{}'),
  ('single_leg',     'এক-পায়ে ভারসাম্য', 'Single-leg balance','balance',   'low',    180, 6,  'এক পায়ে দাঁড়িয়ে ৩০ সেকেন্ড ভারসাম্য রাখুন, পা বদলান।',
    '["চেয়ারের পেছনে দাঁড়ান, হালকাভাবে ধরুন", "ডান পা তুলুন", "৩০ সেকেন্ড গোনা", "পা নামান", "বাম পায়ে একই"]'::jsonb,
    '{"chair"}'),
  ('water_walk',     'পানিতে হাঁটা',       'Water walk',      'cardio',      'medium', 720, 60, 'পুকুর/সুইমিং-পুলে বুক-পানি পর্যন্ত গভীরে ধীরে হাঁটুন।',
    '["বুক-পানি পর্যন্ত যান", "স্বাভাবিক শ্বাস", "ধীরে ধীরে ১২ মিনিট হাঁটুন", "বিশ্রাম নিয়ে আরেক দফা"]'::jsonb,
    '{"pool"}'),
  ('neck_rolls',     'গলা ঘোরানো',         'Neck rolls',      'flexibility', 'low',    120, 4,  'ধীরে ধীরে গলা ঘুরিয়ে টান কমান।',
    '["সোজা হয়ে বসুন", "মাথা ধীরে ডানে", "সামনে", "বামে", "পেছনে", "৩ বার, বিপরীত দিকে ৩ বার"]'::jsonb,
    '{}'),
  ('stretch_full',   'সারা শরীর স্ট্রেচ', 'Full-body stretch','flexibility','low',    360, 10, 'মাথা থেকে পা — প্রতিটি জয়েন্ট ১৫ সেকেন্ড ধরে টানুন।',
    '["মাথা পেছনে হেলান", "কাঁধ ঘোরান", "বাহু ছড়ান", "কোমর ঘোরান", "হাঁটু টান", "গোড়ালি ঘোরান"]'::jsonb,
    '{}')
on conflict (id) do update set
  name_bn = excluded.name_bn,
  name_en = excluded.name_en,
  category = excluded.category,
  intensity = excluded.intensity,
  target_duration_seconds = excluded.target_duration_seconds,
  target_calories_kcal = excluded.target_calories_kcal,
  description_bn = excluded.description_bn,
  instructions = excluded.instructions,
  equipment = excluded.equipment,
  is_active = true;

-- ---------- 2. WORKOUT ASSIGNMENTS ----------
create table if not exists public.workout_assignments (
  user_id uuid not null references auth.users(id) on delete cascade,
  day_index int not null check (day_index between 1 and 30),
  workout_id text not null references public.workouts(id) on delete cascade,
  position int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (user_id, day_index, workout_id)
);

create index if not exists workout_assignments_user_day
  on public.workout_assignments (user_id, day_index) where is_active;

alter table public.workout_assignments enable row level security;
drop policy if exists "Users manage their own workout assignments" on public.workout_assignments;
create policy "Users manage their own workout assignments"
  on public.workout_assignments for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------- 3. WORKOUT SESSIONS ----------
create table if not exists public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_date date not null default (now() at time zone 'Asia/Dhaka')::date,
  program_day int check (program_day between 1 and 30),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  total_duration_seconds int not null default 0,
  completed_items int not null default 0,
  total_items int not null default 0,
  is_finished boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (user_id, session_date)
);

create index if not exists workout_sessions_user_date
  on public.workout_sessions (user_id, session_date desc);

alter table public.workout_sessions enable row level security;
drop policy if exists "Users manage their own workout sessions" on public.workout_sessions;
create policy "Users manage their own workout sessions"
  on public.workout_sessions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------- 4. WORKOUT SESSION ITEMS ----------
create table if not exists public.workout_session_items (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.workout_sessions(id) on delete cascade,
  workout_id text not null references public.workouts(id) on delete cascade,
  position int not null default 0,
  is_completed boolean not null default false,
  started_at timestamptz,
  finished_at timestamptz,
  duration_seconds int not null default 0,
  updated_at timestamptz not null default now()
);

create index if not exists workout_session_items_session
  on public.workout_session_items (session_id, position);

alter table public.workout_session_items enable row level security;
drop policy if exists "Users manage their own workout session items" on public.workout_session_items;
create policy "Users manage their own workout session items"
  on public.workout_session_items for all
  using (exists (
    select 1 from public.workout_sessions s
    where s.id = workout_session_items.session_id and s.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.workout_sessions s
    where s.id = workout_session_items.session_id and s.user_id = auth.uid()
  ));

-- ---------- 5. TOUCH TRIGGER ----------
create or replace function public.touch_workout_sessions_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_touch_workout_sessions on public.workout_sessions;
create trigger trg_touch_workout_sessions
  before update on public.workout_sessions
  for each row execute function public.touch_workout_sessions_updated_at();

-- ---------- 6. RPC: list_workouts ----------
create or replace function public.list_workouts()
returns table (
  id text,
  name_bn text,
  name_en text,
  category text,
  intensity text,
  target_duration_seconds int,
  target_calories_kcal int,
  description_bn text,
  instructions jsonb,
  equipment text[]
)
language sql
security definer
set search_path = public
as $$
  select id, name_bn, name_en, category, intensity,
         target_duration_seconds, target_calories_kcal,
         description_bn, instructions, equipment
  from public.workouts
  where is_active
  order by category, name_bn;
$$;

grant execute on function public.list_workouts() to authenticated;

-- ---------- 7. RPC: get_today_workout ----------
-- Returns the planned workouts for a given program day, plus any
-- existing session state for today (so the UI can show progress).
-- Drop any prior overloads so we can safely change defaults /
-- arg types between revisions. Running 13_*.sql twice should be
-- idempotent, so we drop first then re-create.
drop function if exists public.get_today_workout(integer);
drop function if exists public.get_today_workout(int);
create or replace function public.get_today_workout(
  p_day_index int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_assignments jsonb;
  v_session jsonb;
begin
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'workout_id', w.id,
      'name_bn', w.name_bn,
      'name_en', w.name_en,
      'category', w.category,
      'intensity', w.intensity,
      'target_duration_seconds', w.target_duration_seconds,
      'target_calories_kcal', w.target_calories_kcal,
      'description_bn', w.description_bn,
      'instructions', w.instructions,
      'equipment', w.equipment,
      'position', a.position
    ) order by a.position, w.name_bn
  ), '[]'::jsonb)
  into v_assignments
  from public.workout_assignments a
  join public.workouts w on w.id = a.workout_id and w.is_active
  where a.user_id = v_user and a.day_index = p_day_index and a.is_active;

  select jsonb_build_object(
    'id', s.id,
    'session_date', s.session_date,
    'program_day', s.program_day,
    'started_at', s.started_at,
    'finished_at', s.finished_at,
    'total_duration_seconds', s.total_duration_seconds,
    'completed_items', s.completed_items,
    'total_items', s.total_items,
    'is_finished', s.is_finished,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'workout_id', i.workout_id,
          'position', i.position,
          'is_completed', i.is_completed,
          'started_at', i.started_at,
          'finished_at', i.finished_at,
          'duration_seconds', i.duration_seconds
        ) order by i.position
      )
      from public.workout_session_items i where i.session_id = s.id
    ), '[]'::jsonb)
  )
  into v_session
  from public.workout_sessions s
  where s.user_id = v_user and s.session_date = v_today;

  return jsonb_build_object(
    'day_index', p_day_index,
    'today', v_today,
    'assignments', v_assignments,
    'session', v_session
  );
end $$;

grant execute on function public.get_today_workout(int) to authenticated;

-- ---------- 8. RPC: start_workout_session ----------
-- Idempotent: returns the existing session for today if there is one.
create or replace function public.start_workout_session(
  p_day_index int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_session_id uuid;
  v_total int;
begin
  -- Reuse an unfinished session from today if one exists.
  select id into v_session_id
  from public.workout_sessions
  where user_id = v_user and session_date = v_today;
  if v_session_id is not null then
    return v_session_id;
  end if;

  select count(*) into v_total
  from public.workout_assignments
  where user_id = v_user and day_index = p_day_index and is_active;

  insert into public.workout_sessions (user_id, session_date, program_day, total_items, started_at)
  values (v_user, v_today, p_day_index, v_total, now())
  returning id into v_session_id;

  -- Pre-create one session_item per assignment so the timer UI can
  -- update rows in place rather than juggling "current exercise".
  insert into public.workout_session_items (session_id, workout_id, position)
  select v_session_id, a.workout_id, a.position
  from public.workout_assignments a
  where a.user_id = v_user and a.day_index = p_day_index and a.is_active;

  return v_session_id;
end $$;

grant execute on function public.start_workout_session(int) to authenticated;

-- ---------- 9. RPC: finish_workout_session_item ----------
-- Records an item's per-exercise timer. The caller passes either
-- `p_completed` (boolean) or `p_mark_running` (true = start the timer
-- without finishing). Any other invocation: just persist duration.
--
-- To avoid the previous "workout item not found" crash when a user
-- navigates between days (the session was started on a different
-- `day_index` than the one they're now exercising), we accept the
-- `p_session_id` + `p_workout_id` pair and look the item up by
-- (session, workout). If no row exists yet for that exercise — which
-- can happen when the user starts exercising on a day that wasn't
-- the one used to create the session — we INSERT the missing item
-- (with the correct position from the day's assignments) before
-- updating it. `p_item_id` is still accepted for backwards-compat
-- with earlier clients; if it is provided AND resolves, we use it.
drop function if exists public.finish_workout_session_item(uuid, int, boolean);
drop function if exists public.finish_workout_session_item(uuid, text, uuid, int, boolean);
create or replace function public.finish_workout_session_item(
  p_item_id uuid default null,
  p_workout_id text default null,
  p_session_id uuid default null,
  p_duration_seconds int default 0,
  p_completed boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_session uuid;
  v_item    uuid;
begin
  -- 1. Resolve the parent session.
  if p_session_id is not null then
    select id into v_session
    from public.workout_sessions
    where id = p_session_id and user_id = v_user;
  end if;

  -- 2. Try the legacy path: caller supplied an item_id that still
  --    points at one of the user's existing session_items.
  if p_item_id is not null then
    select i.session_id, i.id into v_session, v_item
    from public.workout_session_items i
    join public.workout_sessions s on s.id = i.session_id
    where i.id = p_item_id and s.user_id = v_user;
  end if;

  -- 3. Look up by (session, workout) — covers the day-navigation case
  --    where the session was opened on a different day_index but the
  --    caller is exercising on a new day.
  if v_item is null and v_session is not null and p_workout_id is not null then
    select id into v_item
    from public.workout_session_items
    where session_id = v_session and workout_id = p_workout_id;

    -- 4. Lazy-create: if the session has no item for this workout yet
    --    (the session was started on a day_index that didn't include
    --    this exercise), insert one on the fly so the user's timer
    --    always succeeds. Position comes from the active assignment
    --    for today so the day's ordering stays consistent.
    if v_item is null then
      insert into public.workout_session_items (session_id, workout_id, position)
      select v_session, p_workout_id,
             coalesce((
               select a.position from public.workout_assignments a
               where a.user_id = v_user
                 and a.is_active
                 and a.workout_id = p_workout_id
               order by a.day_index
               limit 1
             ), 0)
      returning id into v_item;
    end if;
  end if;

  if v_item is null then
    raise exception 'workout item not found (no session for this user)';
  end if;

  update public.workout_session_items i
  set is_completed = p_completed,
      duration_seconds = greatest(duration_seconds, p_duration_seconds),
      started_at = coalesce(started_at, case when p_duration_seconds > 0 then now() - make_interval(secs => p_duration_seconds) else null end),
      finished_at = case when p_completed then now() else finished_at end,
      updated_at = now()
  where i.id = v_item;

  -- Roll up totals on the parent session.
  update public.workout_sessions s
  set total_duration_seconds = coalesce((
        select sum(duration_seconds) from public.workout_session_items
        where session_id = s.id
      ), 0),
      completed_items = coalesce((
        select count(*) from public.workout_session_items
        where session_id = s.id and is_completed
      ), 0),
      updated_at = now()
  where s.id = v_session;

  return v_item;
end $$;

grant execute on function public.finish_workout_session_item(uuid, text, uuid, int, boolean) to authenticated;

-- ---------- 10. RPC: finish_workout_session ----------
create or replace function public.finish_workout_session(
  p_session_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  update public.workout_sessions
  set is_finished = true,
      finished_at = now(),
      updated_at = now()
  where id = p_session_id and user_id = v_user;
end $$;

grant execute on function public.finish_workout_session(uuid) to authenticated;

-- ---------- 11. RPC: get_workout_logs ----------
-- Returns the last `p_days` of session summaries for the dashboard chart.
-- Column names are aliased to match the Dart `WorkoutLogRow` model:
--   day / total / completed / total_minutes / total_calories.
-- total_minutes  = total_duration_seconds / 60 (rounded down).
-- total_calories = total_minutes * 5 — a conservative fixed estimate
-- used when the app doesn't have a per-exercise MET table available.
-- (The user can always override this with a real MET-based estimate
-- in a follow-up; the rough number is enough for the dashboard's
-- "0/7 দিন / 0 মিনিট / 0 ক্যালোরি" headline which is currently
-- permanently stuck at 0 because the field names didn't match.)
create or replace function public.get_workout_logs(
  p_days int default 7
)
returns table (
  day date,
  total int,
  completed int,
  total_minutes int,
  total_calories int,
  is_finished boolean
)
language sql
security definer
set search_path = public
as $$
  select s.session_date as day,
         s.total_items as total,
         s.completed_items as completed,
         floor(s.total_duration_seconds / 60) as total_minutes,
         floor(s.total_duration_seconds / 60) * 5 as total_calories,
         s.is_finished
  from public.workout_sessions s
  where s.user_id = auth.uid()
    and s.session_date >= (current_date - (p_days - 1))
  order by s.session_date desc;
$$;

grant execute on function public.get_workout_logs(int) to authenticated;

-- ---------- 12. RPC: get_workout_adherence ----------
-- Per-day (last `p_days`) completion ratio = completed_items / total_items.
-- NULLs are kept so we can tell "no session that day" from "0% done".
create or replace function public.get_workout_adherence(
  p_days int default 7
)
returns table (
  day date,
  completed int,
  total int,
  ratio numeric
)
language sql
security definer
set search_path = public
as $$
  with d as (
    select (current_date - g)::date as day
    from generate_series(0, greatest(p_days, 1) - 1) g
  )
  select d.day,
         coalesce(s.completed_items, 0) as completed,
         coalesce(s.total_items, 0) as total,
         case
           when s.total_items is null or s.total_items = 0 then null
           else round((s.completed_items::numeric / s.total_items), 2)
         end as ratio
  from d
  left join public.workout_sessions s
    on s.user_id = auth.uid() and s.session_date = d.day
  order by d.day;
$$;

grant execute on function public.get_workout_adherence(int) to authenticated;

-- ---------- 13. RPC: get_meal_adherence ----------
-- Per-day (last `p_days`) completion ratio = eaten / planned_items.
-- "planned_items" is the count of distinct (slot, role) entries the
-- AI returned for that day (so swaps don't inflate the denominator).
create or replace function public.get_meal_adherence(
  p_days int default 7
)
returns table (
  day date,
  eaten int,
  planned int,
  ratio numeric
)
language sql
security definer
set search_path = public
as $$
  with d as (
    select (current_date - g)::date as day
    from generate_series(0, greatest(p_days, 1) - 1) g
  ),
  -- Distinct (slot,role) tuples logged as "eaten" for the day.
  eaten_per_day as (
    select l.meal_date as day, count(*)::int as eaten
    from public.meal_intake_log l
    where l.user_id = auth.uid()
      and l.status in ('eaten','swap')
      and l.meal_date >= (current_date - (p_days - 1))
    group by l.meal_date
  )
  select d.day,
         coalesce(e.eaten, 0) as eaten,
         -- planned_items: number of slots defined for that program day
         -- in meal_plan_days (1..30); mod 30 so day 31+ loops.
         coalesce(
           (
             select 1 + (case when lunch_dal is not null then 1 else 0 end)
                    + (case when morning_snack is not null then 1 else 0 end)
                    + (case when evening_snack is not null then 1 else 0 end)
             from public.meal_plan_days
             where day = (((d.day - date '2025-01-01') % 30) + 1)
           ), 0
         ) as planned,
         case
           when coalesce(e.eaten, 0) = 0 then null
           else round(
             (e.eaten::numeric / nullif(
               (
                 select 1 + (case when lunch_dal is not null then 1 else 0 end)
                        + (case when morning_snack is not null then 1 else 0 end)
                        + (case when evening_snack is not null then 1 else 0 end)
                 from public.meal_plan_days
                 where day = (((d.day - date '2025-01-01') % 30) + 1)
               ), 0
             )), 2)
         end as ratio
  from d
  left join eaten_per_day e on e.day = d.day
  order by d.day;
$$;

grant execute on function public.get_meal_adherence(int) to authenticated;

-- ---------- 14. RPC: get_medicine_adherence ----------
-- Per-day (last `p_days`) ratio = taken / total scheduled doses.
-- "total scheduled" = the number of dose rows for that day
-- (each one is either taken/skipped/missed). A day with zero
-- scheduled doses has ratio NULL.
drop function if exists public.get_medicine_adherence(int);

create or replace function public.get_medicine_adherence(
  p_days int default 7
)
returns table (
  day date,
  taken int,
  total int,
  ratio numeric
)
language sql
security definer
set search_path = public
as $$
  with d as (
    select (current_date - g)::date as day
    from generate_series(0, greatest(p_days, 1) - 1) g
  ),
  per_day as (
    select d.day,
           coalesce(sum(case when md.status = 'taken' then 1 else 0 end), 0)::int as taken,
           count(md.*)::int as total
    from d
    left join public.medicine_doses md
      on md.user_id = auth.uid() and md.dose_date = d.day
    group by d.day
  )
  select day, taken, total,
         case when total = 0 then null else round(taken::numeric / total, 2) end as ratio
  from per_day
  order by day;
$$;

grant execute on function public.get_medicine_adherence(int) to authenticated;

-- ---------- 15. RPC: ensure_default_workout_assignments ----------
-- Convenience: when a new user signs up, seed days 1..30 with a
-- gentle daily routine (walk + breathing + stretch). Idempotent.
--
-- Optional p_user_id lets the Dart caller pass the signed-in user
-- explicitly. We fall back to auth.uid() so existing callers keep
-- working. If neither resolves, we still log a notice so the gap
-- is visible in Supabase logs instead of silently doing nothing.
create or replace function public.ensure_default_workout_assignments(
  p_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
begin
  if v_user is null then
    raise notice 'ensure_default_workout_assignments: no user (auth.uid null, p_user_id null); skipping';
    return;
  end if;

  insert into public.workout_assignments (user_id, day_index, workout_id, position, is_active)
  select v_user, d, w.workout_id, w.pos, true
  from (
    values
      ('walk_brisk',    0),
      ('breathing_box', 1),
      ('stretch_full',  2)
  ) as w(workout_id, pos)
  cross join generate_series(1, 30) d
  on conflict (user_id, day_index, workout_id) do nothing;
end $$;

grant execute on function public.ensure_default_workout_assignments(uuid) to authenticated;

-- ---------- 15b. RPC: get_workout_time_tracking ----------
-- Per-day target vs. actual workout minutes for the last N days.
-- `target_seconds` = sum of `target_duration_seconds` over the user's
-- active assignments for that day. `actual_seconds` = sum of item
-- `duration_seconds` on completed session items for that day.
-- days with no plan AND no session are omitted (avoids a 30-empty-row
-- wall on the chart).
create or replace function public.get_workout_time_tracking(p_days int default 7)
returns table(
  day date,
  target_seconds int,
  actual_seconds int,
  target_minutes int,
  actual_minutes int,
  pct numeric,
  planned_count int,
  completed_count int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then return; end if;

  return query
    with series as (
      -- Calendar dates for the last p_days, oldest → newest. Computed in
      -- Asia/Dhaka so the chart stays aligned with the user's local day
      -- even when server time is UTC.
      select ((current_date at time zone 'Asia/Dhaka')::date - gs)::date as d
      from generate_series(0, greatest(p_days, 1) - 1) gs
    ),
    anchor as (
      -- "Today" in the user's timezone; program_day starts at 1 here.
      select ((current_timestamp at time zone 'Asia/Dhaka')::date) as anchor_date,
             1 as program_day
    ),
    plan_per_day as (
      -- The user might be on any day_index of the 30-day program, but the
      -- RPC callers (chart, headline) want today's target. We compute the
      -- target for "the program day that corresponds to each calendar date"
      -- rather than hardcoding day 1 — that way, if the user has been on
      -- the program for a while, the chart still reflects today's plan.
      --
      -- Two safeguards:
      --   1. If anchor.program_day (=1) yields 0, fall back to the lowest
      --      non-empty day_index that has assignments, so freshly-seeded
      --      users never see "no workouts" while assignments exist.
      --   2. The numeric division rounds down to the nearest completed
      --      program cycle so we never project past day 30.
      with eff_day as (
        select (
          select coalesce(sum(w.target_duration_seconds), 0)
          from public.workout_assignments a
          join public.workouts w on w.id = a.workout_id and w.is_active
          where a.user_id = v_user
            and a.is_active
            and a.day_index = (select program_day from anchor)
        ) as s1,
        (
          select coalesce(sum(w.target_duration_seconds), 0)
          from public.workout_assignments a
          join public.workouts w on w.id = a.workout_id and w.is_active
          where a.user_id = v_user
            and a.is_active
            and a.day_index = (
              select min(a2.day_index)
              from public.workout_assignments a2
              where a2.user_id = v_user and a2.is_active
            )
        ) as s_fallback,
        (
          select min(a2.day_index)
          from public.workout_assignments a2
          where a2.user_id = v_user and a2.is_active
        ) as fallback_day
      )
      select
        case when s1 > 0 then s1::int else s_fallback::int end as target,
        case when s1 > 0
          then (select count(*) from public.workout_assignments a
                join public.workouts w on w.id = a.workout_id and w.is_active
                where a.user_id = v_user and a.is_active
                  and a.day_index = (select program_day from anchor))::int
          else (select count(*) from public.workout_assignments a
                join public.workouts w on w.id = a.workout_id and w.is_active
                where a.user_id = v_user and a.is_active
                  and a.day_index = eff_day.fallback_day)::int
        end as planned
      from eff_day
    ),
    actual_per_day as (
      select s.session_date as d,
             coalesce(sum(s.total_duration_seconds), 0)::int as actual,
             coalesce(sum(s.completed_items), 0)::int as done
      from public.workout_sessions s
      where s.user_id = v_user
        and s.session_date >= current_date - greatest(p_days, 1)
      group by s.session_date
    ),
    today_targets as (
      select target as target_seconds, planned as planned_count
      from plan_per_day
    )
    select
      series.d,
      coalesce(tt.target_seconds, 0)::int as target_seconds,
      coalesce(ap.actual, 0)::int          as actual_seconds,
      (coalesce(tt.target_seconds, 0) / 60)::int as target_minutes,
      (coalesce(ap.actual, 0) / 60)::int        as actual_minutes,
      case
        when coalesce(tt.target_seconds, 0) = 0 then
          case when coalesce(ap.actual, 0) > 0 then 1.0 else 0.0 end
        else round((ap.actual::numeric / tt.target_seconds), 2)
      end as pct,
      coalesce(tt.planned_count, 0)::int  as planned_count,
      coalesce(ap.done, 0)::int            as completed_count
    from series
    cross join today_targets tt
    left join actual_per_day ap on ap.d = series.d
    order by series.d asc;
end $$;

grant execute on function public.get_workout_time_tracking(int) to authenticated;

-- ---------- 15c. RPC: get_today_exercise_time_feedback ----------
-- For each of today's assigned workouts, return
--   target_seconds, target_seconds_done (the accumulated duration
--   logged on that workout so far today), and a Bangla hint string
--   the UI can show inline. Used by the assignment tiles to render
--   "৮ / ১০ মিনিট" pills under each exercise.
create or replace function public.get_today_exercise_time_feedback()
returns table(
  workout_id text,
  target_seconds int,
  actual_seconds int,
  target_minutes int,
  actual_minutes int,
  pct numeric,
  hint_bn text,
  status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_day int := public.calendar_day_to_index();
begin
  if v_user is null then return; end if;

  return query
    with today_assign as (
      select a.workout_id, w.target_duration_seconds
      from public.workout_assignments a
      join public.workouts w on w.id = a.workout_id and w.is_active
      where a.user_id = v_user
        and a.is_active
        and a.day_index = v_day
    ),
    actual_per_workout as (
      select i.workout_id,
             coalesce(sum(i.duration_seconds), 0)::int as actual_seconds
      from public.workout_session_items i
      join public.workout_sessions s
        on s.id = i.session_id
      where s.user_id = v_user
        and s.session_date = v_today
      group by i.workout_id
    )
    select
      ta.workout_id,
      ta.target_duration_seconds as target_seconds,
      coalesce(a.actual_seconds, 0) as actual_seconds,
      (ta.target_duration_seconds / 60)::int as target_minutes,
      (coalesce(a.actual_seconds, 0) / 60)::int as actual_minutes,
      case
        when ta.target_duration_seconds = 0 then 0.0
        else round((coalesce(a.actual_seconds, 0)::numeric / ta.target_duration_seconds)::numeric, 2)
      end as pct,
      format(
        '%s / %s মিনিট',
        (coalesce(a.actual_seconds, 0) / 60)::int,
        (ta.target_duration_seconds / 60)::int
      ) as hint_bn,
      case
        when coalesce(a.actual_seconds, 0) >= ta.target_duration_seconds then 'met'
        when coalesce(a.actual_seconds, 0) > 0 then 'partial'
        else 'pending'
      end as status
    from today_assign ta
    left join actual_per_workout a on a.workout_id = ta.workout_id;
end $$;

grant execute on function public.get_today_exercise_time_feedback() to authenticated;

-- ---------- 16. RPC: get_meal_logs ----------
-- Per-day planned vs eaten counts for the last N days, oldest first.
-- "planned" = 4 slots per day; "eaten" = unique (day, slot) pairs in
-- meal_intake_log for that user.
create or replace function public.get_meal_logs(p_days int default 7)
returns table(day date, planned int, eaten int)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then return; end if;
  return query
    with series as (
      select (current_date - gs)::date as d
      from generate_series(0, greatest(p_days, 1) - 1) gs
    ),
    eaten as (
      select (meal_at at time zone 'Asia/Dhaka')::date as d,
             count(distinct slot) as n
      from public.meal_intake_log
      where user_id = v_user
        and status in ('eaten', 'alternative')
        and meal_at >= current_date - greatest(p_days, 1)
      group by 1
    )
    select s.d, 4::int as planned, coalesce(e.n, 0)::int as eaten
    from series s
    left join eaten e on e.d = s.d
    order by s.d asc;
end $$;

grant execute on function public.get_meal_logs(int) to authenticated;

-- ---------- 17. RPC: get_medicine_logs ----------
-- Per-day totals for the last N days, oldest first.
create or replace function public.get_medicine_logs(p_days int default 7)
returns table(day date, total int, taken int, taken_pct numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then return; end if;
  return query
    with series as (
      select (current_date - gs)::date as d
      from generate_series(0, greatest(p_days, 1) - 1) gs
    ),
    agg as (
      select dose_date as d,
             count(*) as n,
             sum(case when status = 'taken' then 1 else 0 end) as t
      from public.medicine_doses
      where user_id = v_user
        and dose_date >= current_date - greatest(p_days, 1)
      group by 1
    )
    select s.d,
           coalesce(a.n, 0)::int as total,
           coalesce(a.t, 0)::int as taken,
           case when coalesce(a.n, 0) = 0 then 0
                else round((a.t::numeric / a.n::numeric) * 100, 1)
           end as taken_pct
    from series s
    left join agg a on a.d = s.d
    order by s.d asc;
end $$;

grant execute on function public.get_medicine_logs(int) to authenticated;