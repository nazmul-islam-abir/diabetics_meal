-- ============================================================
-- Amar Diet — RPC functions
-- ============================================================

-- ---------- 7. CLASSIFICATION ----------
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

  max_carb_per_meal := case glucose_tier
    when 'good' then 45
    when 'moderate' then 35
    when 'poor' then 25
    else 35
  end;
  if p.meal_size_pref = 'small' then max_carb_per_meal := max_carb_per_meal - 5; end if;
  if p.meal_size_pref = 'large' then max_carb_per_meal := max_carb_per_meal + 5; end if;

  allowed_gi := case glucose_tier
    when 'good' then array['low','medium']
    when 'moderate' then array['low','medium']
    when 'poor' then array['low']
    else array['low','medium']
  end;

  if p.bmi < 18.5 then bmi_tier := 'underweight';
  elsif p.bmi < 23 then bmi_tier := 'normal';
  elsif p.bmi < 25 then bmi_tier := 'overweight';
  else bmi_tier := 'obese';
  end if;

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


-- ---------- 8. FOOD-SWAP HELPER ----------
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


-- ---------- 9. ALTERNATIVES HELPER ----------
create or replace function public.food_alternatives_for(p_food_id text, p_limit int default 3)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  out jsonb := '[]'::jsonb;
  rec record;
begin
  for rec in
    select f.*, a.priority
    from public.food_alternatives a
    join public.foods f on f.id = a.alternative_id
    where a.food_id = p_food_id
    order by a.priority asc
    limit p_limit
  loop
    out := out || jsonb_build_object(
      'id', rec.id,
      'name_bn', rec.name_bn,
      'portion_label', rec.portion_label,
      'gi_category', rec.gi_category,
      'healthiness', rec.healthiness,
      'affordability', rec.affordability,
      'common_in_bd', rec.common_in_bd,
      'tags', to_jsonb(rec.tags)
    );
  end loop;
  return out;
end;
$$;


-- ---------- 10. DAILY RECOMMENDATION ----------
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
    'breakfast', public.pick_food(cls, plan.breakfast_main, null),
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
  return result;
end;
$$;


-- ---------- 11. RECORD MEAL INTAKE ----------
create or replace function public.record_meal_intake(
  p_meal_slot text,
  p_food_id text,
  p_food_name_bn text,
  p_status text,
  p_impact text,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  insert into public.meal_intake_log
    (user_id, meal_slot, food_id, food_name_bn, status, impact, notes)
  values
    (v_user, p_meal_slot, p_food_id, p_food_name_bn, p_status, p_impact, p_notes)
  returning id into v_id;
  return v_id;
end;
$$;


-- ---------- 12. DAILY LOG FETCH ----------
-- Returns the meal log for one day, optionally filtered by which plan_day
-- the user was on when they logged it (so day 1 vs day 5 don't collide).
-- `p_plan_day` is the 1..30 rotation index from public.meal_plan_days.day;
-- `p_date` is the calendar date (default = today in Asia/Dhaka). Both are
-- optional; if both are given, both must match.
create or replace function public.get_daily_log(
  p_date date default null,
  p_plan_day int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_date date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date);
  out jsonb;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    into out
  from (
    select id, meal_slot, food_id, food_name_bn, status, impact, notes,
           plan_day, impact_reason, created_at
    from public.meal_intake_log
    where user_id = v_user
      and hidden = false
      and meal_date = v_date
      and (p_plan_day is null or plan_day = p_plan_day)
    order by created_at asc
  ) t;
  return jsonb_build_object('date', v_date, 'plan_day', p_plan_day, 'items', out);
end;
$$;


-- ---------- 13. DASHBOARD SUMMARY ----------
create or replace function public.get_dashboard_summary(p_days int default 7)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_rows jsonb;
  v_total int;
  v_good int;
  v_neutral int;
  v_bad int;
  v_streak int := 0;
  cur_day date;
  i int;
  have_log boolean;
begin
  if v_user is null then raise exception 'Not authenticated'; end if;

  select coalesce(jsonb_agg(row_to_json(t) order by t.meal_date desc),
                  '[]'::jsonb)
    into v_rows
  from (
    select meal_date,
           count(*) as items,
           sum(case when impact='good' then 1 else 0 end) as good,
           sum(case when impact='neutral' then 1 else 0 end) as neutral,
           sum(case when impact='bad' then 1 else 0 end) as bad
    from public.meal_intake_log
    where user_id = v_user
      and meal_date >= ((now() at time zone 'Asia/Dhaka')::date - (p_days - 1))
    group by meal_date
    order by meal_date desc
  ) t;

  select count(*) into v_total from public.meal_intake_log
    where user_id = v_user
      and meal_date >= ((now() at time zone 'Asia/Dhaka')::date - (p_days - 1));
  select count(*) into v_good from public.meal_intake_log
    where user_id = v_user and impact='good'
      and meal_date >= ((now() at time zone 'Asia/Dhaka')::date - (p_days - 1));
  select count(*) into v_neutral from public.meal_intake_log
    where user_id = v_user and impact='neutral'
      and meal_date >= ((now() at time zone 'Asia/Dhaka')::date - (p_days - 1));
  select count(*) into v_bad from public.meal_intake_log
    where user_id = v_user and impact='bad'
      and meal_date >= ((now() at time zone 'Asia/Dhaka')::date - (p_days - 1));

  i := 0;
  loop
    cur_day := ((now() at time zone 'Asia/Dhaka')::date - i);
    select exists(
      select 1 from public.meal_intake_log
      where user_id = v_user and impact='good' and meal_date = cur_day
    ) into have_log;
    exit when not have_log;
    v_streak := v_streak + 1;
    i := i + 1;
    exit when i > 365;
  end loop;

  return jsonb_build_object(
    'days', p_days,
    'total_items', v_total,
    'good', v_good,
    'neutral', v_neutral,
    'bad', v_bad,
    'good_pct', case when v_total = 0 then 0 else round(v_good::numeric / v_total * 100) end,
    'bad_pct',   case when v_total = 0 then 0 else round(v_bad::numeric / v_total * 100) end,
    'streak_days', v_streak,
    'by_day', v_rows
  );
end;
$$;