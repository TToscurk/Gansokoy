# -*- coding: utf-8 -*-
"""NPC 情緒對話 改善前後對照＋情緒樣本＋客觀量測（開發用；要開 VOICEVOX、AivisSpeech、Kokoro）。
用 Kokoro 的 Python 跑（需要 numpy）：D:/Tools/TTS/Kokoro-FastAPI/.venv-gpu/Scripts/python emotion_ab.py [--out=D:/神社/proto/npc_voice/emotion]

輸出：
  sets/<set>_<lang>_before.wav／_after.wav  — 三組（＋B 的兩種聽者）改善前後整段對話
  emo/<hero>_<lang>_<emo>.wav                — 同一句話、不同情緒
  engines/aivis_michinoku_<style>.wav         — AivisSpeech 情緒模型（みちのくあいり）的真情緒 style 對照
  report.json                                  — 每段的音高（中位數 Hz、p10–p90 半音範圍）、語速、音量起伏
改善前＝平板書面句、基本聲線、句間固定 0.35 s；改善後＝遊戲實際台本（情緒參數、停頓、打斷、反應行取權重最高者）。
"""
import io, json, math, os, sys, wave
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import bake_voice_cache as B

GODOT = B.GODOT
voices = json.load(open(B.VOICES, encoding="utf-8"))
social = json.load(open(B.SOCIAL, encoding="utf-8"))
heroes = json.load(open(B.HEROES, encoding="utf-8"))
SR = 24000

FLAT = {
    "emo_daily_mk": {"who": ["marisa", "keine", "marisa", "keine", "keine", "marisa"],
        "ja": ["慧音、今日は早いな。", "授業の前に市場を回ろうと思っている。", "朝ごはんの買い出しか。", "それもある。", "一緒に来るか。今日は大根が安い。", "大根か。キノコなら行く。"],
        "en": ["Keine, you are early today.", "I plan to visit the market before class.", "Are you buying breakfast?", "That is one reason.", "Will you come with me? Daikon is cheap today.", "Daikon. I would go for mushrooms."]},
    "emo_news_mk": {"who": ["marisa", "keine", "marisa", "keine"],
        "ja": ["慧音、昨日森で光る石を見つけた。夜になると浮く。", "浮くのか。触っていないだろうな。", "少し触った。", "今すぐ見せなさい。"],
        "en": ["Keine, I found a glowing stone in the forest yesterday. It floats at night.", "It floats? You did not touch it, did you?", "I touched it a little.", "Show it to me now."]},
    "emo_news_mr": {"who": ["marisa", "reimu", "marisa", "reimu"],
        "ja": ["霊夢、昨日森で光る石を見つけた。夜になると浮く。", "浮く石は神社に持ち込まないで。", "もう賽銭箱の横に置いてきた。", "今すぐ持って帰りなさい。"],
        "en": ["Reimu, I found a glowing stone in the forest yesterday. It floats at night.", "Do not bring a floating stone to the shrine.", "I already left it beside the donation box.", "Take it back now."]},
    "emo_banter_rm": {"who": ["reimu", "marisa", "reimu", "marisa", "reimu", "marisa"],
        "ja": ["今日も賽銭箱は空だった。", "いつものことだ。", "笑い事ではない。何か入れていきなさい。", "用事を思い出した。", "逃げないで。", "また今度。"],
        "en": ["The donation box was empty again today.", "That always happens.", "It is not funny. Please put something in.", "I remembered an errand.", "Do not run away.", "Next time."]},
}
EMO_SENT = {"ja": {"marisa": "そっか、今日は雨が降るんだな。", "keine": "そうか、今日は雨が降るんだな。", "reimu": "そう、今日は雨が降るのね。"},
            "en": {h: "Oh, so it's going to rain today." for h in ("marisa", "keine", "reimu")}}
EMOS = ["neutral", "happy", "surprised", "doubt", "annoyed", "sigh"]


def to_mono24k(wav):
    with wave.open(io.BytesIO(wav)) as w:
        ch, sr, n = w.getnchannels(), w.getframerate(), w.getnframes()
        a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
    a = a[::ch]
    if sr != SR:
        t = np.arange(0, len(a) / sr, 1.0 / SR)
        a = np.interp(t, np.arange(len(a)) / sr, a).astype(np.float32)
    return a


def synth(hero, lang, text, emo):
    v = B.hero_voice(voices, hero, lang, emo)
    return to_mono24k(B.synth(voices["engines"][v["engine"]], v, text))


def write(path, a):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm)


def f0_track(a):
    """自相關法 F0（70–600 Hz）；只取有聲段。"""
    fl, hop = int(0.04 * SR), int(0.01 * SR)
    lo, hi = int(SR / 600), int(SR / 70)
    out, rms = [], []
    for i in range(0, len(a) - fl, hop):
        x = a[i:i + fl] - np.mean(a[i:i + fl])
        e = float(np.sqrt(np.mean(x * x)))
        rms.append(e)
        if e < 0.01:
            continue
        c = np.correlate(x, x, "full")[fl - 1:]
        c = c / (c[0] + 1e-9)
        k = lo + int(np.argmax(c[lo:hi]))
        if c[k] > 0.45:
            out.append(SR / k)
    return np.array(out), np.array(rms)


def measure(a, text):
    f0, rms = f0_track(a)
    voiced = rms[rms > 0.01]
    r = {"dur_s": round(len(a) / SR, 2), "chars_per_s": round(len(text) / max(len(a) / SR, 0.1), 2)}
    if len(f0) > 5:
        p10, p50, p90 = np.percentile(f0, [10, 50, 90])
        r.update({"f0_med_hz": round(float(p50), 1), "f0_range_st": round(12 * math.log2(p90 / p10), 2)})
    if len(voiced) > 5:
        db = 20 * np.log10(voiced + 1e-9)
        r["loud_sd_db"] = round(float(np.std(db)), 2)
    return r


def best_reaction(hero, stim, frm):
    pool = heroes.get(hero, {}).get("speech", {}).get("reactions", {}).get(stim, [])
    aff = float(heroes[hero].get("relationships", {}).get(frm, {}).get("affinity", 0.5))
    best, bw = None, -1
    for e in pool:
        w = float(e.get("w", 1.0))
        if e.get("aff") == "hi": w *= 2.0 if aff >= 0.8 else 0.4
        if e.get("aff") == "lo": w *= 2.0 if aff <= 0.55 else 0.4
        if "world" in e: w = 0.0          # 測試時世界沒有異狀
        if w > bw:
            best, bw = e, w
    return best


def after_script(t, lang):
    rows = []
    for i, ln in enumerate(t["lines"]):
        spk = ln[0]
        bt = t["beats"][i] if i < len(t.get("beats", [])) else {}
        lis = [h for h in t["pair"] if h != spk][0]
        if str(ln[1]).startswith("@"):
            r = best_reaction(spk, ln[1][1:], lis)
            rows.append((spk, r[lang], r["emo"], bt.get("pause", 0.12), 0.0, r["zh"]))
        else:
            rows.append((spk, t["voice"][lang][i], bt.get("emo", "neutral"), bt.get("pause", 0.0), bt.get("cut", 0.0), ln[1]))
    return rows


def silence(s):
    return np.zeros(int(s * SR), dtype=np.float32)


def main():
    args = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    out = args.get("out", r"D:\神社\proto\npc_voice\emotion")
    rep = {"sets": {}, "emo": {}, "engines": {}}
    tops = {t["id"]: t for t in social["topics"]}
    for sid, flat in FLAT.items():
        t = tops[sid]
        for lang in ("ja", "en"):
            # 改善前：平板句、基本聲線、句間 0.35 s
            seg, meas = [], []
            for who, text in zip(flat["who"], flat[lang]):
                a = synth(who, lang, text, "neutral")
                seg += [a, silence(0.35)]
                meas.append({"who": who, "text": text, **measure(a, text)})
            write(os.path.join(out, "sets", f"{sid}_{lang}_before.wav"), np.concatenate(seg))
            # 改善後：遊戲台本（遊戲裡句與句之間是語音長＋0.45 s，再加 beats 的停頓；被打斷的句子只播到 cut 成）
            seg2, meas2 = [], []
            for who, text, emo, pause, cut, zh in after_script(t, lang):
                a = synth(who, lang, text, emo)
                if cut:
                    a = a[: int(len(a) * cut)]
                    a[-int(0.03 * SR):] *= np.linspace(1, 0, int(0.03 * SR))
                    gap = 0.0
                else:
                    gap = 0.45
                seg2 += [silence(pause), a, silence(gap)]
                meas2.append({"who": who, "emo": emo, "text": text, "zh": zh, "cut": cut, **measure(a, text)})
            write(os.path.join(out, "sets", f"{sid}_{lang}_after.wav"), np.concatenate(seg2))
            rep["sets"][f"{sid}_{lang}"] = {"before": meas, "after": meas2}
            print("set", sid, lang, "done")
    for lang in ("ja", "en"):
        for h, text in EMO_SENT[lang].items():
            for emo in EMOS:
                a = synth(h, lang, text, emo)
                write(os.path.join(out, "emo", f"{h}_{lang}_{emo}.wav"), a)
                rep["emo"][f"{h}_{lang}_{emo}"] = {"text": text, **measure(a, text)}
            print("emo", h, lang, "done")
    # AivisSpeech 真情緒 style（引擎能力對照；不是遊戲目前的聲線）
    mich = {"標準": 1717361472, "喜び": 1717361478, "驚き": 1717361476, "怒り": 1717361474, "悲しみ": 1717361473, "嫌悪": 1717361475}
    eng = voices["engines"]["aivis"]
    text = "そうか、今日は雨が降るんだな。"
    for name, sp in mich.items():
        a = to_mono24k(B.synth(eng, {"engine": "aivis", "speaker": sp, "intonation": 1.3}, text))
        write(os.path.join(out, "engines", f"aivis_michinoku_{name}.wav"), a)
        rep["engines"][f"aivis_michinoku_{name}"] = {"text": text, **measure(a, text)}
    json.dump(rep, open(os.path.join(out, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("WROTE", out)


if __name__ == "__main__":
    main()
