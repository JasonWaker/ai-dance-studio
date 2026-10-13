import Database from 'better-sqlite3'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import 'dotenv/config'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.resolve(__dirname, process.env.DATA_DIR || '../data')
const DB_PATH = path.join(DATA_DIR, 'studio.db')
fs.mkdirSync(DATA_DIR, { recursive: true })

const db = new Database(DB_PATH)
db.pragma('journal_mode = WAL')
db.pragma('foreign_keys = ON')

db.exec(`
CREATE TABLE IF NOT EXISTS model (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  face_seed TEXT,
  style_prompt TEXT,
  ref_image TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS outfit (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  image TEXT,
  style_tag TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS scene (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT,
  ref_image TEXT,
  description TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS dance_source (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  video_url TEXT,
  duration_s REAL,
  bpm REAL,
  genre TEXT,
  source TEXT,
  hot_score REAL DEFAULT 0,
  music_id TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS music (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  audio_url TEXT,
  bpm REAL,
  style TEXT,
  copyright TEXT DEFAULT 'unverified',
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS prompt_library (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  tags TEXT DEFAULT '',
  hot_count INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS template (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  name TEXT NOT NULL,
  params TEXT,
  prompt TEXT,
  enabled INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS topic (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  hot_score REAL DEFAULT 0,
  enabled INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS task (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  status TEXT DEFAULT 'queued',
  model_id TEXT,
  outfit_id TEXT,
  scene_id TEXT,
  dance_source_id TEXT,
  music_id TEXT,
  model_version TEXT,
  params TEXT,
  result_url TEXT,
  credit_cost REAL DEFAULT 0,
  error TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS video (
  id TEXT PRIMARY KEY,
  task_id TEXT,
  file_url TEXT,
  resolution TEXT DEFAULT '720p',
  bpm REAL,
  compliance TEXT DEFAULT 'pending',
  publish_status TEXT DEFAULT 'unpublished',
  play_count INTEGER DEFAULT 0,
  like_count INTEGER DEFAULT 0,
  download_count INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS export_record (
  id TEXT PRIMARY KEY,
  video_ids TEXT,
  format TEXT DEFAULT 'mp4',
  resolution TEXT DEFAULT '720p',
  status TEXT DEFAULT 'pending',
  zip_url TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS batch (
  id TEXT PRIMARY KEY,
  batch_date TEXT,
  model_id TEXT,
  target_count INTEGER DEFAULT 10,
  produced_count INTEGER DEFAULT 0,
  hit_count INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);
`)

// ---------- 种子数据（首次启动） ----------
const count = db.prepare('SELECT COUNT(*) AS c FROM prompt_library').get().c
if (count === 0) {
  const seed = db.transaction(() => {
    const insPrompt = db.prepare('INSERT INTO prompt_library (id, category, title, content, tags) VALUES (?,?,?,?,?)')
    const prompts = [
      ['p1', '造型', '辣妹风', '黑色抹胸上衣、铆钉短裤、厚底长靴、腿部绑带', '辣妹,性感,夜店'],
      ['p2', '造型', '甜妹风', '粉色吊带裙、白色帆布鞋、双马尾、清新妆容', '甜妹,清纯,少女'],
      ['p3', '造型', '运动风', '紧身运动背心、瑜伽裤、运动鞋、高马尾', '运动,健身,活力'],
      ['p4', '造型', '职场风', '修身西装外套、白衬衫、包臀裙、高跟鞋', '职场,OL,干练'],
      ['p5', '场景', '居家走廊', '灰瓷砖地面、米色墙面、门框、吊顶筒灯', '居家,走廊,室内'],
      ['p6', '场景', '卧室', '暖色调灯光、床品、落地窗、木地板', '卧室,温馨,室内'],
      ['p7', '场景', '街拍', '霓虹灯、城市夜景、人行道、虚化背景', '街拍,城市,夜晚'],
      ['p8', '场景', '纯色背景', '纯色 studio 背景板，干净简洁', '影棚,简约,纯色'],
      ['p9', '运镜', '卡点切镜', '跟随音乐重音快速切镜、低角度仰拍、抖动运镜', '卡点,切镜,运镜'],
      ['p10', '运镜', '环绕运镜', '围绕人物缓慢环绕运镜、中景到特写推进', '环绕,运镜,推进'],
      ['p11', '动作', '大幅卡点', '动作幅度大、定点卡点、律动感强、每个重音一个爆点', '卡点,幅度大,律动'],
      ['p12', '动作', '手势舞', '以手部和上半身动作为主、动作干净利落', '手势舞,上半身'],
      ['p13', '风格', '潮流暗黑', '赛博霓虹、暗黑街头、金属质感', '赛博,暗黑,潮流'],
      ['p14', '风格', '清新校园', '清新校园风、自然光、青春气息', '校园,清新,青春'],
      ['p15', '文案', '钩子文案', '这个舞也太带感了，谁懂啊', '文案,钩子'],
      ['p16', '文案', '钩子文案', '一开口就是老舞蹈生了', '文案,钩子'],
      ['p17', '文案', '钩子文案', '今日份快乐是这支舞给的', '文案,钩子'],
      ['p18', '文案', '状态文案', '我此刻的精神状态：疯癫模式', '文案,状态,魔性'],
      ['p19', '文案', '状态文案', '健身人的快乐就是这么简单', '文案,状态,健身'],
      ['p20', '文案', '状态文案', '假期在家，跳舞续命', '文案,状态,假期']
    ]
    for (const p of prompts) insPrompt.run(...p)

    const insTopic = db.prepare('INSERT INTO topic (id, name, hot_score, enabled) VALUES (?,?,?,1)')
    const topics = [
      ['t1', '#AI卡点魔性跳舞', 98],
      ['t2', '#抖音ai创作全新升级', 95],
      ['t3', '#AI丝滑卡点跳舞', 90],
      ['t4', '#随变ai随便玩', 80]
    ]
    for (const t of topics) insTopic.run(...t)

    const insTemplate = db.prepare('INSERT INTO template (id, type, name, params, prompt) VALUES (?,?,?,?,?)')
    const templates = [
      ['tmp1', '生图', '辣妹居家走廊', JSON.stringify({ ratio: '9:16', model: 'seedream' }), '一位20岁左右的长发亚洲女孩，[发型][妆容]固定不变，身穿黑色抹胸上衣、铆钉短裤、厚底长靴、腿部绑带，站在居家走廊中（灰瓷砖地面、米色墙面、门框、吊顶筒灯），全身，舞蹈准备姿势，真实摄影质感，自然光，皮肤细腻有质感，高清8k，9:16竖构图。负面：畸形、崩坏、多余手指、低质量、模糊'],
      ['tmp2', '动作迁移', 'K-pop 卡点（默认）', JSON.stringify({ ratio: '9:16', duration: 10, candidates: 2 }), '驱动模特复刻参考视频舞蹈动作，动作连贯、与音乐重音对齐'],
      ['tmp3', '音乐驱动', 'BGM 自动编舞', JSON.stringify({ ratio: '9:16', candidates: 2, model: 'seedance-2.5' }), '让角色跟随音乐重音编排舞蹈，动作幅度大、节奏感强、K-pop 风格，场景与造型保持参考图一致'],
      ['tmp4', '剪辑', '卡点剪辑默认', JSON.stringify({ bpmMode: 'auto', transition: 'cut' }), 'BPM 自适应检测，重音处切镜，前5秒叠加"本视频含AI生成内容"标注'],
      ['tmp5', '结构', '舞蹈+舞源指路', JSON.stringify({ dance: 15, tail: 3 }), '舞蹈主体15s + 舞源指路尾屏3s（搜索关键词画面）'],
      ['tmp6', '结构', '纯卡点', JSON.stringify({ dance: 15, tail: 0 }), '整段15s纯舞蹈卡点，无尾屏']
    ]
    for (const t of templates) insTemplate.run(...t)
  })
  seed()
}

// ---------- 舞蹈模板补种（幂等，type='舞蹈'：热门舞蹈模板直出） ----------
const insTplId = 'td'
const danceTpl = db.prepare('INSERT OR IGNORE INTO template (id, type, name, params, prompt) VALUES (?,?,?,?,?)')
const danceTemplates = [
  ['td1', '舞蹈', '巴提巴提舞', JSON.stringify({ ratio: '9:16' }), '双手高举左右摆动、胯部左右顶动、点头律动、脚下小幅跳跃'],
  ['td2', '舞蹈', '科目三', JSON.stringify({ ratio: '9:16' }), '丝滑小连招、左右滑步、扭胯、手臂交替甩动'],
  ['td3', '舞蹈', '擦玻璃舞', JSON.stringify({ ratio: '9:16' }), '双手上下做擦玻璃动作、弯腰、横向移动、节奏感强'],
  ['td4', '舞蹈', '摆摆舞', JSON.stringify({ ratio: '9:16' }), '双手左右摆动、身体左右横移、俏皮可爱、步伐轻快'],
  ['td5', '舞蹈', '手势舞', JSON.stringify({ ratio: '9:16' }), '以手部和上半身为主、指尖精细律动、动作干净利落'],
  ['td6', '舞蹈', '摇花手', JSON.stringify({ ratio: '9:16' }), '双手交替摇动、魔性节奏、身体轻微摇摆'],
  ['td7', '舞蹈', '抖肩舞', JSON.stringify({ ratio: '9:16' }), '双肩快速抖动、脚步轻点、头部微微摆动'],
  ['td8', '舞蹈', '韩舞女团', JSON.stringify({ ratio: '9:16' }), '扭胯、wave 律动、定点卡点、手臂大幅摆动'],
  ['td9', '舞蹈', 'Jazz 爵士', JSON.stringify({ ratio: '9:16' }), '动作大开大合、wave 律动、定点爆点、表情酷飒'],
  ['td10', '舞蹈', '螃蟹舞', JSON.stringify({ ratio: '9:16' }), '横向行走、双手开合、左右交替、节奏卡点']
]
const danceInsert = db.transaction(() => {
  for (const t of danceTemplates) danceTpl.run(...t)
})
danceInsert()

export default db
