-- 14_plan_progress.sql
-- Tracks per-user 30-day meal plan progression.
-- plan_start_date lives on user_profiles. This script adds a getter/reset RPC.

create or replace function public.get_plan_progress(p_total_days int default 30)
returns table (
  day int,
  total_days int,
  plan_complete bool,
  plan_start_date date,
  days_elapsed int
)
language plpgsql
security definer
as $$
declare
  v_uid uuid := auth.uid();
  v_start date;
  v_today date := current_date;
  v_diff int;
  v_day int;
  v_complete bool := false;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select up.plan_start_date
    into v_start
    from public.user_profiles up
   where up.id = v_uid;

  if v_start is null then
    -- First-time user: stamp start date as today.
    update public.user_profiles
       set plan_start_date = v_today,
           updated_at = now()
     where id = v_uid;
    v_start := v_today;
  end if;

  v_diff := (v_today - v_start);
  if v_diff < 0 then
    v_diff := 0;
    update public.user_profiles
       set plan_start_date = v_today,
           updated_at = now()
     where id = v_uid;
    v_start := v_today;
  end if;

  v_day := (v_diff % p_total_days) + 1;

  -- Plan completes only after a full cycle (>= total_days elapsed).
  if v_diff >= p_total_days then
    v_complete := true;
    -- Roll the start date forward so the next cycle starts fresh.
    declare
      v_new_start date := v_start + make_interval(days => p_total_days);
    begin
      update public.user_profiles
         set plan_start_date = v_new_start,
             updated_at = now()
       where id = v_uid;
    end;
  end if;

  return query select v_day, p_total_days, v_complete, v_start, v_diff;
end;
$$;

grant execute on function public.get_plan_progress(int) to authenticated;