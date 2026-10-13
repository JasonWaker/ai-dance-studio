#!/usr/bin/env python3
"""BPM 检测与重音时间戳（卡点引擎）——不依赖 ffmpeg，使用 PyAV 解码音频。"""
import sys, json, math
import numpy as np

def detect(path):
    import av
    c = av.open(path)
    a = c.streams.audio[0]
    sr = a.sample_rate
    parts = []
    for frame in c.decode(a):
        arr = frame.to_ndarray()
        if arr.ndim == 2 and arr.shape[0] == 1:
            arr = arr[0]
        parts.append(arr.astype(np.float32))
    if not parts:
        return {"bpm": None, "duration": 0, "beats": [], "error": "no audio"}
    mono = np.concatenate(parts)
    dur = len(mono) / sr
    mx = float(np.abs(mono).max())
    if mx <= 0:
        return {"bpm": None, "duration": dur, "beats": [], "error": "silence"}
    mono = mono / mx

    hop, win = 512, 1024
    n_frames = (len(mono) - win) // hop
    if n_frames < 30:
        return {"bpm": None, "duration": dur, "beats": [], "error": "too short"}
    env = np.zeros(n_frames)
    for i in range(n_frames):
        seg = mono[i * hop: i * hop + win]
        env[i] = math.sqrt(float((seg ** 2).mean()))
    env_c = env - env.mean()
    env_c = np.clip(env_c, 0, None)

    # 自相关估计 BPM（60~200）
    lag_min = int(sr * 0.28 / hop)
    lag_max = min(int(sr * 1.05 / hop), n_frames // 2)
    ac = np.correlate(env_c, env_c, 'full')[len(env_c) - 1:]
    seg_ac = ac[lag_min:lag_max]
    best_lag = lag_min + int(np.argmax(seg_ac))
    bpm = round(60.0 / (best_lag * hop / sr), 1)
    # 防半速/双速误判：取与常见 90-160 更接近的倍率
    if bpm < 90:
        bpm = round(bpm * 2, 1)

    # 重音时间戳：能量峰值（每拍一个）
    beat_interval = int(sr * 60.0 / bpm / hop)
    beat_interval = max(beat_interval, 4)
    beats = []
    prev = -beat_interval
    for i in range(0, n_frames):
        if env_c[i] > 0.12 and i - prev >= beat_interval * 0.8:
            beats.append(round(i * hop / sr, 3))
            prev = i
        if len(beats) >= 64:
            break
    # 去掉首尾 0.2s 内可能误判的点
    beats = [b for b in beats if 0.2 < b < dur - 0.2]
    return {"bpm": bpm, "duration": round(dur, 2), "beats": beats[:48], "error": None}

if __name__ == "__main__":
    path = sys.argv[1]
    out = detect(path)
    print(json.dumps(out, ensure_ascii=False))
