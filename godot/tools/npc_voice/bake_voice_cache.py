# -*- coding: utf-8 -*-
"""NPC 語音快取離線烘焙：讀 data/npc_life/voices.json（每名 HERO 的聲線）＋ social.json 的 voice 台詞，
呼叫本機 TTS 引擎（AivisSpeech／VOICEVOX 相容 API：audio_query＋synthesis；Kokoro：/v1/audio/speech），
寫進 godot/assets/voice/cache/<lang>/<key>.wav，並更新 godot/assets/voice/voice_index.json（含長度與 30 Hz 音量包絡）。
key 的算法、情緒參數合併與 AudioQuery 套用規則，都必須與 systems/npc_life/npc_voice.gd 一致（hero_voice／clip_key／apply_query_params）。
台本：social.json 每行依 beats 的 emo 烘焙；反應行（"@刺激"）把說話者 speech.reactions 裡「每一句可能的反應」都烘好。
只用本機免費引擎；只用 Python 標準函式庫。
只需要開 voices.json 裡 heroes 用到的引擎（目前只有 AivisSpeech：D:\\Tools\\TTS\\start_aivis.cmd）；
開工前會先檢查，沒開就直接說要開哪個，不會半途失敗。烘焙前先預熱每個聲線（AivisSpeech 冷模型約 7 s）。
用法：python bake_voice_cache.py [--langs=ja,en] [--topics=mk_greet,...] [--force] [--prune]
  --prune：刪掉現在設定用不到的舊快取（換聲線後的舊檔，含 .import）
之後：godot --headless --path godot --import
"""
import array, hashlib, io, json, math, os, struct, sys, time, urllib.parse, urllib.request, wave

GODOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VOICES = os.path.join(GODOT, "data", "npc_life", "voices.json")
SOCIAL = os.path.join(GODOT, "data", "npc_life", "social.json")
HEROES = os.path.join(GODOT, "data", "npc_life", "heroes.json")
OUTDIR = os.path.join(GODOT, "assets", "voice")
INDEX = os.path.join(OUTDIR, "voice_index.json")
ENV_HZ = 30.0


KEY_FIELDS = ["engine", "speaker", "voice", "lang_code", "speed", "pitch", "intonation", "tempo", "pause", "volume", "rise"]


def hero_voice(voices, hero, lang, emo="neutral"):
    base = voices["heroes"].get(hero, {}).get(lang)
    if not base:
        return None
    v = {k: x for k, x in base.items() if k not in ("emotions", "label")}
    for k, x in base.get("emotions", {}).get(emo, {}).items():
        if k != "label":
            v[k] = x
    return v


def clip_key(hero, lang, v, text):
    parts = []
    for k in KEY_FIELDS:
        if k in v:
            x = v[k]
            parts.append("%s=%s" % (k, ("%.3f" % float(x)) if isinstance(x, (int, float)) and not isinstance(x, bool) else str(x)))
    sig = "%s|%s|%s|%s" % (hero, lang, ";".join(parts), text)
    return hashlib.sha1(sig.encode("utf-8")).hexdigest()[:16]


def apply_query_params(query, v, pitch_edit):
    for k, q in (("speed", "speedScale"), ("pitch", "pitchScale"), ("intonation", "intonationScale"), ("tempo", "tempoDynamicsScale"),
                 ("pause", "pauseLengthScale"), ("volume", "volumeScale")):
        if k in v:
            query[q] = float(v[k])
    if pitch_edit and float(v.get("rise", 0.0)) != 0.0 and query.get("accent_phrases"):
        moras = query["accent_phrases"][-1].get("moras", [])
        for k in range(len(moras) - 1, -1, -1):
            if float(moras[k].get("pitch", 0.0)) > 0.0:
                moras[k]["pitch"] = float(moras[k]["pitch"]) + float(v["rise"])
                if k > 0 and float(moras[k - 1].get("pitch", 0.0)) > 0.0:
                    moras[k - 1]["pitch"] = float(moras[k - 1]["pitch"]) + float(v["rise"]) * 0.4
                break


def script_items(voices, social, heroes, lang, only=None):
    """(hero, text, emo, 說明) — 每個主題行（依 beats 的 emo）＋反應行的所有候選。"""
    out = []
    for t in social["topics"]:
        if "voice" not in t or (only and t["id"] not in only):
            continue
        vt = t["voice"].get(lang, [])
        beats = t.get("beats", [])
        pair = t.get("pair", [])
        for i, ln in enumerate(t["lines"]):
            who = ln[0]
            spk = who if who in heroes else (pair[0] if who == "a" else pair[1])
            if str(ln[1]).startswith("@"):
                stim = ln[1][1:]
                for r in heroes.get(spk, {}).get("speech", {}).get("reactions", {}).get(stim, []):
                    if r.get(lang):
                        out.append((spk, r[lang], r.get("emo", "neutral"), f"{t['id']}#{i}@{stim}"))
                continue
            if i < len(vt) and vt[i]:
                emo = (beats[i] if i < len(beats) else {}).get("emo", "neutral")
                out.append((spk, vt[i], emo, f"{t['id']}#{i}"))
    return out


def http(url, data=None, ctype=None, timeout=300):
    req = urllib.request.Request(url, data=data, method="POST" if (data is not None or ctype == "post") else "GET")
    if ctype and ctype != "post":
        req.add_header("Content-Type", ctype)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def alive(eng):
    try:
        return http(eng["url"] + ("/version" if eng["api"] == "voicevox" else "/v1/audio/voices"), timeout=3)[0] == 200
    except Exception:
        return False


def fix_wav(b):
    """串流式 WAV 的 RIFF／data 長度可能是 0xFFFFFFFF：改成實際長度。"""
    if b[:4] != b"RIFF":
        return b
    b = bytearray(b)
    b[4:8] = struct.pack("<I", len(b) - 8)
    i = 12
    while i + 8 <= len(b):
        cid = bytes(b[i:i + 4]); size = struct.unpack("<I", b[i + 4:i + 8])[0]
        if cid == b"data":
            b[i + 4:i + 8] = struct.pack("<I", len(b) - i - 8); break
        i += 8 + size + (size & 1)
    return bytes(b)


def synth(eng, v, text):
    url = eng["url"]
    if eng["api"] != "voicevox":
        body = {"model": "kokoro", "input": text, "voice": v["voice"], "response_format": "wav", "stream": False,
                "speed": float(v.get("speed", 1.0)), "lang_code": v.get("lang_code", "a")}
        _, wav = http(f"{url}/v1/audio/speech", json.dumps(body).encode("utf-8"), "application/json")
        return fix_wav(wav)
    spk = int(v["speaker"])
    _, q = http(f"{url}/audio_query?" + urllib.parse.urlencode({"text": text, "speaker": spk}), ctype="post", timeout=120)
    query = json.loads(q)
    apply_query_params(query, v, bool(eng.get("pitch_edit", False)))
    _, wav = http(f"{url}/synthesis?speaker={spk}", json.dumps(query).encode("utf-8"), "application/json")
    return fix_wav(wav)


def envelope(wav):
    """16-bit PCM → 30 Hz RMS（每 4 個取樣取 1），正規化到 0..1；與 npc_voice.gd 的 envelope_from_wav 同算法。"""
    with wave.open(io.BytesIO(wav)) as w:
        ch, sr, sw, n = w.getnchannels(), w.getframerate(), w.getsampwidth(), w.getnframes()
        raw = w.readframes(n)
    if sw != 2:
        raise ValueError("只支援 16-bit PCM")
    a = array.array("h"); a.frombytes(raw)
    mono = a[::ch]
    frame = int(sr / ENV_HZ)
    env = []
    for k in range(0, len(mono), frame):
        seg = mono[k:k + frame:4]
        env.append(math.sqrt(sum((s / 32768.0) ** 2 for s in seg) / len(seg)) if len(seg) else 0.0)
    peak = max(env) if env and max(env) > 1e-6 else 1.0
    return [round(min(e / peak, 1.0), 3) for e in env], len(mono) / sr


def main():
    args = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in sys.argv[1:] if a.startswith("--"))
    langs = args.get("langs", "ja,en").split(",")
    only = set(args["topics"].split(",")) if "topics" in args else None
    voices = json.load(open(VOICES, encoding="utf-8"))
    social = json.load(open(SOCIAL, encoding="utf-8"))
    index = json.load(open(INDEX, encoding="utf-8")) if os.path.exists(INDEX) else {"clips": {}}
    heroes = json.load(open(HEROES, encoding="utf-8"))
    items = {lang: script_items(voices, social, heroes, lang, only) for lang in langs}
    # 只檢查／預熱實際用到的引擎與聲線（含情緒 style）
    need = {}
    for lang in langs:
        for hero, text, emo, _ in items[lang]:
            v = hero_voice(voices, hero, lang, emo)
            if v:
                need.setdefault(v["engine"], set()).add(v.get("speaker", -1))
    down = [e for e in need if not alive(voices["engines"][e])]
    if down:
        sys.exit("要先開引擎：" + "、".join(f"{e}（{voices['engines'][e]['label']}，{voices['engines'][e]['url']}）" for e in down))
    for e, spks in need.items():
        if voices["engines"][e]["api"] != "voicevox":
            continue
        for sp in sorted(spks):
            t0 = time.perf_counter()
            http(f"{voices['engines'][e]['url']}/initialize_speaker?speaker={sp}&skip_reinit=true", ctype="post", timeout=120)
            print(f"預熱 {e} {sp}：{time.perf_counter() - t0:.2f}s")
    made = skipped = 0
    live = set()
    for lang in langs:
        os.makedirs(os.path.join(OUTDIR, "cache", lang), exist_ok=True)
        for hero, text, emo, where in items[lang]:
            v = hero_voice(voices, hero, lang, emo)
            if not v:
                continue
            key = clip_key(hero, lang, v, text)
            if key in live:
                continue
            live.add(key)
            rel = f"cache/{lang}/{key}.wav"
            path = os.path.join(OUTDIR, rel)
            if key in index["clips"] and os.path.exists(path) and "force" not in args:
                skipped += 1
                continue
            t0 = time.perf_counter()
            wav = synth(voices["engines"][v["engine"]], v, text)
            gen = time.perf_counter() - t0
            open(path, "wb").write(wav)
            env, dur = envelope(wav)
            index["clips"][key] = {"file": "res://assets/voice/" + rel, "dur": round(dur, 3), "env": env, "hero": hero, "lang": lang,
                                   "engine": v["engine"], "voice": voices["heroes"][hero][lang].get("label", ""), "emo": emo, "where": where,
                                   "text": text, "gen_s": round(gen, 3)}
            made += 1
            print(f"{lang} {where:26s} {hero:6s} {emo:11s} gen {gen:5.2f}s dur {dur:5.2f}s  {text}")
    pruned = 0
    if "prune" in args and only is None:
        for k in [k for k, c in index["clips"].items() if c["lang"] in langs and k not in live]:
            f = os.path.join(OUTDIR, index["clips"][k]["file"].split("res://assets/voice/")[1])
            for x in (f, f + ".import"):
                if os.path.exists(x):
                    os.remove(x)
            del index["clips"][k]
            pruned += 1
    json.dump(index, open(INDEX, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"made {made} skipped {skipped} pruned {pruned} → {INDEX}")


if __name__ == "__main__":
    main()
