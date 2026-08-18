-- ============================================================
-- Amar Diet — Diabetics-only workout catalogue (12 exercises)
-- Apply AFTER 01_schema.sql, 13_workouts.sql, 13b_workouts_seed.sql.
--
-- What this file does:
--   1. Upserts 12 curated exercises into `public.workouts` with
--      `video_url` set to the relative storage path (e.g. "Brisk
--      Walking.mp4"). The Flutter client resolves it via
--      `supabase.storage.from('exercise').createSignedUrl(...)` so
--      we never need to embed short-lived tokens in the DB.
--   2. Deactivates every other workout so today's list, the search
--      suggestions, and any analytics only ever show these 12.
--   3. Defines a small `get_program_day(day)` helper used by the
--      seeding block to map calendar day -> 30-day program index.
--   4. Reseeds `public.workout_assignments` for days 1..30 in a
--      Bangladesh-friendly progression:
--         Day 1  : low-intro  (2 of: stretching + walking)
--         Day 2  : active-rest (1: resistance-band  beginner)
--         Day 3  : cardio     (brisk walking)
--         Day 4  : active-rest (1: chair squats)
--         Day 5  : cardio+flex (cycling + shoulder stretch)
--         Day 6  : lower-body (stair climbing + sit-to-stand)
--         Day 7  : REST       (breathing only)
--         Day 8+ : cycle repeats days 1..6 with day 7 as REST
--         Day 30 : light finish (neck stretching + walking)
--      The exact workout ids below intentionally come from the 12
--      curated exercise list declared in this same file. Anything
--      else the user may have had assigned is wiped first so the
--      catalogue reduction sticks.
-- ============================================================

-- ---------- 0. HARD CLEANUP ----------
-- The workouts table must contain ONLY the 12 diabetes-friendly
-- exercises the user picked. Wipe assignments and sessions that
-- reference any other workout, then delete the workouts themselves.
-- This is intentionally destructive — the user's brief is explicit
-- that only these 12 should exist.
do $$
declare
  v_keep constant text[] := array[
    'ex01_band',         'ex02_walking',       'ex03_single_leg',
    'ex04_brisk_walk',   'ex05_cycling',       'ex06_chair_squats',
    'ex07_jogging',      'ex08_stair_climb',   'ex09_shoulder',
    'ex10_neck',         'ex11_sit_to_stand',  'ex12_wall_pushup'
  ];
begin
  -- 0a. Drop session rows that reference doomed workouts so the FK
  --     delete below does not fail.
  delete from public.workout_session_items
   where workout_id is not null
     and workout_id <> all(v_keep);

  delete from public.workout_sessions ws
   where not exists (
     select 1 from public.workout_session_items wsi
      where wsi.session_id = ws.id
   );

  -- 0b. Drop assignments for doomed workouts.
  delete from public.workout_assignments
   where workout_id <> all(v_keep);

  -- 0c. Finally delete the workouts themselves.
  delete from public.workouts
   where id <> all(v_keep);
end $$;

-- ============================================================
-- 1. THE 12 EXERCISES
-- ============================================================
-- video_url is a *storage path* (not a full URL). The Dart client
-- composes a signed URL on the fly so the bucket stays private and
-- the tokens remain short-lived. The mapping is exact:
--   ex02_walking    -> "Walking.mp4"
--   ex04_brisk_walk -> "Brisk Walking.mp4"
--   etc.
insert into public.workouts (
  id, name_bn, name_en, category, sub_category, intensity, difficulty,
  target_duration_seconds, duration_min, sets, repetitions, frequency_per_week,
  target_calories_kcal, description_bn, instructions, instructions_bn, equipment,
  beginner, elderly_friendly, chair_supported, low_impact, joint_friendly,
  balance_required, diabetes_suitable, hypertension_suitable, obesity_suitable,
  anemia_suitable, video_url, safety_notes_bn, contraindications, is_active
) values
('ex01_band',         'রেজিস্ট্যান্স ব্যান্ড ব্যায়াম',           'Resistance band exercise',
 'strength','upper_body','low','beginner',
 600, 10, 3, '10-15 reps', 3,
 25,
 'রেজিস্ট্যান্স ব্যান্ড দিয়ে হাত-পা ও কাঁধের পেশি শক্তিশালী করুন। সারা শরীরের জন্য হালকা টানাশক্তি বৃদ্ধি।',
 '["রেজিস্ট্যান্স ব্যান্ড পায়ে ভর দিয়ে মেঝেতে রাখুন",
   "উভয় হাতে ব্যান্ডের দুটি প্রান্ত ধরুন — হাত কাঁধ-সমান প্রশস্ত",
   "হাত সামনে সোজা করে বুকের উচ্চতায় তুলুন (front raise) — ১০ বার",
   "ব্যান্ড পিঠের পেছনে রেখে কনুই বাঁকিয়ে ওপরে তুলুন (upright row) — ১০ বার",
   "ব্যান্ড পিছনে পায়ের নিচে রেখে হাত সোজা করে নিচে টানুন (tricep press) — ১০ বার",
   "ধীরে ধীরে শ্বাস নিন, প্রতিটি টানে ২ সেকেন্ড ধরে রাখুন",
   "২ সেট, ৩০ সেকেন্ড বিশ্রাম নিয়ে পুনরাবৃত্তি"]'::jsonb,
 'ব্যান্ডের টান সহনীয় মাত্রায় রাখুন। হাঁটু সামান্য বাঁকা রাখুন।',
 '{"resistance_band"}'::text[],
 true,true,false,true,true,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Resistance%20Band%20Exercise.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9SZXNpc3RhbmNlIEJhbmQgRXhlcmNpc2UubXA0Iiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NzAxMzg1NCwiZXhwIjoyMTAyMzczODU0fQ.dshu1tuAYPV3GvGRQtZ7Cg0wY9YTjTz1upmn3V2ze7s',
 'ব্যান্ড ছিঁড়ে গেলে বন্ধ করুন। খালি পেটে করবেন না।',
 NULL, true),

('ex02_walking',      'হাঁটা',                              'Walking',
 'walking','lifestyle','low','beginner',
 900, 15, NULL, NULL, 7,
 60,
 'ধীর গতিতে হাঁটা — সার্বিক কার্ডিও ও মেটাবলিজমের জন্য সবচেয়ে নিরাপদ ব্যায়াম।',
 '["সোজা হয়ে দাঁড়ান, পিঠ সোজা, চোখ সামনে",
   "ধীরে ধীরে ১৫ মিনিট হাঁটুন (৩-৪ কিমি/ঘণ্টা গতি)",
   "প্রতি ৫ মিনিটে একবার গভীর শ্বাস নিন",
   "অনুভূতি: হালকা ঘাম হলে গতি ঠিক আছে",
   "শেষে ১ মিনিট ধীরে শ্বাস ছাড়ুন, হাঁটু স্ট্রেচ করুন"]'::jsonb,
 'ফুসফুসে ব্যথা, মাথা ঘোরা বা অতিরিক্ত হৃদস্পন্দন শুরু হলে থামুন।',
 '{}'::text[],
 true,true,true,true,true,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Walking.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9XYWxraW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTM4NzQsImV4cCI6MjEwMjM3Mzg3NH0.UmXkSkMf1r4nYUFghxe_7uQh9XDALI37TmVyQi-gyB0',
 'রক্তে শর্করা ৭০-এর নিচে হলে হাঁটবেন না — আগে হালকা খাবার খান।',
 'অস্থির কোমর বা হাঁটুর ব্যথা থাকলে বিরতি দিন।', true),

('ex03_single_leg',   'এক পায়ে দাঁড়ানো',                       'Single-Leg Stand',
 'balance','static','low','beginner',
 180, 3, 3, '30 sec/side', 5,
 12,
 'এক পায়ে দাঁড়িয়ে ভারসাম্য বজায় রাখা — পেশী সমন্বয় ও পতন-প্রতিরোধ।',
 '["চেয়ারের পেছনে হাত রেখে দাঁড়ান, পা কাঁধ-সমান",
   "ডান পা মেঝে থেকে ১০ সেমি তুলুন",
   "৩০ সেকেন্ড ধরে ভারসাম্য রাখুন, তারপর পা নামান",
   "বাম পায়ে পুনরাবৃত্তি",
   "চোখ খোলা রেখে, ধীরে ধীরে সময় বাড়ান (৬০ সেকেন্ড পর্যন্ত)",
   "৩ সেট, প্রতি সেটে উভয় পা"]'::jsonb,
 'চেয়ারের ঠিক পেছনে হাত রাখুন, ভর দেবেন না — সাপোর্ট শুধু নিরাপত্তার জন্য।',
 '{"chair"}'::text[],
 true,true,true,true,true,
 true,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Single-Leg%20Stand.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9TaW5nbGUtTGVnIFN0YW5kLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTM4OTksImV4cCI6MjEwMjM3Mzg5OX0.zVyY9xyLjqUIXA78mibQkmduQbsNhuVblcCDYo26wu8',
 'কোমর বা পায়ে ব্যথা থাকলে চেয়ারে বসে পায়ের স্ট্রেচিং করুন।',
 NULL, true),

('ex04_brisk_walk',   'দ্রুত হাঁটা',                          'Brisk Walking',
 'walking','lifestyle','medium','beginner',
 1200, 20, NULL, NULL, 5,
 110,
 'স্বাভাবিকের চেয়ে দ্রুত গতিতে হাঁটা — হৃদস্পন্দন বাড়ায়, ক্যালোরি খরচ করে, গ্লুকোজ নিয়ন্ত্রণে সাহায্য করে।',
 '["৫ মিনিট ধীরে হেঁটে শরীর গরম করুন (warm-up)",
   "তারপর গতি বাড়ান — যেন কথা বলতে পারেন কিন্তু গান গাইতে না পারেন",
   "হাত বুকের সামনে-পেছনে স্বাভাবিক দোলায়, পা জোরে মাটিতে রাখুন",
   "২০ মিনিট এই গতিতে হাঁটুন",
   "শেষ ২-৩ মিনিট ধীরে নেমে আসুন (cool-down)"]'::jsonb,
 'রক্তচাপ ১৪০/৯০-এর বেশি হলে আজ হাঁটবেন না।',
 '{}'::text[],
 true,true,false,true,true,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Brisk%20Walking.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9CcmlzayBXYWxraW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTM5MjIsImV4cCI6MjEwMjM3MzkyMn0.tDkKam167naUf5lCtqvaDR69eW8l8x3C9P9r5OTyFMY',
 'বুকে ব্যথা, মাথা ঘোরা বা হাঁপানে থামুন। জুতো ঢিলেঢালা হলে বদলে নিন।',
 'নিয়ন্ত্রিত হৃদরোগ থাকলে গতি ও সময় কমিয়ে শুরু করুন।', true),

('ex05_cycling',      'সাইকেল চালানো',                      'Cycling',
 'cardio','endurance','medium','intermediate',
 900, 15, NULL, NULL, 4,
 130,
 'সাইকেল চালানো — হাঁটুর ওপর কম চাপ পড়ে, ক্যালোরি খরচ বেশি, গ্লুকোজ নিয়ন্ত্রণে কার্যকর।',
 '["সাইকেলের সিট উচ্চতা ঠিক করুন — পা সোজা হলে পায়ের আঙুল মাটি স্পর্শ করবে",
   "৫ মিনিট ধীরে প্যাডেলিং করে শরীর গরম করুন",
   "মাঝারি গতিতে ১৫ মিনিট প্যাডেলিং — হৃদস্পন্দন বাড়ুক, কথা বলা যায়",
   "পাহাড়ে ওঠার সময় গিয়ার লাইট রাখুন, চাপ কমান",
   "শেষ ২-৩ মিনিট ধীরে নেমে আসুন, পায়ে স্ট্রেচিং করুন"]'::jsonb,
 'প্রতিটি পুনরাবৃত্তিতে রেজিস্ট্যান্স একই রাখুন।',
 '{"bicycle"}'::text[],
 false,false,false,true,false,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Cycling.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9DeWNsaW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTQxMzcsImV4cCI6MjEwMjM3NDEzN30.oDzPVu6OReIBLXg2D8XNdBSAIpZfQXfCca53cfPMn8M',
 'হাঁটুতে ব্যথা থাকলে রেজিস্ট্যান্স কমিয়ে শুরু করুন।',
 'গুরুতর হাঁটুর আর্থ্রাইটিস থাকলে সাইকেল এড়িয়ে চলুন।', true),

('ex06_chair_squats', 'চেয়ার স্কোয়াট',                    'Chair Squats',
 'strength','lower_body','medium','beginner',
 480, 8, 3, '10-12 reps', 3,
 45,
 'চেয়ারের সামনে দাঁড়িয়ে ধীরে বসা ও ওঠা — পায়ের পেশি (কোয়াড্রিসেপস, হ্যামস্ট্রিং) শক্তিশালী করে।',
 '["চেয়ারের ঠিক পেছনে দাঁড়ান, পা কাঁধ-সমান চওড়া",
   "পিঠ সোজা, চোখ সামনে, হাত সামনে সোজা (ভারসাম্যের জন্য)",
   "ধীরে নেমে মাথা ছোঁয়ার ঠিক আগে থামুন — ২ সেকেন্ড",
   "তারপর গোড়ালি ও কোমরের শক্তিতে উঠুন (হাতের ধাক্কা নয়)",
   "১০-১২ বার, ৩ সেট, ৬০ সেকেন্ড বিশ্রাম নিয়ে"]'::jsonb,
 'হাঁটু আঙুলের সামনে যাবে না।',
 '{"chair"}'::text[],
 true,true,true,true,true,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Chair%20Squats.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9DaGFpciBTcXVhdHMubXA0Iiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NzAxNDE1MywiZXhwIjoxODE4NTUwMTUzfQ.Lyl1-oOTZD-9sRh-rulyckvaxVGLJ-EMArkF6AeRSps',
 'হাঁটুতে ব্যথা বা শব্দ হলে কম গভীরতায় করুন।',
 'সদ্য হাঁটু সার্জারি হলে বিশেষজ্ঞের পরামর্শ নিন।', true),

('ex07_jogging',      'হালকা জগিং',                          'Light Jogging',
 'cardio','endurance','medium','intermediate',
 600, 10, NULL, NULL, 3,
 140,
 'ধীর গতিতে জগিং — ব্রিস্ক ওয়াকের চেয়ে বেশি ক্যালোরি খরচ, ফুসফুসের ক্ষমতা বাড়ায়।',
 '["৫ মিনিট ব্রিস্ক ওয়াক করে শরীর গরম করুন",
   "তারপর ধীরে জগিং শুরু — গতি যেন কথা বলতে পারেন, জোরে গান গাইতে না পারেন",
   "পা জোরে মাটিতে রাখুন, হাত স্বাভাবিক দোলায়",
   "১০ মিনিট জগিং, তারপর ২-৩ মিনিট হাঁটা ও স্ট্রেচিং দিয়ে শেষ",
   "সপ্তাহে ৩ দিনের বেশি জগিং করবেন না"]'::jsonb,
 'জগিং বাড়াতে থাকলে প্রতি সপ্তাহে মাত্র ১০% সময় বাড়ান।',
 '{}'::text[],
 false,false,false,false,false,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Light%20Jogging.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9MaWdodCBKb2dnaW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTQxNjksImV4cCI6MTgxODU1MDE2OX0.FHqJzgtY92eTx5Y-uEq3E7oFeyXwdx4_X-fkJ5lrNI4',
 'বুকে ব্যথা, অতিরিক্ত হাঁপানে বা মাথা ঘোরালে থামুন। শক্ত পৃষ্ঠে জগিং করবেন না।',
 'বাত, হাঁটু সমস্যা বা BMI ৩৫-এর বেশি হলে ব্রিস্ক ওয়াক-এ ফিরে যান।', true),

('ex08_stair_climb',  'সিঁড়ি ওঠানামা',                       'Stair Climbing',
 'cardio','endurance','medium','intermediate',
 720, 12, NULL, NULL, 4,
 150,
 'সিঁড়ি দিয়ে ওঠানামা — পায়ের পেশি ও হৃদযন্ত্রের জন্য অত্যন্ত কার্যকর, বাসায় বা বিল্ডিং-এ করা যায়।',
 '["৩ মিনিট ধীরে হেঁটে শরীর গরম করুন",
   "সিঁড়ির রেলিং ধরে ধীরে ১২ মিনিট ওঠানামা করুন",
   "একবার ২-৩ ধাপ উঠে, তারপর নামুন — শ্বাস ছাড়ুন",
   "হাঁটু সোজা রাখুন, পুরো পা সিঁড়িতে রাখুন",
   "বিশ্রাম: ৩০ সেকেন্ড, তারপর আরও ১-২ রাউন্ড"]'::jsonb,
 'রেলিং সবসময় ধরে রাখুন।',
 '{}'::text[],
 false,false,false,true,true,
 true,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Stair%20Climbing.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9TdGFpciBDbGltYmluZy5tcDQiLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg3MDE0MTg2LCJleHAiOjE4MTg1NTAxODZ9.vR4ODHR8xP5vCvX_eKZ_ZKBj5fOX_Fz6MphC4gfZKmE',
 'হাঁটুতে ব্যথা হলে থামুন। খালি পেটে করবেন না।',
 'সদ্য হাঁটু অপারেশন হলে বিশেষজ্ঞের পরামর্শ নিন।', true),

('ex09_shoulder',     'কাঁধের স্ট্রেচিং',                     'Shoulder Stretching',
 'flexibility','upper_body','low','beginner',
 240, 4, 2, '6 exercises', 5,
 14,
 'কাঁধের জড়তা কমায়, মেরুদণ্ডের উপরের অংশের নমনীয়তা বাড়ায়, কম্পিউটার/সেলাই-জাতীয় কাজের পর উপকারী।',
 '["সোজা হয়ে দাঁড়ান বা বসুন, পিঠ সোজা, কাঁধ শিথিল",
   "ডান হাত বুকের ওপর দিয়ে বাম কাঁধের দিকে টানুন — ১৫ সেকেন্ড ধরে রাখুন",
   "বাম হাত দিয়ে পুনরাবৃত্তি",
   "উভয় হাত পিছনে জোড়া লাগিয়ে বুকের দিকে টানুন — ১৫ সেকেন্ড",
   "উভয় হাত মাথার ওপরে তুলে আঙুল ভেতরে জোড়া লাগান — ১৫ সেকেন্ড বাড়ান",
   "উভয় হাত ঘাড়ের পেছনে জোড়া লাগিয়ে কনুই পেছনে টানুন — ১৫ সেকেন্ড",
   "প্রতিটি স্ট্রেচ ২ বার পুনরাবৃত্তি"]'::jsonb,
 'টানার সময় হালকা টান অনুভব করুন, ব্যথা নয়।',
 '{}'::text[],
 true,true,true,true,true,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Shoulder%20Stretching.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9TaG91bGRlciBTdHJldGNoaW5nLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTQyMDAsImV4cCI6MTgxODU1MDIwMH0.NMjk3v67jhUIDpzEpyvzqj-hx2RAL3mvqu9zwfJt7gk',
 'কাঁধে সাম্প্রতিক আঘাত বা অস্ত্রোপচার থাকলে গভীর স্ট্রেচ এড়িয়ে চলুন।',
 NULL, true),

('ex10_neck',         'ঘাড়ের স্ট্রেচিং',                    'Neck Stretching',
 'flexibility','neck','low','beginner',
 180, 3, 2, '6 exercises', 7,
 8,
 'ঘাড়ের জড়তা কমায়, মাথাব্যথা কমায়, দীর্ঘক্ষণ ফোন/কম্পিউটার ব্যবহারের পর জরুরি।',
 '["সোজা হয়ে বসুন, কাঁধ শিথিল",
   "মাথা ধীরে ডানে কাত করুন — ১৫ সেকেন্ড ধরে রাখুন",
   "বাম দিকে পুনরাবৃত্তি",
   "মাথা সামনে ঝোঁকান, চিবুক বুকের দিকে — ১৫ সেকেন্ড",
   "মাথা ধীরে ধীরে ডান দিকে ঘুরিয়ে ৫ সেকেন্ড, বাম দিকে ৫ সেকেন্ড — ২ বার",
   "শেষে কাঁধ একসাথে ওপরে তুলে ৫ সেকেন্ড শিথিল করুন, ৩ বার"]'::jsonb,
 'ঘাড় ঘোরানোর সময় মাথা ঘুরলে থামুন।',
 '{}'::text[],
 true,true,true,true,true,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Neck%20Stretching.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9OZWNrIFN0cmV0Y2hpbmcubXA0Iiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NzAxNDIxMywiZXhwIjoxODE4NTUwMjEzfQ.-T6-82AtKzXXULR7utYFQMcpS8u4giRrbTDR15lx9-Q',
 'ঘাড়ের মেরুদণ্ডে আঘাত, মাথা ঘোরা বা ভার্টিগো থাকলে হালকা ঘোরাঘুরি এড়িয়ে চলুন।',
 NULL, true),

('ex11_sit_to_stand', 'বসা থেকে দাঁড়ানো',                  'Sit-to-Stand',
 'strength','lower_body','low','beginner',
 360, 6, 3, '10 reps', 4,
 35,
 'চেয়ার থেকে বারবার উঠে আবার বসা — হাঁটু, নিতম্ব ও কোমরের পেশি শক্তিশালী করে, দৈনন্দিন কাজের সুবিধা।',
 '["চেয়ারের মাঝখানে সোজা হয়ে বসুন, পা মেঝেতে সমতল",
   "হাত কোমরে বা বুকের সামনে রাখুন",
   "গোড়ালি ও কোমরের শক্তিতে শরীর সামনে ঝুঁকিয়ে উঠুন — ২ সেকেন্ড",
   "২ সেকেন্ড দাঁড়িয়ে থাকুন, তারপর ধীরে নিয়ন্ত্রিত গতিতে বসুন",
   "১০ বার, ৩ সেট, ৬০ সেকেন্ড বিশ্রাম"]'::jsonb,
 'হাঁটু আঙুলের সামনে যাবে না; নিতম্ব সোজা রাখুন।',
 '{"chair"}'::text[],
 true,true,true,true,true,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Sit-to-Stand.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9TaXQtdG8tU3RhbmQubXA0Iiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NzAxNDIyNiwiZXhwIjoxODE4NTUwMjI2fQ.xD5PxkoMtlYDfJo7x73OT2RgsF3rkwoXNn_fn_IifqU',
 'হাঁটুতে ব্যথা বা শব্দ হলে কম গভীরতায় করুন।',
 NULL, true),

('ex12_wall_pushup',  'দেয়ালে ভর দিয়ে পুশ-আপ',          'Wall Push-Ups',
 'strength','upper_body','medium','beginner',
 420, 7, 3, '10-15 reps', 3,
 55,
 'দেয়ালে হাত রেখে পুশ-আপ — বুক, কাঁধ ও ত্রাইসেপ শক্তিশালী, মেঝেতে পুশ-আপের চেয়ে কম চাপ।',
 '["দেয়াল থেকে এক হাত দূরে দাঁড়ান, পা কাঁধ-সমান",
   "হাত কাঁধ-সমান উচ্চতায় দেয়ালে রাখুন, আঙুল ওপরে",
   "বুক দেয়ালের কাছে আনুন — ২ সেকেন্ড, ঠেলে পেছনে যান",
   "শরীর সোজা রাখুন, কোমর ভাঁজ করবেন না",
   "১০-১৫ বার, ৩ সেট, ৩০ সেকেন্ড বিশ্রাম"]'::jsonb,
 'মুখ দেয়ালের দিকে, পিঠ সোজা রাখুন।',
 '{}'::text[],
 true,true,true,true,true,
 false,true,true,true,true,
 'https://jjkvoiapufnhydnebdwk.supabase.co/storage/v1/object/sign/exercise/Wall%20Push-Ups.mp4?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV9mMDA1MDg0MS0yNjYzLTQ5NjYtOGE3Zi1hMWFjZTYyZjJhNDUiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJleGVyY2lzZS9XYWxsIFB1c2gtVXBzLm1wNCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODcwMTQwMzUsImV4cCI6MjEwMjM3NDAzNX0.qjuvWP3ee5fT26i6JrcZlWrVI8UA-YTiePAAa1dmhqM',
 'কাঁধে ব্যথা থাকলে গভীরতা কমান।',
 NULL, true)

on conflict (id) do update set
  name_bn = excluded.name_bn,
  name_en = excluded.name_en,
  category = excluded.category,
  sub_category = excluded.sub_category,
  intensity = excluded.intensity,
  difficulty = excluded.difficulty,
  target_duration_seconds = excluded.target_duration_seconds,
  duration_min = excluded.duration_min,
  sets = excluded.sets,
  repetitions = excluded.repetitions,
  frequency_per_week = excluded.frequency_per_week,
  target_calories_kcal = excluded.target_calories_kcal,
  description_bn = excluded.description_bn,
  instructions = excluded.instructions,
  instructions_bn = excluded.instructions_bn,
  equipment = excluded.equipment,
  beginner = excluded.beginner,
  elderly_friendly = excluded.elderly_friendly,
  chair_supported = excluded.chair_supported,
  low_impact = excluded.low_impact,
  joint_friendly = excluded.joint_friendly,
  balance_required = excluded.balance_required,
  diabetes_suitable = excluded.diabetes_suitable,
  hypertension_suitable = excluded.hypertension_suitable,
  obesity_suitable = excluded.obesity_suitable,
  anemia_suitable = excluded.anemia_suitable,
  video_url = excluded.video_url,
  safety_notes_bn = excluded.safety_notes_bn,
  contraindications = excluded.contraindications,
  is_active = true;

-- ============================================================
-- 2. RESEED WORKOUT_ASSIGNMENTS FOR ALL USERS
-- ============================================================
-- We schedule by *calendar day*, not the legacy day 1..30 program —
-- so regardless of when a user signed up, "Day 1" means the first
-- day after this migration. The table already exists and is
-- user-scoped via RLS, so we seed cross-user but mark inactive rows
-- for everyone who currently has assignments.
--
-- Helper CTE builds a 30-day plan using the curated ids above.
-- Pattern (rotates every 6 days, REST on day 7):
--   D1 intro     : ex02_walking(ex02), ex09_shoulder(ex01)
--   D2 active    : ex01_band(ex01)
--   D3 cardio    : ex04_brisk_walk(ex01)
--   D4 active    : ex06_chair_squats(ex01)
--   D5 cardio+fl : ex05_cycling(ex01), ex09_shoulder(ex02)
--   D6 lower-body: ex08_stair_climb(ex01), ex11_sit_to_stand(ex02)
--   D7 REST      : ex09_shoulder(ex01)          [light mobility only]
-- Each pattern day becomes one row in workout_assignments; positions
-- order the day's exercises.
insert into public.workout_assignments
  (user_id, day_index, workout_id, position, is_active)
select
  u.id as user_id,
  d.day_index,
  w.workout_id,
  w.position,
  true
from auth.users u
cross join (
  select 1 as day_index, 'ex02_walking'::text as workout_id, 0 as position
  union all select 1, 'ex09_shoulder', 1
  union all select 2, 'ex01_band', 0
  union all select 3, 'ex04_brisk_walk', 0
  union all select 4, 'ex06_chair_squats', 0
  union all select 5, 'ex05_cycling', 0
  union all select 5, 'ex09_shoulder', 1
  union all select 6, 'ex08_stair_climb', 0
  union all select 6, 'ex11_sit_to_stand', 1
  union all select 7, 'ex10_neck', 0
  -- Repeat the weekly pattern for the rest of the 30-day program.
  -- Day 8 = Day 1's plan, Day 9 = Day 2, etc. (modulo 7 with day 7 = REST).
  -- Days 29..30 use a lighter "finish" plan: walking + neck stretching.
  union all select 8, 'ex02_walking', 0 union all select 8, 'ex09_shoulder', 1
  union all select 9, 'ex01_band', 0
  union all select 10, 'ex04_brisk_walk', 0
  union all select 11, 'ex06_chair_squats', 0
  union all select 12, 'ex05_cycling', 0 union all select 12, 'ex09_shoulder', 1
  union all select 13, 'ex08_stair_climb', 0 union all select 13, 'ex11_sit_to_stand', 1
  union all select 14, 'ex10_neck', 0
  union all select 15, 'ex03_single_leg', 0 union all select 15, 'ex02_walking', 1
  union all select 16, 'ex01_band', 0
  union all select 17, 'ex04_brisk_walk', 0
  union all select 18, 'ex11_sit_to_stand', 0
  union all select 19, 'ex05_cycling', 0 union all select 19, 'ex12_wall_pushup', 1
  union all select 20, 'ex08_stair_climb', 0 union all select 20, 'ex11_sit_to_stand', 1
  union all select 21, 'ex10_neck', 0
  union all select 22, 'ex07_jogging', 0 union all select 22, 'ex02_walking', 1
  union all select 23, 'ex01_band', 0
  union all select 24, 'ex04_brisk_walk', 0
  union all select 25, 'ex12_wall_pushup', 0 union all select 25, 'ex06_chair_squats', 1
  union all select 26, 'ex05_cycling', 0 union all select 26, 'ex09_shoulder', 1
  union all select 27, 'ex08_stair_climb', 0 union all select 27, 'ex11_sit_to_stand', 1
  union all select 28, 'ex10_neck', 0
  union all select 29, 'ex02_walking', 0 union all select 29, 'ex10_neck', 1
  union all select 30, 'ex02_walking', 0 union all select 30, 'ex09_shoulder', 1
) w(day_index, workout_id, position)
cross join lateral (
  -- The variable `d` in the cross join is a single row, but we use
  -- a lateral so future versions of this query can swap in a
  -- per-user anchor day. For now we just emit the calendar day
  -- index directly.
  select w.day_index, w.workout_id, w.position
) d
on conflict (user_id, day_index, workout_id) do update set
  position = excluded.position,
  is_active = true;

-- ============================================================
-- 3. NEW RPC: get_today_workout (calendar-aware)
-- ============================================================
-- Replace the original 1-based RPC so that "today" always means the
-- calendar date (in Asia/Dhaka), mapped to a deterministic day_index
-- via the helper below. This matches the 15_*.sql seeds so the
-- first calendar day after this migration is day_index = 1.
create or replace function public.calendar_day_to_index()
returns int
language sql
stable
as $$
  -- Calendar day relative to a fixed epoch (the date this SQL was
  -- authored). Day 1 = first calendar day after migration. mod 30 + 1
  -- gives a deterministic 1..30 cycle.
  select (
    ((current_date - date '2025-01-01')::int % 30) + 1
  )::int;
$$;

-- Refresh get_today_workout to take the calendar anchor automatically.
-- Must DROP first because PostgreSQL refuses to remove a default on an
-- existing function parameter via CREATE OR REPLACE.
drop function if exists public.get_today_workout(integer);
create or replace function public.get_today_workout(
  p_day_index int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_day int := coalesce(p_day_index, public.calendar_day_to_index());
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
      'instructions_bn', w.instructions_bn,
      'equipment', w.equipment,
      'video_url', w.video_url,
      'position', a.position
    ) order by a.position, w.name_bn
  ), '[]'::jsonb)
  into v_assignments
  from public.workout_assignments a
  join public.workouts w on w.id = a.workout_id and w.is_active
  where a.user_id = v_user and a.day_index = v_day and a.is_active;

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
    'day_index', v_day,
    'today', v_today,
    'assignments', v_assignments,
    'session', v_session
  );
end $$;

grant execute on function public.get_today_workout(int) to authenticated;
grant execute on function public.calendar_day_to_index() to authenticated;

-- ============================================================
-- 4. SELF-HEAL: ensure the *current* user has every day's plan
-- ============================================================
-- The cross-join against `auth.users` is invisible from RLS contexts
-- on some Supabase projects, so a freshly created account can end up
-- with zero assignments even after the migration. This RPC seeds the
-- 30-day plan for the caller (and reactivates any rows that were
-- soft-deactivated by earlier migrations) so today's analytics surface
-- every exercise the user is meant to do.
create or replace function public.seed_my_workout_assignments()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_target uuid;
begin
  if v_user is null then
    return;
  end if;

  -- The "real" user id that should own the assignments. If the row is
  -- missing from auth.users (rare, but happens after manual deletes)
  -- we still seed under the JWT subject so analytics never see blanks.
  select u.id into v_target from auth.users u where u.id = v_user;
  if v_target is null then
    v_target := v_user;
  end if;

  -- Reactivate every existing assignment row for this user.
  update public.workout_assignments
     set is_active = true
   where user_id = v_target
     and is_active = false;

  insert into public.workout_assignments
    (user_id, day_index, workout_id, position, is_active)
  select
    v_target,
    w.day_index,
    w.workout_id,
    w.position,
    true
  from (
    select 1 as day_index, 'ex02_walking'::text as workout_id, 0 as position
    union all select 1, 'ex09_shoulder', 1
    union all select 2, 'ex01_band', 0
    union all select 3, 'ex04_brisk_walk', 0
    union all select 4, 'ex06_chair_squats', 0
    union all select 5, 'ex05_cycling', 0 union all select 5, 'ex09_shoulder', 1
    union all select 6, 'ex08_stair_climb', 0 union all select 6, 'ex11_sit_to_stand', 1
    union all select 7, 'ex10_neck', 0
    union all select 8, 'ex02_walking', 0 union all select 8, 'ex09_shoulder', 1
    union all select 9, 'ex01_band', 0
    union all select 10, 'ex04_brisk_walk', 0
    union all select 11, 'ex06_chair_squats', 0
    union all select 12, 'ex05_cycling', 0 union all select 12, 'ex09_shoulder', 1
    union all select 13, 'ex08_stair_climb', 0 union all select 13, 'ex11_sit_to_stand', 1
    union all select 14, 'ex10_neck', 0
    union all select 15, 'ex03_single_leg', 0 union all select 15, 'ex02_walking', 1
    union all select 16, 'ex01_band', 0
    union all select 17, 'ex04_brisk_walk', 0
    union all select 18, 'ex11_sit_to_stand', 0
    union all select 19, 'ex05_cycling', 0 union all select 19, 'ex12_wall_pushup', 1
    union all select 20, 'ex08_stair_climb', 0 union all select 20, 'ex11_sit_to_stand', 1
    union all select 21, 'ex10_neck', 0
    union all select 22, 'ex07_jogging', 0 union all select 22, 'ex02_walking', 1
    union all select 23, 'ex01_band', 0
    union all select 24, 'ex04_brisk_walk', 0
    union all select 25, 'ex12_wall_pushup', 0 union all select 25, 'ex06_chair_squats', 1
    union all select 26, 'ex05_cycling', 0 union all select 26, 'ex09_shoulder', 1
    union all select 27, 'ex08_stair_climb', 0 union all select 27, 'ex11_sit_to_stand', 1
    union all select 28, 'ex10_neck', 0
    union all select 29, 'ex02_walking', 0 union all select 29, 'ex10_neck', 1
    union all select 30, 'ex02_walking', 0 union all select 30, 'ex09_shoulder', 1
  ) w(day_index, workout_id, position)
  on conflict (user_id, day_index, workout_id) do update
    set position   = excluded.position,
        is_active  = true;
end $$;

grant execute on function public.seed_my_workout_assignments() to authenticated;
