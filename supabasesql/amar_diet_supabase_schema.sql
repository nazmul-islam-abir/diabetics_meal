-- ============================================================
-- Amar Diet — Supabase Postgres schema
-- Nutrition estimates are approximations for app bootstrapping.
-- Cross-check against verified BFCT/food composition data before
-- production use, especially the CKD/sodium/potassium tags below.
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

  fasting_glucose_mmol numeric(4,1),      -- e.g. 7.8
  post_meal_glucose_mmol numeric(4,1),    -- e.g. 10.5 (2hr post-meal)
  random_glucose_mmol numeric(4,1),       -- optional spot reading
  hba1c_percent numeric(4,1),             -- e.g. 7.5

  on_insulin boolean not null default false,
  medication text,                        -- free text: 'Metformin', 'Metformin+Insulin', etc.

  systolic_bp int,
  diastolic_bp int,

  has_ckd boolean not null default false,
  ckd_stage int,                          -- 1-5, null if has_ckd = false
  has_heart_disease boolean not null default false,
  has_anemia boolean not null default false,
  other_conditions text,

  activity_level text check (activity_level in ('low','moderate','high')) default 'low',
  meal_size_pref text check (meal_size_pref in ('small','medium','large')) default 'medium',
  food_preference text check (food_preference in ('omnivore','vegetarian','fish_only','no_beef')) default 'omnivore',

  updated_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;

create policy "Users manage their own profile"
  on public.user_profiles for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ---------- 2. FOOD MASTER TABLE ----------
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
  portion_g numeric(6,1) not null
);

-- Extended columns (app-side impact / affordability / effort classification).
-- Idempotent: re-running this schema keeps the columns in sync.
alter table public.foods
  add column if not exists affordability text not null default 'low_cost'
    check (affordability in ('low_cost','medium','premium')),
  add column if not exists common_in_bd boolean not null default true,
  add column if not exists effort text not null default 'easy'
    check (effort in ('easy','medium','hard')),
  add column if not exists healthiness text not null default 'good'
    check (healthiness in ('good','neutral','bad'));

alter table public.foods enable row level security;
create policy "Foods are readable by any authenticated user"
  on public.foods for select
  using (auth.role() = 'authenticated');


-- ---------- 3. 30-DAY MEAL PLAN TEMPLATE ----------
-- Generic (not user-specific) rotation; the app filters/subs at query time
-- using get_daily_recommendation() below, based on the user's profile.
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
create policy "Meal plan days are readable by any authenticated user"
  on public.meal_plan_days for select
  using (auth.role() = 'authenticated');


-- ---------- 4. SAVED RECOMMENDATIONS (optional log) ----------
create table if not exists public.user_daily_recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  day int not null references public.meal_plan_days(day),
  recommendation jsonb not null,
  warnings text[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.user_daily_recommendations enable row level security;
create policy "Users manage their own recommendations"
  on public.user_daily_recommendations for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ============================================================
-- 5. CLASSIFICATION FUNCTION
-- Standard reference cutoffs (ADA glucose/HbA1c staging,
-- Asian/Bangladesh BMI cutoffs, ACC/AHA BP staging).
-- Returns a jsonb of tiers/flags used by the matching function.
-- ============================================================
create or replace function public.classify_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.user_profiles;
  glucose_tier text;
  bmi_tier text;
  bp_tier text;
  max_carb_per_meal numeric;
  allowed_gi text[];
  restriction_flags text[] := '{}';
  warnings text[] := '{}';
begin
  select * into p from public.user_profiles where user_id = p_user_id;
  if not found then
    raise exception 'No profile found for user %', p_user_id;
  end if;

  -- Glucose control tier: prioritize HbA1c (3-month average) if present,
  -- fall back to fasting/post-meal readings.
  if p.hba1c_percent is not null then
    if p.hba1c_percent < 7.0 then glucose_tier := 'good';
    elsif p.hba1c_percent <= 8.5 then glucose_tier := 'moderate';
    else glucose_tier := 'poor';
    end if;
  elsif p.fasting_glucose_mmol is not null then
    if p.fasting_glucose_mmol < 7.0 then glucose_tier := 'good';
    elsif p.fasting_glucose_mmol <= 10.0 then glucose_tier := 'moderate';
    else glucose_tier := 'poor';
    end if;
  else
    glucose_tier := 'unknown';
    warnings := array_append(warnings, 'গ্লুকোজ বা HbA1c তথ্য দেওয়া হয়নি — সাধারণ মধ্যম-কার্ব পরিকল্পনা দেখানো হচ্ছে');
  end if;

  -- Carb ceiling per main meal (grams), scaled by glucose tier + meal size pref
  max_carb_per_meal := case glucose_tier
    when 'good' then 45
    when 'moderate' then 35
    when 'poor' then 25
    else 35
  end;
  if p.meal_size_pref = 'small' then max_carb_per_meal := max_carb_per_meal - 5; end if;
  if p.meal_size_pref = 'large' then max_carb_per_meal := max_carb_per_meal + 5; end if;

  -- Allowed GI categories
  allowed_gi := case glucose_tier
    when 'good' then array['low','medium']
    when 'moderate' then array['low','medium']
    when 'poor' then array['low']
    else array['low','medium']
  end;

  -- BMI tier (Bangladesh/Asian cutoffs)
  if p.bmi < 18.5 then bmi_tier := 'underweight';
  elsif p.bmi < 23 then bmi_tier := 'normal';
  elsif p.bmi < 25 then bmi_tier := 'overweight';
  else bmi_tier := 'obese';
  end if;

  -- BP tier (ACC/AHA)
  if p.systolic_bp is not null and p.diastolic_bp is not null then
    if p.systolic_bp >= 140 or p.diastolic_bp >= 90 then bp_tier := 'stage2';
    elsif p.systolic_bp >= 130 or p.diastolic_bp >= 80 then bp_tier := 'stage1';
    elsif p.systolic_bp >= 120 then bp_tier := 'elevated';
    else bp_tier := 'normal';
    end if;
  else
    bp_tier := 'unknown';
  end if;

  if bp_tier in ('stage1','stage2') then
    restriction_flags := array_append(restriction_flags, 'low_sodium_required');
  end if;

  -- CKD — hard exclusions, highest priority safety flag
  if p.has_ckd then
    restriction_flags := array_append(restriction_flags, 'ckd_restricted_high_k');
    restriction_flags := array_append(restriction_flags, 'ckd_restricted_high_phos');
    warnings := array_append(warnings, 'কিডনি রোগের কারণে পটাশিয়াম/ফসফরাসযুক্ত খাবার সীমিত করা হয়েছে — নেফ্রোলজিস্টের পরামর্শ অনুসরণ করুন');
  end if;

  if p.has_heart_disease then
    restriction_flags := array_append(restriction_flags, 'heart_moderate_restricted');
  end if;

  if p.on_insulin then
    warnings := array_append(warnings,
      'আপনি ইনসুলিন গ্রহণ করছেন — খাবারের সময় ও পরিমাণ ধারাবাহিক রাখা জরুরি। কোনো বেলা বাদ দেওয়ার আগে ডাক্তারের পরামর্শ নিন।');
  end if;

  if p.has_anemia then
    warnings := array_append(warnings, 'রক্তস্বল্পতা থাকায় আয়রন সমৃদ্ধ খাবার (শিং মাছ, কচু শাক) অগ্রাধিকার দেওয়া হচ্ছে');
  end if;

  return jsonb_build_object(
    'glucose_tier', glucose_tier,
    'bmi_tier', bmi_tier,
    'bp_tier', bp_tier,
    'max_carb_per_meal', max_carb_per_meal,
    'allowed_gi', to_jsonb(allowed_gi),
    'restriction_flags', to_jsonb(restriction_flags),
    'warnings', to_jsonb(warnings),
    'food_preference', p.food_preference
  );
end;
$$;


-- ============================================================
-- 6. FOOD-SWAP HELPER
-- Given the user's classification and a primary/alternative food id,
-- returns the alternative if the primary is excluded by a CKD
-- (potassium/phosphorus) restriction flag; otherwise returns the primary.
-- Defined as a top-level function (not nested) for Postgres compatibility.
-- ============================================================
create or replace function public.pick_food(p_cls jsonb, p_primary_id text, p_alt_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  f public.foods;
  flags text[];
  restricted text[] := array['ckd_restricted_high_k','ckd_restricted_high_phos'];
begin
  flags := array(select jsonb_array_elements_text(p_cls->'restriction_flags'));
  select * into f from public.foods where id = p_primary_id;
  if f.tags && flags and f.tags && restricted then
    if p_alt_id is not null then
      select * into f from public.foods where id = p_alt_id;
    end if;
  end if;
  return to_jsonb(f);
end;
$$;


-- ============================================================
-- 7. RECOMMENDATION FUNCTION
-- Filters a given plan day's foods against the user's classification.
-- Falls back to the *_alt food if the primary choice is excluded.
-- ============================================================
create or replace function public.get_daily_recommendation(p_user_id uuid, p_day int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cls jsonb;
  plan public.meal_plan_days;
  result jsonb;
begin
  cls := public.classify_user(p_user_id);
  select * into plan from public.meal_plan_days where day = p_day;
  if not found then
    raise exception 'No plan found for day %', p_day;
  end if;

  result := jsonb_build_object(
    'day', p_day,
    'classification', cls,
    'breakfast', to_jsonb((select f from public.foods f where f.id = plan.breakfast_main)),
    'lunch', jsonb_build_object(
      'carb', to_jsonb((select f from public.foods f where f.id = plan.lunch_carb)),
      'protein', public.pick_food(cls, plan.lunch_protein, plan.lunch_protein_alt),
      'vegetable', to_jsonb((select f from public.foods f where f.id = plan.lunch_vegetable)),
      'dal', to_jsonb((select f from public.foods f where f.id = plan.lunch_dal))
    ),
    'dinner', jsonb_build_object(
      'carb', to_jsonb((select f from public.foods f where f.id = plan.dinner_carb)),
      'protein', public.pick_food(cls, plan.dinner_protein, plan.dinner_protein_alt),
      'vegetable', to_jsonb((select f from public.foods f where f.id = plan.dinner_vegetable))
    ),
    'morning_snack', to_jsonb((select f from public.foods f where f.id = plan.morning_snack)),
    'evening_snack', to_jsonb((select f from public.foods f where f.id = plan.evening_snack))
  );

  -- Log it
  insert into public.user_daily_recommendations (user_id, day, recommendation, warnings)
  values (p_user_id, p_day, result, array(select jsonb_array_elements_text(cls->'warnings')));

  return result;
end;
$$;


-- ---------- SEED: foods ----------

insert into public.foods (id, name_bn, category, carb_g, protein_g, fat_g, fiber_g, sodium_mg, potassium_mg, phosphorus_mg, gi_category, tags, portion_label, portion_g) values
('b_lal_ruti', 'লাল আটার রুটি (২টি)', 'breakfast', 30, 6, 2, 5, 120, 140, 110, 'low', ARRAY['ckd_caution_moderate','low_sodium_ok','vegetarian']::text[], '২টি মাঝারি রুটি', 60),
('b_oats_khichuri', 'ওটস খিচুড়ি', 'breakfast', 27, 8, 3, 6, 150, 180, 130, 'low', ARRAY['ckd_caution_moderate','low_sodium_ok','vegetarian']::text[], '১ বাটি (৪০ গ্রাম কাঁচা ওটস)', 200),
('b_chira_doi', 'টক দই চিড়া', 'breakfast', 25, 6, 3, 1, 60, 220, 140, 'medium', ARRAY['low_sodium_ok','vegetarian']::text[], 'চিড়া ৩০গ্রাম + দই আধা কাপ', 150),
('b_sobji_ruti', 'সবজি রুটি (লাল আটা)', 'breakfast', 28, 6, 2, 6, 130, 200, 120, 'low', ARRAY['ckd_caution_moderate','low_sodium_ok','vegetarian']::text[], '২টি রুটি', 60),
('b_mug_chila', 'মুগ ডালের চিলা', 'breakfast', 20, 10, 3, 4, 140, 260, 180, 'low', ARRAY['ckd_restricted_high_phos','vegetarian']::text[], '২টি ছোট চিলা', 100),
('b_alt_lalchal_ruti', 'লাল চালের রুটি', 'breakfast', 30, 5, 1, 4, 100, 130, 100, 'low', ARRAY['ckd_caution_moderate','low_sodium_ok','vegetarian']::text[], '২টি', 60),
('b_alt_muri', 'মুড়ি (ভাজা ছাড়া)', 'breakfast', 24, 2, 0, 1, 180, 40, 30, 'high', ARRAY['low_potassium_ok','vegetarian']::text[], '১ কাপ (৩০ গ্রাম)', 30),
('b_alt_oats_plain', 'ওটস (পানি দিয়ে)', 'breakfast', 23, 5, 2, 5, 10, 140, 110, 'low', ARRAY['ckd_caution_moderate','low_sodium_ok','vegetarian']::text[], '৩৫ গ্রাম', 35),
('c_lalchal_bhat', 'লাল চালের ভাত (১ কাপ)', 'carb', 45, 4, 0, 2, 5, 55, 60, 'medium', ARRAY['low_sodium_ok','vegetarian']::text[], '১ কাপ রান্না করা (~১৫০ গ্রাম)', 150),
('c_lal_ruti_3', 'লাল আটার রুটি (৩টি)', 'carb', 45, 9, 3, 7, 180, 210, 165, 'low', ARRAY['ckd_caution_moderate','low_sodium_ok','vegetarian']::text[], '৩টি মাঝারি', 90),
('c_lalchal_bhat_light', 'লাল চালের ভাত (হালকা)', 'carb', 33, 3, 0, 1, 4, 40, 45, 'medium', ARRAY['low_sodium_ok','vegetarian']::text[], '৩/৪ কাপ (~১১০ গ্রাম)', 110),
('c_lal_ruti_2', 'লাল আটার রুটি (২টি)', 'carb', 30, 6, 2, 5, 120, 140, 110, 'low', ARRAY['ckd_caution_moderate','low_sodium_ok','vegetarian']::text[], '২টি মাঝারি', 60),
('p_rui', 'রুই মাছ (ঝোল)', 'protein', 1, 20, 6, 0, 190, 330, 220, 'low', ARRAY['ckd_restricted_high_phos','low_sodium_ok']::text[], '১ টুকরা (~৮০ গ্রাম)', 80),
('p_tilapia', 'তেলাপিয়া মাছ (ভাপা/ঝোল)', 'protein', 1, 21, 4, 0, 170, 300, 200, 'low', ARRAY['ckd_restricted_high_phos','low_sodium_ok']::text[], '১ টুকরা (~৮০ গ্রাম)', 80),
('p_murgi', 'মুরগির মাংস (চামড়া ছাড়া)', 'protein', 0, 24, 5, 0, 160, 260, 190, 'low', ARRAY['ckd_restricted_high_phos','low_sodium_ok','heart_moderate']::text[], '২ টুকরা (~৯০ গ্রাম)', 90),
('p_shing', 'শিং মাছ (ঝোল)', 'protein', 1, 18, 5, 0, 175, 280, 195, 'low', ARRAY['ckd_restricted_high_phos','low_sodium_ok','high_iron']::text[], '২টি ছোট (~৭৫ গ্রাম)', 75),
('p_moshur_dal', 'মসুর ডাল (ঘন)', 'protein', 15, 9, 2, 5, 140, 250, 170, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১৫০ মিলি)', 150),
('p_katla', 'কাতলা মাছ (ঝোল)', 'protein', 1, 19, 6, 0, 185, 320, 215, 'low', ARRAY['ckd_restricted_high_phos','low_sodium_ok']::text[], '১ টুকরা (~৮০ গ্রাম)', 80),
('p_mug_dal', 'মুগ ডাল + সয়াবিন বড়ি', 'protein', 16, 10, 2, 5, 150, 260, 180, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], '১ বাটি', 150),
('p_pabda', 'পাবদা মাছ (ঝোল)', 'protein', 1, 17, 7, 0, 180, 290, 200, 'low', ARRAY['ckd_restricted_high_phos','low_sodium_ok']::text[], '২টি ছোট (~৭০ গ্রাম)', 70),
('p_dim', 'ডিম কারি', 'protein', 2, 13, 10, 0, 190, 140, 180, 'low', ARRAY['ckd_restricted_high_phos','heart_moderate','vegetarian_egg']::text[], '১টি ডিম, সপ্তাহে ৩ বার সীমিত', 50),
('p_deshi_murgi', 'দেশি মুরগি (হালকা মসলা)', 'protein', 0, 23, 6, 0, 165, 270, 195, 'low', ARRAY['ckd_restricted_high_phos','low_sodium_ok','heart_moderate']::text[], '২ টুকরা (~৮৫ গ্রাম)', 85),
('v_0', 'লাউ ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_1', 'পটল ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_2', 'ঢেঁড়স ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_3', 'বরবটি ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_4', 'লাল শাক', 'vegetable', 8, 2, 1, 3, 40, 180, 45, 'low', ARRAY['ckd_restricted_high_k','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_5', 'পালং শাক', 'vegetable', 8, 2, 1, 3, 40, 180, 45, 'low', ARRAY['ckd_restricted_high_k','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_6', 'করলা ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_7', 'চিচিঙ্গা ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_8', 'শজনে ডাটা', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_9', 'মিষ্টি কুমড়া', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_10', 'বাঁধাকপি ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_11', 'ফুলকপি-আলু', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_12', 'কচুর লতি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_restricted_high_k','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_13', 'ঝিঙা ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('v_14', 'পেঁপে ভাজি', 'vegetable', 8, 2, 1, 3, 40, 130, 45, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি (~১০০ গ্রাম)', 100),
('d_0', 'মসুর ডাল (পাতলা)', 'dal', 12, 7, 1, 4, 90, 210, 150, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], 'আধা বাটি (~১০০ মিলি)', 100),
('d_1', 'মুগ ডাল', 'dal', 12, 7, 1, 4, 90, 210, 150, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], 'আধা বাটি (~১০০ মিলি)', 100),
('d_2', 'খেসারি ডাল', 'dal', 12, 7, 1, 4, 90, 210, 150, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], 'আধা বাটি (~১০০ মিলি)', 100),
('d_3', 'ছোলার ডাল', 'dal', 12, 7, 1, 4, 90, 210, 150, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], 'আধা বাটি (~১০০ মিলি)', 100),
('d_4', 'মাসকলাই ডাল', 'dal', 12, 7, 1, 4, 90, 210, 150, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], 'আধা বাটি (~১০০ মিলি)', 100),
('s_peyara', 'পেয়ারা', 'snack', 14, 1, 0, 5, 2, 417, 30, 'low', ARRAY['ckd_restricted_high_k','vegetarian','low_sodium_ok']::text[], '১টি মাঝারি (~১০০ গ্রাম)', 100),
('s_apple', 'আপেল', 'snack', 14, 0, 0, 2, 1, 107, 11, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১টি ছোট (~১০০ গ্রাম)', 100),
('s_badam', 'বাদাম (কাঠবাদাম/আখরোট)', 'snack', 6, 6, 14, 3, 1, 200, 140, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], '১ মুঠো (~২০ গ্রাম)', 20),
('s_jambura', 'বাতাবি লেবু (জাম্বুরা)', 'snack', 10, 1, 0, 2, 1, 216, 17, 'low', ARRAY['ckd_restricted_high_k','vegetarian','low_sodium_ok']::text[], '২-৩ কোয়া', 80),
('s_doi', 'টক দই (চিনি ছাড়া)', 'snack', 7, 4, 2, 0, 40, 155, 95, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], 'আধা কাপ', 100),
('s_salad', 'শসা-গাজর সালাদ', 'snack', 6, 1, 0, 2, 10, 180, 25, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি', 100),
('s_chola', 'ছোলা সেদ্ধ (মসলা কম)', 'snack', 20, 8, 2, 6, 120, 240, 140, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], 'আধা কাপ', 100),
('s_cha', 'চা (চিনি ছাড়া) + ফাইবার বিস্কুট', 'snack', 16, 2, 3, 2, 80, 60, 50, 'medium', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ কাপ + ২টি বিস্কুট', 150),
('s_muri_chola', 'মুড়ি + ছোলা মাখা', 'snack', 22, 5, 2, 4, 140, 150, 90, 'high', ARRAY['ckd_caution_moderate','vegetarian']::text[], '১ কাপ মুড়ি + সামান্য ছোলা', 120),
('s_dab', 'ডাবের পানি', 'snack', 9, 0, 0, 0, 25, 250, 5, 'medium', ARRAY['ckd_restricted_high_k','vegetarian','low_sodium_ok']::text[], '১ গ্লাস (~২০০ মিলি), সপ্তাহে ২-৩ বার', 200),
('s_sobji_sidho', 'সবজি সিদ্ধ (গাজর/শসা/টমেটো)', 'snack', 8, 1, 0, 3, 15, 160, 30, 'low', ARRAY['ckd_caution_moderate','vegetarian','low_sodium_ok']::text[], '১ বাটি', 100),
('s_badam_mix', 'বাদাম মিশ্রণ', 'snack', 6, 6, 14, 3, 1, 200, 140, 'low', ARRAY['ckd_restricted_high_phos','vegetarian','low_sodium_ok']::text[], '১ মুঠো (~২০ গ্রাম)', 20)
on conflict (id) do nothing;


-- ---------- SEED: meal_plan_days ----------

insert into public.meal_plan_days (day, breakfast_main, breakfast_alt, lunch_carb, lunch_protein, lunch_protein_alt, lunch_vegetable, lunch_dal, dinner_carb, dinner_protein, dinner_protein_alt, dinner_vegetable, morning_snack, morning_snack_alt, evening_snack, evening_snack_alt) values
(1, 'b_lal_ruti', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lalchal_bhat', 'p_rui', 'p_shing', 'v_0', 'd_0', 'c_lal_ruti_3', 'p_katla', 'p_dim', 'v_4', 's_peyara', 's_badam', 's_chola', 's_dab'),
(2, 'b_oats_khichuri', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lal_ruti_3', 'p_tilapia', 'p_moshur_dal', 'v_1', 'd_1', 'c_lalchal_bhat_light', 'p_mug_dal', 'p_deshi_murgi', 'v_5', 's_apple', 's_jambura', 's_cha', 's_sobji_sidho'),
(3, 'b_chira_doi', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lalchal_bhat_light', 'p_murgi', 'p_katla', 'v_2', 'd_2', 'c_lal_ruti_2', 'p_pabda', 'p_rui', 'v_6', 's_badam', 's_doi', 's_muri_chola', 's_badam_mix'),
(4, 'b_sobji_ruti', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lal_ruti_2', 'p_shing', 'p_mug_dal', 'v_3', 'd_3', 'c_lalchal_bhat', 'p_dim', 'p_tilapia', 'v_7', 's_jambura', 's_salad', 's_dab', 's_peyara'),
(5, 'b_mug_chila', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lalchal_bhat', 'p_moshur_dal', 'p_pabda', 'v_4', 'd_4', 'c_lal_ruti_3', 'p_deshi_murgi', 'p_murgi', 'v_8', 's_doi', 's_chola', 's_sobji_sidho', 's_apple'),
(6, 'b_lal_ruti', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lal_ruti_3', 'p_katla', 'p_dim', 'v_5', 'd_0', 'c_lalchal_bhat_light', 'p_rui', 'p_shing', 'v_9', 's_salad', 's_cha', 's_badam_mix', 's_badam'),
(7, 'b_oats_khichuri', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lalchal_bhat_light', 'p_mug_dal', 'p_deshi_murgi', 'v_6', 'd_1', 'c_lal_ruti_2', 'p_tilapia', 'p_moshur_dal', 'v_10', 's_chola', 's_muri_chola', 's_peyara', 's_jambura'),
(8, 'b_chira_doi', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lal_ruti_2', 'p_pabda', 'p_rui', 'v_7', 'd_2', 'c_lalchal_bhat', 'p_murgi', 'p_katla', 'v_11', 's_cha', 's_dab', 's_apple', 's_doi'),
(9, 'b_sobji_ruti', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lalchal_bhat', 'p_dim', 'p_tilapia', 'v_8', 'd_3', 'c_lal_ruti_3', 'p_shing', 'p_mug_dal', 'v_12', 's_muri_chola', 's_sobji_sidho', 's_badam', 's_salad'),
(10, 'b_mug_chila', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lal_ruti_3', 'p_deshi_murgi', 'p_murgi', 'v_9', 'd_4', 'c_lalchal_bhat_light', 'p_moshur_dal', 'p_pabda', 'v_13', 's_dab', 's_badam_mix', 's_jambura', 's_chola'),
(11, 'b_lal_ruti', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lalchal_bhat_light', 'p_rui', 'p_shing', 'v_10', 'd_0', 'c_lal_ruti_2', 'p_katla', 'p_dim', 'v_14', 's_sobji_sidho', 's_peyara', 's_doi', 's_cha'),
(12, 'b_oats_khichuri', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lal_ruti_2', 'p_tilapia', 'p_moshur_dal', 'v_11', 'd_1', 'c_lalchal_bhat', 'p_mug_dal', 'p_deshi_murgi', 'v_0', 's_badam_mix', 's_apple', 's_salad', 's_muri_chola'),
(13, 'b_chira_doi', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lalchal_bhat', 'p_murgi', 'p_katla', 'v_12', 'd_2', 'c_lal_ruti_3', 'p_pabda', 'p_rui', 'v_1', 's_peyara', 's_badam', 's_chola', 's_dab'),
(14, 'b_sobji_ruti', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lal_ruti_3', 'p_shing', 'p_mug_dal', 'v_13', 'd_3', 'c_lalchal_bhat_light', 'p_dim', 'p_tilapia', 'v_2', 's_apple', 's_jambura', 's_cha', 's_sobji_sidho'),
(15, 'b_mug_chila', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lalchal_bhat_light', 'p_moshur_dal', 'p_pabda', 'v_14', 'd_4', 'c_lal_ruti_2', 'p_deshi_murgi', 'p_murgi', 'v_3', 's_badam', 's_doi', 's_muri_chola', 's_badam_mix'),
(16, 'b_lal_ruti', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lal_ruti_2', 'p_katla', 'p_dim', 'v_0', 'd_0', 'c_lalchal_bhat', 'p_rui', 'p_shing', 'v_4', 's_jambura', 's_salad', 's_dab', 's_peyara'),
(17, 'b_oats_khichuri', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lalchal_bhat', 'p_mug_dal', 'p_deshi_murgi', 'v_1', 'd_1', 'c_lal_ruti_3', 'p_tilapia', 'p_moshur_dal', 'v_5', 's_doi', 's_chola', 's_sobji_sidho', 's_apple'),
(18, 'b_chira_doi', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lal_ruti_3', 'p_pabda', 'p_rui', 'v_2', 'd_2', 'c_lalchal_bhat_light', 'p_murgi', 'p_katla', 'v_6', 's_salad', 's_cha', 's_badam_mix', 's_badam'),
(19, 'b_sobji_ruti', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lalchal_bhat_light', 'p_dim', 'p_tilapia', 'v_3', 'd_3', 'c_lal_ruti_2', 'p_shing', 'p_mug_dal', 'v_7', 's_chola', 's_muri_chola', 's_peyara', 's_jambura'),
(20, 'b_mug_chila', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lal_ruti_2', 'p_deshi_murgi', 'p_murgi', 'v_4', 'd_4', 'c_lalchal_bhat', 'p_moshur_dal', 'p_pabda', 'v_8', 's_cha', 's_dab', 's_apple', 's_doi'),
(21, 'b_lal_ruti', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lalchal_bhat', 'p_rui', 'p_shing', 'v_5', 'd_0', 'c_lal_ruti_3', 'p_katla', 'p_dim', 'v_9', 's_muri_chola', 's_sobji_sidho', 's_badam', 's_salad'),
(22, 'b_oats_khichuri', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lal_ruti_3', 'p_tilapia', 'p_moshur_dal', 'v_6', 'd_1', 'c_lalchal_bhat_light', 'p_mug_dal', 'p_deshi_murgi', 'v_10', 's_dab', 's_badam_mix', 's_jambura', 's_chola'),
(23, 'b_chira_doi', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lalchal_bhat_light', 'p_murgi', 'p_katla', 'v_7', 'd_2', 'c_lal_ruti_2', 'p_pabda', 'p_rui', 'v_11', 's_sobji_sidho', 's_peyara', 's_doi', 's_cha'),
(24, 'b_sobji_ruti', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lal_ruti_2', 'p_shing', 'p_mug_dal', 'v_8', 'd_3', 'c_lalchal_bhat', 'p_dim', 'p_tilapia', 'v_12', 's_badam_mix', 's_apple', 's_salad', 's_muri_chola'),
(25, 'b_mug_chila', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lalchal_bhat', 'p_moshur_dal', 'p_pabda', 'v_9', 'd_4', 'c_lal_ruti_3', 'p_deshi_murgi', 'p_murgi', 'v_13', 's_peyara', 's_badam', 's_chola', 's_dab'),
(26, 'b_lal_ruti', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lal_ruti_3', 'p_katla', 'p_dim', 'v_10', 'd_0', 'c_lalchal_bhat_light', 'p_rui', 'p_shing', 'v_14', 's_apple', 's_jambura', 's_cha', 's_sobji_sidho'),
(27, 'b_oats_khichuri', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lalchal_bhat_light', 'p_mug_dal', 'p_deshi_murgi', 'v_11', 'd_1', 'c_lal_ruti_2', 'p_tilapia', 'p_moshur_dal', 'v_0', 's_badam', 's_doi', 's_muri_chola', 's_badam_mix'),
(28, 'b_chira_doi', ARRAY['b_alt_lalchal_ruti','b_alt_muri']::text[], 'c_lal_ruti_2', 'p_pabda', 'p_rui', 'v_12', 'd_2', 'c_lalchal_bhat', 'p_murgi', 'p_katla', 'v_1', 's_jambura', 's_salad', 's_dab', 's_peyara'),
(29, 'b_sobji_ruti', ARRAY['b_alt_muri','b_alt_oats_plain']::text[], 'c_lalchal_bhat', 'p_dim', 'p_tilapia', 'v_13', 'd_3', 'c_lal_ruti_3', 'p_shing', 'p_mug_dal', 'v_2', 's_doi', 's_chola', 's_sobji_sidho', 's_apple'),
(30, 'b_mug_chila', ARRAY['b_alt_oats_plain','b_alt_lalchal_ruti']::text[], 'c_lal_ruti_3', 'p_deshi_murgi', 'p_murgi', 'v_14', 'd_4', 'c_lalchal_bhat_light', 'p_moshur_dal', 'p_pabda', 'v_3', 's_salad', 's_cha', 's_badam_mix', 's_badam')
on conflict (day) do nothing;


-- ============================================================
-- 7. EXAMPLE USAGE (run from the Flutter app via Supabase RPC)
-- select public.get_daily_recommendation('<user-uuid>', 1);
-- ============================================================
