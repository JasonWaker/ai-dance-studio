# AI 热门卡点舞 · 生产工作台（ai-dance-studio）

抖音 AI 卡点舞账号的**内部生产系统**：从选题 → 资产 → 生成 → 质检 → 成片 → 发布合规检查的全流程工作台。
已接入真实生成：**火山方舟（Seedance 2.5/2.0 视频 + Seedream 生图）** 与 **可灵 motion control（动作迁移）**。

## 一、快速启动

```bash
# 1. 安装依赖（monorepo，一次性）
cd ai-dance-studio
npm install

# 2. 配置 AI 密钥（backend/.env 已预填可灵+火山方舟 key，可自行替换）
cp backend/.env.example backend/.env   # 首次；已存在则直接编辑

# 3. 启动后端（端口 8787）
cd backend && npm run dev

# 4. 启动前端工作台（端口 5173，浏览器打开）
cd .. && npm run dev -w frontend
#    访问 http://localhost:5173
```

> 未配置密钥时自动进入**模拟生成模式**（全流程可演示）；配置密钥后自动切真实 API。
> 可在 `.env` 设 `MOCK_MODE=true` 强制模拟。

## 二、已接入的 AI 渠道（backend/.env）

| 渠道 | 字段 | 说明 |
| --- | --- | --- |
| 火山方舟 | `ARK_API_KEY` | Seedance 视频 + Seedream 生图（当前已配置） |
| 可灵 | `KLING_API_KEY` | 动作迁移 motion-control（当前已配置） |
| 即梦 | `JIMENG_API_KEY` + `JIMENG_BASE_URL` | 可选，未配置 |

**模型 ID 映射（官方）**：Seedance 2.5 = `doubao-seedance-2-5-260628`（音频条件驱动，4–30s）、Seedance 2.0 = `doubao-seedance-2-0-260128`（视频参考，4–15s）、2.0 fast = `doubao-seedance-2-0-fast-260128`、2.0 mini = `doubao-seedance-2-0-mini-260615`（最省钱）、Seedream 4.0 = `doubao-seedream-4-0-20260415`（生图）。
> 若你的方舟账号模型 ID 不同，以方舟控制台「开通管理」为准，改 `.env` 的 `SEEDANCE_MODEL` / `SEEDREAM_MODEL`。

## 三、工作台 8 个页面

| 页面 | 路径 | 作用 |
| --- | --- | --- |
| 数据看板 | `/dashboard` | 任务/成片统计、渠道密钥状态 |
| 选题中心 | `/topics` | 官方话题列表、今日灵感、素材准备清单 |
| 资产库 | `/assets` | 模特 / 造型 / 场景 / 舞源 / 音乐，上传即自动测 BPM |
| 任务台 | `/tasks` | 创建任务：动作迁移 / 音乐驱动 / **舞蹈模板直出** / 生图 / 换装；💡 词库、成本预估、新增舞蹈入库 |
| 质检台 | `/review` | 预览生成结果，通过 → 成品库，或重做 |
| 提示词中心 | `/prompts` | 分类提示词库 + 随机灵感 + 新增/复制/热度 |
| 成品库 | `/videos` | 已通过质检的成片，合规预检、批量导出、数据回填 |
| 发布助手 | `/publish` | 发布合规清单 + 文案违禁词检测 |

## 四、核心生成能力（实战方法论）

- **动作迁移（换人不换动作）**：模特图 + 参考舞蹈视频 → **可灵 motion control**（官方动作迁移，`character_orientation=video`），或 Seedance 2.0 视频参考。
- **音乐驱动（BGM 自动编舞）**：Seedance 2.5 原生音频条件（content 带 `audio_url`），自动跟随节奏编排动作。
- **舞蹈模板直出（最省钱）**：**舞蹈名当 prompt**——巴提巴提/科目三/擦玻璃等 10 个预置模板已入库，前端可随时新增（舞蹈名越火 Seedance 跳得越准）；默认 2.0 mini（5s ≈ ¥2.5）。
- **生图 → 定妆图一致性**：Seedream 生图做定妆图，后续以图为参考（图生图）保持长相/服装/场景一致。
- **提示词回溯**：任务详情可查看送 AI 的完整 prompt 并复制存档复现。
- **💡 词库**：造型/场景/动作/运镜/风格/文案 6 类词条点击追加，解决词穷。
- **BPM 卡点**：上传舞源/音乐自动检测 BPM 与重音时间戳（PyAV 实现，无需 ffmpeg）。

## 五、合规红线（系统内置提醒，务必遵守）

1. 画面前 5 秒标注「本视频含 AI 生成内容」+ 发布页勾选 AI 标签（未标注会被限流 50%–80%）。
2. **禁止真人/名人肖像**（AI 换脸属侵权红线），只用 AI 虚拟形象或自有授权肖像。
3. 内容控制在舞蹈欣赏 / 穿搭展示 / 健身向，避开「魅惑舞蹈」擦边（平台已点名打击）。
4. 音乐/舞源版权来源合规。
