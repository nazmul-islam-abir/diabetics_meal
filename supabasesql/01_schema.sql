-- ============================================================
-- Amar Diet — Supabase Postgres schema (v2)
-- Apply with: 01_schema.sql, then 02_rpcs.sql, then 03_seed_foods.sql,
--             then 04_seed_alternatives.sql, then 05_seed_mealplan.sql
-- ============================================================

-- ---------- 1. USER CLINICAL PROFILE ----------
create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  age int not null check (age between 1 and 120),
  sex text check (sex in ('male','female','other')),
  weight_kg numeric(5,2) not null,
  height_cm numeric(5,2) not null,
  bmi numeric(5,2) generated always as (
    round((weight_kg / ((height_cm/100.0) * (height_cm/100.0)))::numeric, 2)
  ) stored,
  fasting_glucose_mmol numeric(4,1),
  post_meal_glucose_mmol numeric(4,1),
  random_glucose_mmol numeric(4,1),
  hba1c_percent numeric(4,1),
  on_insulin boolean not null default false,
  medication text,
  systolic_bp int,
  diastolic_bp int,
  has_ckd boolean not null default false,
  ckd_stage int,
  has_heart_disease boolean not null default false,
  has_anemia boolean not null default false,
  other_conditions text,
  activity_level text check (activity_level in ('low','moderate','high')) default 'low',
  meal_size_pref text check (meal_size_pref in ('small','medium','large')) default 'medium',
  food_preference text check (food_preference in ('omnivore','vegetarian','fish_only','no_beef')) default 'omnivore',
  updated_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;
drop policy if exists "Users manage their own profile" on public.user_profiles;
create policy "Users manage their own profile"
  on public.user_profiles for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ---------- 2. FOOD MASTER ----------
create table if not exists public.foods (
  id text primary key,
  name_bn text not null,
  category text not null check (category in ('breakfast','carb','protein','vegetable','dal','snack')),
  carb_g numeric(5,1) not null,
  protein_g numeric(5,1) not null,
  fat_g numeric(5,1) not null,
  fiber_g numeric(5,1) not null,
  sodium_mg numeric(6,1) not null,
  potassium_mg numeric(6,1) not null,
  phosphorus_mg numeric(6,1) not null,
  gi_category text not null check (gi_category in ('low','medium','high')),
  tags text[] not null default '{}',
  portion_label text not null,
  portion_g numeric(6,1) not null,
  affordability text not null default 'low_cost'
    check (affordability in ('low_cost','medium','premium')),
  common_in_bd boolean not null default true,
  effort text not null default 'easy'
    check (effort in ('easy','medium','hard')),
  healthiness text not null default 'good'
    check (healthiness in ('good','neutral','bad'))
);

alter table public.foods enable row level security;
drop policy if exists "Foods are readable by any authenticated user" on public.foods;
create policy "Foods are readable by any authenticated user"
  on public.foods for select
  using (auth.role() = 'authenticated');


-- ---------- 3. FOOD ALTERNATIVES (one-step swaps) ----------
create table if not exists public.food_alternatives (
  food_id text not null references public.foods(id) on delete cascade,
  alternative_id text not null references public.foods(id) on delete cascade,
  priority int not null default 1,
  primary key (food_id, alternative_id)
);

alter table public.food_alternatives enable row level security;
drop policy if exists "Alternatives are readable by any authenticated user" on public.food_alternatives;
create policy "Alternatives are readable by any authenticated user"
  on public.food_alternatives for select
  using (auth.role() = 'authenticated');


-- ---------- 4. 30-DAY MEAL PLAN ----------
create table if not exists public.meal_plan_days (
  day int primary key check (day between 1 and 30),
  breakfast_main text references public.foods(id),
  breakfast_alt text[] not null default '{}',
  lunch_carb text references public.foods(id),
  lunch_protein text references public.foods(id),
  lunch_protein_alt text references public.foods(id),
  lunch_vegetable text references public.foods(id),
  lunch_dal text references public.foods(id),
  dinner_carb text references public.foods(id),
  dinner_protein text references public.foods(id),
  dinner_protein_alt text references public.foods(id),
  dinner_vegetable text references public.foods(id),
  morning_snack text references public.foods(id),
  morning_snack_alt text references public.foods(id),
  evening_snack text references public.foods(id),
  evening_snack_alt text references public.foods(id)
);

alter table public.meal_plan_days enable row level security;
drop policy if exists "Meal plan days are readable by any authenticated user" on public.meal_plan_days;
create policy "Meal plan days are readable by any authenticated user"
  on public.meal_plan_days for select
  using (auth.role() = 'authenticated');


-- ---------- 5. MEAL INTAKE LOG ----------
create table if not exists public.meal_intake_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  meal_date date not null default (now() at time zone 'Asia/Dhaka')::date,
  meal_slot text not null check (meal_slot in ('breakfast','morning_snack','lunch','evening_snack','dinner')),
  food_id text references public.foods(id),
  food_name_bn text not null,
  status text not null check (status in ('eaten','swap','off_plan')),
  impact text not null default 'neutral' check (impact in ('good','neutral','bad')),
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists meal_intake_log_user_date
  on public.meal_intake_log (user_id, meal_date);

alter table public.meal_intake_log enable row level security;
drop policy if exists "Users manage their own intake log" on public.meal_intake_log;
create policy "Users manage their own intake log"
  on public.meal_intake_log for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ---------- 6. USER FAVORITES ----------
create table if not exists public.user_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  food_id text not null references public.foods(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, food_id)
);

alter table public.user_favorites enable row level security;
drop policy if exists "Users manage their own favorites" on public.user_favorites;
create policy "Users manage their own favorites"
  on public.user_favorites for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);