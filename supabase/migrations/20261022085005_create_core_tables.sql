-- ============================================
-- AI Dance Studio · Supabase 核心表 Migration
-- 项目: uljvndjkdfbvazhrrxmd (plus8-football)
-- ============================================

-- 启用 UUID 生成
create extension if not exists "pgcrypto";

-- --------------------------------------------
-- 1. media_assets — 素材资产（统一管理图片/视频/音频/成片）
-- --------------------------------------------
create table if not exists public.media_assets (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('image','video','audio','output','thumbnail')),
  storage_bucket text not null,
  storage_path text not null,
  original_name text,
  mime_type text not null,
  size_bytes bigint not null default 0 check (size_bytes >= 0),
  sha256 text,
  width integer,
  height integer,
  duration_ms integer,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists media_assets_kind_idx on public.media_assets(kind);
create index if not exists media_assets_created_idx on public.media_assets(created_at desc);

-- --------------------------------------------
-- 2. model_capabilities — 模型能力配置（取代硬编码）
-- --------------------------------------------
create table if not exists public.model_capabilities (
  provider text not null,
  model_id text not null,
  display_name text,
  enabled boolean not null default true,
  supported_modes text[] not null default '{}',  -- t2v, i2v, r2v_motion, r2v_reference, music_drive, dance_template, image_gen, image_edit
  supported_inputs jsonb not null default '{}'::jsonb,    -- {image, video, audio, start_frame, end_frame, multi_image}
  supported_params jsonb not null default '{}'::jsonb,     -- {negative_prompt, seed, motion_strength, camera, duration_range, aspect_ratios, resolutions}
  pricing_info jsonb not null default '{}'::jsonb,         -- {currency, unit, price_per, notes}
  constraints jsonb not null default '{}'::jsonb,          -- {max_duration_s, min_duration_s, max_file_size_mb, max_ref_vid_s, max_images}
  verification_note text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(provider, model_id)
);

-- 初始化 Seedance / Seedream / 可灵 能力数据（基于官方文档 + 交接文档）
insert into public.model_capabilities (provider, model_id, display_name, enabled, supported_modes, supported_inputs, supported_params, pricing_info, constraints, verification_note) values
('volcengine', 'doubao-seedance-2-5-260628', 'Seedance 2.5', true,
  '{t2v, i2v, r2v_reference, music_drive, dance_template}',
  '{"image": true, "video": true, "audio": true, "start_frame": false, "end_frame": false, "multi_image": false}',
  '{"negative_prompt": false, "seed": false, "motion_strength": false, "camera": false, "aspect_ratios": ["16:9","9:16","1:1","3:4","4:3"]}',
  '{"currency": "CNY", "unit": "video", "price_per": "duration_s", "notes": "约 5s=¥2.5，以官方账单为准"}',
  '{"min_duration_s": 4, "max_duration_s": 30}',
  '交接文档记录，需实测验证'),
('volcengine', 'doubao-seedance-2-0-260128', 'Seedance 2.0', true,
  '{t2v, i2v, r2v_reference, dance_template}',
  '{"image": true, "video": true, "audio": false, "start_frame": false, "end_frame": false, "multi_image": false}',
  '{"negative_prompt": false, "seed": false, "motion_strength": false, "camera": false, "aspect_ratios": ["16:9","9:16","1:1"]}',
  '{"currency": "CNY", "unit": "video", "price_per": "duration_s"}',
  '{"min_duration_s": 4, "max_duration_s": 15}',
  '交接文档记录'),
('volcengine', 'doubao-seedance-2-0-fast-260128', 'Seedance 2.0 Fast', true,
  '{t2v, i2v, dance_template}',
  '{"image": true, "video": false, "audio": false, "start_frame": false, "end_frame": false, "multi_image": false}',
  '{"negative_prompt": false, "seed": false, "aspect_ratios": ["9:16","16:9","1:1"]}',
  '{"currency": "CNY", "unit": "video", "price_per": "duration_s", "notes": "快速低成本版"}',
  '{"min_duration_s": 4, "max_duration_s": 15}',
  '交接文档记录，不支持视频参考'),
('volcengine', 'doubao-seedance-2-0-mini-260615', 'Seedance 2.0 Mini（最省钱）', true,
  '{t2v, i2v, dance_template}',
  '{"image": true, "video": false, "audio": false, "start_frame": false, "end_frame": false, "multi_image": false}',
  '{"negative_prompt": false, "seed": false, "aspect_ratios": ["9:16","16:9","1:1"]}',
  '{"currency": "CNY", "unit": "video", "price_per": "duration_s", "notes": "约 5s=¥2.5，最省钱"}',
  '{"min_duration_s": 4, "max_duration_s": 15}',
  '交接文档记录，mini 不支持视频参考（已在 seedance.js 拦截）'),
('volcengine', 'doubao-seedream-4-0-20260415', 'Seedream 4.0（生图）', true,
  '{image_gen, image_edit}',
  '{"image": true}',
  '{"negative_prompt": true, "seed": false, "sizes": ["1:1","16:9","9:16","3:4","4:3"]}',
  '{"currency": "CNY", "unit": "image"}',
  '{}',
  '交接文档记录'),
('kling', 'kling-v2-6', 'Kling v2-6（动作迁移）', true,
  '{r2v_motion}',
  '{"image": true, "video": true, "audio": false}',
  '{"negative_prompt": false, "mode": ["std","pro"], "character_orientation": ["video","image"]}',
  '{"currency": "CNY", "unit": "video"}',
  '{"max_duration_s": 30, "max_ref_vid_s": 30}',
  '交接文档记录，动作迁移专用'),
('kling', 'kling-v3', 'Kling v3（动作迁移）', true,
  '{r2v_motion}',
  '{"image": true, "video": true, "audio": false}',
  '{"negative_prompt": false, "mode": ["std","pro"]}',
  '{"currency": "CNY", "unit": "video", "notes": "需账号开通"}',
  '{"max_duration_s": 30}',
  '交接文档记录')
on conflict (provider, model_id) do update set
  display_name = excluded.display_name,
  enabled = excluded.enabled,
  supported_modes = excluded.supported_modes,
  supported_inputs = excluded.supported_inputs,
  supported_params = excluded.supported_params,
  pricing_info = excluded.pricing_info,
  constraints = excluded.constraints,
  updated_at = now();

-- --------------------------------------------
-- 3. generation_jobs — 核心生成任务表（持久化、状态机、租约）
-- --------------------------------------------
create table if not exists public.generation_jobs (
  id uuid primary key default gen_random_uuid(),

  -- 请求信息
  mode text not null check (mode in ('i2v','r2v_motion','r2v_reference','t2v','music_drive','dance_template','image_gen','image_edit','legacy')),
  provider text not null,
  model_id text not null,
  prompt text,
  negative_prompt text,
  aspect_ratio text default '9:16',
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 4),
  resolution text,

  -- 关联素材
  input_asset_ids uuid[] not null default '{}',
  input_snapshot jsonb not null default '{}'::jsonb,

  -- 状态机
  status text not null default 'queued' check (
    status in ('queued','validating','submitting','submitted','running',
               'reconciling','postprocessing','succeeded','failed',
               'cancel_requested','cancelled')
  ),

  -- Provider 侧
  provider_job_id text,
  provider_raw_response jsonb not null default '{}'::jsonb,

  -- 结果
  result_asset_id uuid references public.media_assets(id) on delete set null,
  result_url text,

  -- 费用
  estimated_cost numeric(12,4),
  actual_cost numeric(12,4),
  cost_currency text not null default 'CNY',
  cost_source text,  -- estimated_only / provider_bill / manual

  -- 失败信息
  failure_code text,
  failure_message text,

  -- 重试/并发控制
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  idempotency_key text,

  -- Worker 租约
  lease_owner text,
  lease_expires_at timestamptz,
  next_poll_at timestamptz,

  -- 时间戳
  submitted_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 唯一约束
create unique index if not exists jobs_owner_idem_uq
  on public.generation_jobs(idempotency_key) where idempotency_key is not null;
create unique index if not exists jobs_provider_remote_uq
  on public.generation_jobs(provider, provider_job_id) where provider_job_id is not null;

-- 查询索引
create index if not exists jobs_ready_idx on public.generation_jobs(status, next_poll_at)
  where status in ('queued','submitted','running','reconciling','postprocessing');
create index if not exists jobs_created_idx on public.generation_jobs(created_at desc);
create index if not exists jobs_mode_status_idx on public.generation_jobs(mode, status);

-- --------------------------------------------
-- 4. generation_events — 任务事件日志（可追溯）
-- --------------------------------------------
create table if not exists public.generation_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.generation_jobs(id) on delete cascade,
  kind text not null,   -- queued/submitted/progress/succeeded/failed/retry/reconcile/cancel/archive
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists events_job_idx on public.generation_events(job_id, created_at);

-- --------------------------------------------
-- 5. 兼容旧业务表（从 SQLite 迁移过来）
-- --------------------------------------------
create table if not exists public.models (
  id text primary key,
  name text not null,
  face_seed text,
  style_prompt text,
  ref_image text,
  remark text,
  status text default 'active',
  created_at timestamptz default now()
);

create table if not exists public.outfits (
  id text primary key,
  name text not null,
  image text,
  style_tag text,
  remark text,
  status text default 'active',
  created_at timestamptz default now()
);

create table if not exists public.scenes (
  id text primary key,
  name text not null,
  type text,
  ref_image text,
  description text,
  remark text,
  status text default 'active',
  created_at timestamptz default now()
);

create table if not exists public.dance_sources (
  id text primary key,
  name text not null,
  video_url text,
  duration_s real,
  bpm real,
  genre text,
  source text,
  hot_score real default 0,
  music_id text,
  remark text,
  status text default 'active',
  created_at timestamptz default now()
);

create table if not exists public.music (
  id text primary key,
  name text not null,
  audio_url text,
  bpm real,
  style text,
  copyright text default 'unverified',
  remark text,
  created_at timestamptz default now()
);

create table if not exists public.prompt_library (
  id text primary key,
  category text not null,
  title text not null,
  content text not null,
  tags text default '',
  hot_count integer default 0,
  created_at timestamptz default now()
);

create table if not exists public.templates (
  id text primary key,
  type text not null,
  name text not null,
  params jsonb,
  prompt text,
  enabled integer default 1,
  created_at timestamptz default now()
);

create table if not exists public.topics (
  id text primary key,
  name text not null,
  hot_score real default 0,
  enabled integer default 1,
  created_at timestamptz default now()
);

create table if not exists public.legacy_tasks (
  id text primary key,
  type text not null,
  status text default 'queued',
  model_id text,
  outfit_id text,
  scene_id text,
  dance_source_id text,
  music_id text,
  model_version text,
  params jsonb,
  result_url text,
  credit_cost real default 0,
  error text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.videos (
  id text primary key,
  task_id text,
  generation_job_id uuid references public.generation_jobs(id) on delete set null,
  file_url text,
  resolution text default '720p',
  bpm real,
  compliance text default 'pending',
  publish_status text default 'unpublished',
  play_count integer default 0,
  like_count integer default 0,
  download_count integer default 0,
  created_at timestamptz default now()
);

create table if not exists public.export_records (
  id text primary key,
  video_ids text,
  format text default 'mp4',
  resolution text default '720p',
  status text default 'pending',
  zip_url text,
  created_at timestamptz default now()
);

create table if not exists public.batches (
  id text primary key,
  batch_date text,
  model_id text,
  target_count integer default 10,
  produced_count integer default 0,
  hit_count integer default 0,
  created_at timestamptz default now()
);

-- --------------------------------------------
-- 6. 更新时间触发器（generation_jobs 和 media_assets）
-- --------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_jobs_updated on public.generation_jobs;
create trigger trg_jobs_updated before update on public.generation_jobs
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_assets_updated on public.media_assets;
create trigger trg_assets_updated before update on public.media_assets
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_capabilities_updated on public.model_capabilities;
create trigger trg_capabilities_updated before update on public.model_capabilities
  for each row execute function public.touch_updated_at();

-- --------------------------------------------
-- 7. Worker 租约原子抢占函数
-- --------------------------------------------
create or replace function public.claim_next_job(p_lease_owner text, p_timeout_ms int default 120000)
returns table(job_id uuid)
language plpgsql as $$
begin
  -- 抢占 queued 的新任务
  update public.generation_jobs
    set status = 'submitting',
        lease_owner = p_lease_owner,
        lease_expires_at = now() + (p_timeout_ms || ' milliseconds')::interval,
        attempt_count = attempt_count + 1,
        submitted_at = coalesce(submitted_at, now())
  where id = (
    select id from public.generation_jobs
      where status = 'queued'
      order by created_at asc
      limit 1
      for update skip locked
  );

  -- 抢占已到轮询时间的 running/submitted 任务
  update public.generation_jobs
    set status = 'running',
        lease_owner = p_lease_owner,
        lease_expires_at = now() + (p_timeout_ms || ' milliseconds')::interval
  where id = (
    select id from public.generation_jobs
      where status in ('submitted','running')
        and (lease_expires_at is null or lease_expires_at < now())
        and (next_poll_at is null or next_poll_at <= now())
      order by next_poll_at asc nulls first
      limit 1
      for update skip locked
  );

  return query
    select j.id from public.generation_jobs j
    where j.lease_owner = p_lease_owner
      and j.lease_expires_at > now()
      and j.status in ('submitting','running')
    order by j.updated_at desc
    limit 1;
end;
$$;
