import pathlib, subprocess, hashlib, sys
repo = pathlib.Path(__file__).resolve().parents[5]
runner = repo / "godot/tools/run_village_v2_regression.sh"
text = runner.read_text(encoding="utf-8")
lines = text.splitlines()
selected = [line for line in lines if line.startswith("run ") and '" POP ' in line]
assert len(selected) == 4, selected
function = text[text.index("run() {"):text.index('if [ "${1:-}"')]
header = 'G="${GODOT:-D:/Godot/Godot_v4.7.2-stable_win64_console.exe}"; fail=0\n'
print("runner_sha256=" + hashlib.sha256(runner.read_bytes()).hexdigest(), flush=True)
print("gate_sha256=" + hashlib.sha256((repo / "godot/tools/verify_village_v2_population.gd").read_bytes()).hexdigest(), flush=True)
print("Actual runner POP entries selected=4; no other groups executed", flush=True)
sys.exit(subprocess.run(["bash", "-c", header + function + "\n".join(selected) + '\nprintf "POP subset failures: %s\\n" "$fail"\nexit "$fail"'], cwd=repo / "godot").returncode)
