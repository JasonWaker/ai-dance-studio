/**
 * 合规检查器：发布前强制清单 + 基础违禁词过滤。
 * 注意：此处仅做基础文本过滤与清单管理，最终发布合规以平台审核为准。
 */

const BANNED_WORDS = [
  // 低俗擦边类（示例基础词库，可按需扩充）
  '裸聊', '约炮', '包养', '一夜情', '援交', '色情', 'AV资源', '成人片',
  // 违禁/敏感（基础）
  '赌博', '博彩', '洗钱', '毒品', '枪支', '诈骗'
]

const LOW_EROTIC_HINTS = [
  '低胸特写', '裙底', '透视', '湿身诱惑', '擦边暗示', '呻吟'
]

export function checkCompliance({ title = '', caption = '', aiLabeled = false, aiTagChecked = false, hasRealFace = false }) {
  const problems = []
  const full = `${title} ${caption}`
  if (!aiLabeled) problems.push('画面前 5 秒未标注"本视频含 AI 生成内容"')
  if (!aiTagChecked) problems.push('发布页未勾选 AI 生成标签')
  if (hasRealFace) problems.push('出现真人面容（仅允许 AI 虚拟形象或自有授权肖像）')

  for (const w of BANNED_WORDS) {
    if (full.includes(w)) problems.push(`文案含违禁词"${w}"`)
  }
  for (const w of LOW_EROTIC_HINTS) {
    if (full.includes(w)) problems.push(`文案含擦边风险词"${w}"（需控制在舞蹈欣赏/穿搭展示范畴）`)
  }
  return {
    passed: problems.length === 0,
    problems,
    checklist: {
      aiLabeled,
      aiTagChecked,
      hasRealFace,
      bannedWords: BANNED_WORDS.filter((w) => full.includes(w)),
      eroticHints: LOW_EROTIC_HINTS.filter((w) => full.includes(w))
    }
  }
}

export const COMPLIANCE_CHECKLIST = [
  { key: 'aiLabeled', label: '画面前 5 秒标注"本视频含 AI 生成内容"' },
  { key: 'aiTagChecked', label: '发布页勾选 AI 生成标签' },
  { key: 'noRealFace', label: '无真人面容/未授权肖像' },
  { key: 'noErotic', label: '无低俗擦边动作/文案/暗示' },
  { key: 'noWatermark', label: '无水印、无违禁词' },
  { key: 'noDuplicate', label: '非批量搬运同质化' },
  { key: 'copyrightOk', label: '舞源/音乐版权来源合规' }
]
