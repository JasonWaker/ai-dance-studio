#!/bin/bash
# ============================================
# AI 视频生成平台 - 本地一键启动
# 用法: ./start-local.sh
# 说明: 服务常驻后台运行；已运行时重复执行不会重复启动
# ============================================
cd "$(dirname "$0")"

# ---------- 启动后端 (8787) ----------
if lsof -ti :8787 > /dev/null 2>&1; then
  echo "[后端] 已在运行 (http://localhost:8787)"
else
  echo "[后端] 启动中..."
  (cd backend && nohup node src/index.js > /tmp/dance-backend.log 2>&1 &)
  sleep 2
  if lsof -ti :8787 > /dev/null 2>&1; then
    echo "[后端] ✅ 已启动"
  else
    echo "[后端] ❌ 启动失败，看日志: tail -20 /tmp/dance-backend.log"
  fi
fi

# ---------- 启动 Worker (独立进程，处理异步生成任务) ----------
if pgrep -f "worker/src/index.js" > /dev/null 2>&1; then
  echo "[Worker] 已在运行"
else
  echo "[Worker] 启动中 (处理异步生成任务)..."
  if [ ! -d "worker/node_modules" ]; then
    echo "[Worker] 首次启动，正在安装依赖..."
    (cd worker && npm install --silent 2>&1)
  fi
  (cd worker && nohup node src/index.js > /tmp/dance-worker.log 2>&1 &)
  sleep 3
  if pgrep -f "worker/src/index.js" > /dev/null 2>&1; then
    echo "[Worker] ✅ 已启动"
  else
    echo "[Worker] ❌ 启动失败，看日志: tail -20 /tmp/dance-worker.log"
  fi
fi

# ---------- 启动前端 (5173) ----------
if lsof -ti :5173 > /dev/null 2>&1; then
  echo "[前端] 已在运行 (http://localhost:5173)"
else
  echo "[前端] 启动中..."
  (cd frontend && nohup npm run dev -- --host 127.0.0.1 > /tmp/dance-frontend.log 2>&1 &)
  sleep 4
  if lsof -ti :5173 > /dev/null 2>&1; then
    echo "[前端] ✅ 已启动"
  else
    echo "[前端] ❌ 启动失败，看日志: tail -20 /tmp/dance-frontend.log"
  fi
fi

echo ""
echo "=========================================="
echo " 🎬 AI 视频生成平台就绪"
echo "    前端: http://localhost:5173"
echo "    后端: http://localhost:8787  (健康检查 /api/health)"
echo "    Worker: 后台运行中 (处理异步生成任务)"
echo "    Supabase: uljvndjkdfbvazhrrxmd"
echo "    日志: /tmp/dance-{backend,frontend,worker}.log"
echo ""
echo "    新入口: /generate (AI 视频生成) → /jobs (任务中心)"
echo "=========================================="
