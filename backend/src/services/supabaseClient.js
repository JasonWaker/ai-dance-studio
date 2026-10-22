/**
 * Supabase 客户端单例
 * - 读取 SUPABASE_URL + SUPABASE_ANON_KEY 或 SUPABASE_SERVICE_ROLE_KEY
 * - 本地开发时若无配置则返回 null，各服务做降级处理（用 SQLite / MOCK）
 */
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://uljvndjkdfbvazhrrxmd.supabase.co'
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY
const ANON_KEY = process.env.SUPABASE_ANON_KEY

const key = SERVICE_ROLE || ANON_KEY

let client = null
if (key && SUPABASE_URL) {
  client = createClient(SUPABASE_URL, key, {
    auth: { persistSession: false, autoRefreshToken: false }
  })
  console.log(`[supabase] ✅ 已连接: ${SUPABASE_URL.slice(0, 40)}... (role=${SERVICE_ROLE ? 'service_role' : 'anon'})`)
} else {
  console.log('[supabase] ⚠️ 未配置 SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY，将使用 SQLite/MOCK 模式')
}

export default client
export const isSupabaseAvailable = () => !!client
export const getSupabase = () => client
