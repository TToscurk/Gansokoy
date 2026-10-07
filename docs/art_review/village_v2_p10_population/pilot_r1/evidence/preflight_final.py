import json,subprocess,time,statistics,sys
from pathlib import Path
samples=[]
# 讓 launcher／聊天表面的啟動繪製先穩定，再記錄完整十秒窗；不丟棄窗內樣本。
settle=5 if '--settle' in sys.argv else 0
time.sleep(settle)
for _ in range(10):
 p=subprocess.run(['nvidia-smi','--query-gpu=utilization.gpu','--format=csv,noheader,nounits'],capture_output=True,text=True,check=True)
 samples.append(int(p.stdout.strip().splitlines()[0])); time.sleep(1)
ps=r'''$p=@{};Get-CimInstance Win32_Process|ForEach-Object{$p[[int]$_.ProcessId]=$_.Name};Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine|Where-Object{$_.UtilizationPercentage -gt 0}|Sort-Object UtilizationPercentage -Descending|ForEach-Object{if($_.Name -match 'pid_(\d+)_'){$id=[int]$matches[1];[pscustomobject]@{pid=$id;name=$p[$id];engine=$_.Name;utilization=$_.UtilizationPercentage}}}|ConvertTo-Json -Compress'''
p=subprocess.run(['powershell.exe','-NoProfile','-Command',ps],capture_output=True,text=True)
try: consumers=json.loads(p.stdout) if p.stdout.strip() else []
except ValueError:consumers={'error':p.stderr,'raw':p.stdout}
a=statistics.mean(samples);low=min(samples);high=max(samples)
d={'samples_percent':samples,'mean':a,'min':low,'max':high,'range':high-low,'pass':a<=20 and high<=25 and high-low<=8,'gpu_consumers':consumers}
Path(sys.argv[1] if len(sys.argv)>1 else 'C:/Users/B365/AppData/Local/hermes/cache/scratch/pop/preflight_final.json').write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(d,ensure_ascii=False,indent=2));sys.exit(0 if d['pass'] else 2)
