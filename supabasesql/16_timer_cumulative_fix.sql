-- ============================================================
-- Amar Diet — Cumulative timer fix
-- Apply AFTER 01..15_*.sql.
--
-- Bug: `get_today_exercise_time_feedback()` hard-coded
--   a.day_index = 1
-- in its `today_assign` CTE. That means the per-exercise feedback
-- map returned to the Flutter client only ever contained the day 1
-- plan — every other day returned an empty map, so `_baseSeconds`
-- in WorkoutDetailsScreen always loaded as 0. That broke the
-- cumulative timer (morning walk + evening walk should add up).
--
-- Fix: use `public.calendar_day_to_index()` (created in 15_*.sql)
-- so the feedback map reflects TODAY's actual assignments. Sessions
-- for today's assignments already aggregate via `s.session_date =
-- v_today` so they naturally join to today's exercises.
-- ============================================================
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
