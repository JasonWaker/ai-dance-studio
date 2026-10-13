import { spawn } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const SCRIPT = path.join(__dirname, 'bpm_detect.py')

/**
 * 检测媒体文件（视频/音频）的 BPM 与重音时间戳。
 * 依赖：python3 + av + numpy（已安装）。ffmpeg 缺失不影响本检测。
 */
export function detectBpm(filePath) {
  return new Promise((resolve, reject) => {
    const py = spawn('python3', [SCRIPT, filePath])
    let stdout = ''
    let stderr = ''
    py.stdout.on('data', (d) => (stdout += d))
    py.stderr.on('data', (d) => (stderr += d))
    py.on('close', (code) => {
      if (code !== 0) {
        return reject(new Error(`BPM 检测失败: ${stderr.slice(0, 200) || '脚本异常'}`))
      }
      try {
        resolve(JSON.parse(stdout))
      } catch (e) {
        reject(new Error(`BPM 结果解析失败: ${stdout.slice(0, 200)}`))
      }
    })
  })
}
