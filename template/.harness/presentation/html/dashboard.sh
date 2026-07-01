#!/usr/bin/env bash
# dashboard.sh — generate the self-contained static HTML dashboard.
#
# Read-only consumer of state/runtime.json + events/*.jsonl + log timestamps.
# Data is INJECTED inline into the HTML (a file:// page cannot fetch local
# JSON), a <meta refresh> reloads it, and the runtime regenerates it each cycle.
# Zero server, zero dependency, zero token.

set -uo pipefail

HTML_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$HTML_DIR/../.." && pwd)"
export HARNESS_DIR

RUNTIME_JSON="$HARNESS_DIR/state/runtime.json"
EVENTS_DIR="$HARNESS_DIR/events"
LOGS_DIR="$HARNESS_DIR/logs"
OUT_FILE="$HTML_DIR/index.html"

command -v jq >/dev/null 2>&1 || { echo "dashboard: jq required" >&2; exit 0; }

state_json="$(cat "$RUNTIME_JSON" 2>/dev/null || echo '{}')"
echo "$state_json" | jq -e . >/dev/null 2>&1 || state_json='{}'

# --- counters (read living documents) ---
# shellcheck source=../../runtime/state.sh
source "$HARNESS_DIR/runtime/state.sh"
counters="$(jq -n \
  --argjson inbox_pending "$(count_inbox_pending)" \
  --argjson parked "$(count_parked)" \
  --argjson sprint_open "$(count_sprint_open)" \
  --argjson sprint_done "$(count_sprint_done)" \
  --argjson roadmap_pending "$(count_roadmap_pending)" \
  --argjson roadmap_done "$(count_roadmap_done)" \
  '{inbox_pending:$inbox_pending, parked:$parked, sprint_open:$sprint_open,
    sprint_done:$sprint_done, roadmap_pending:$roadmap_pending, roadmap_done:$roadmap_done}')"

# --- telemetry mined from log filenames: cycle-NNNN-loop-START.log ---
telemetry_records() {
  shopt -s nullglob
  local f base loop start end dur
  for f in "$LOGS_DIR"/cycle-*.log; do
    base="$(basename "$f" .log)"
    IFS='-' read -r _ _ loop start <<<"$base"
    [[ "$start" =~ ^[0-9]+$ ]] || continue
    end="$(stat -c %Y "$f" 2>/dev/null)" || continue
    dur=$(( end - start )); (( dur < 0 )) && dur=0
    printf '{"loop":"%s","dur":%s}\n' "$loop" "$dur"
  done
  shopt -u nullglob
}
telemetry="$(telemetry_records | jq -s '
  ([.[].dur] | sort) as $d | {
    cycles: length,
    median_s: (if ($d|length)==0 then 0 elif (($d|length)%2)==1 then $d[(($d|length)/2|floor)]
               else (($d[($d|length)/2-1]+$d[($d|length)/2])/2) end),
    avg_s: (if ($d|length)==0 then 0 else (($d|add)/($d|length)|floor) end),
    loops: reduce .[] as $x ({}; .[$x.loop]=((.[$x.loop]//0)+1))
  }' 2>/dev/null)"
[[ -n "$telemetry" ]] || telemetry='{"cycles":0,"median_s":0,"avg_s":0,"loops":{}}'

# --- recent events feed (the "cards") ---
events_file="$EVENTS_DIR/$(date +%Y-%m-%d).jsonl"
recent_events="$(tail -n 50 "$events_file" 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')"
[[ -n "$recent_events" ]] || recent_events='[]'

# --- liveness via PID probe ---
pid="$(jq -r '.pid // 0' <<<"$state_json")"
alive=false
[[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )) && kill -0 "$pid" 2>/dev/null && alive=true

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
data="$(jq -n \
  --argjson state "$state_json" --argjson counters "$counters" \
  --argjson telemetry "$telemetry" --argjson events "$recent_events" \
  --argjson alive "$alive" --arg generated_at "$generated_at" \
  '{state:$state, counters:$counters, telemetry:$telemetry, events:$events, alive:$alive, generated_at:$generated_at}')"

{
cat <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="10">
<title>Ralph Harness · Dashboard</title>
<style>
  :root{--bg:#0d1117;--panel:#161b22;--border:#30363d;--fg:#e6edf3;--muted:#8b949e;
        --accent:#2f81f7;--green:#3fb950;--red:#f85149;--amber:#d29922;}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 ui-monospace,Menlo,Consolas,monospace}
  header{display:flex;align-items:center;gap:14px;padding:14px 22px;border-bottom:1px solid var(--border)}
  header h1{font-size:15px;margin:0;letter-spacing:1px}
  .pill{padding:2px 10px;border-radius:999px;font-size:12px;border:1px solid var(--border)}
  .live{color:var(--green);border-color:var(--green)} .dead{color:var(--muted)}
  .hgreen{color:var(--green);border-color:var(--green)} .hyellow{color:var(--amber);border-color:var(--amber)}
  .hred{color:var(--red);border-color:var(--red)}
  .spacer{flex:1}
  main{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;padding:22px}
  .card{background:var(--panel);border:1px solid var(--border);border-radius:8px;padding:14px}
  .card h2{font-size:11px;text-transform:uppercase;letter-spacing:1px;color:var(--muted);margin:0 0 10px}
  .big{font-size:26px;font-weight:600}
  .row{display:flex;justify-content:space-between;padding:2px 0}.row .k{color:var(--muted)}
  .bar{height:9px;background:#21262d;border-radius:6px;overflow:hidden;margin-top:6px}.bar>span{display:block;height:100%;background:var(--accent)}
  .feed{padding:0 22px 22px}
  .feed h2{font-size:11px;text-transform:uppercase;letter-spacing:1px;color:var(--muted)}
  .ev{display:flex;gap:10px;padding:6px 10px;border:1px solid var(--border);border-radius:6px;margin-bottom:6px;background:var(--panel)}
  .ev .t{color:var(--muted);min-width:64px}.ev .n{font-weight:600}.ev .m{color:var(--muted)}
  .ok{color:var(--green)}.warn{color:var(--amber)}.err{color:var(--red)}
  footer{color:var(--muted);padding:10px 22px;border-top:1px solid var(--border);font-size:12px}
</style></head><body>
<script>
HTML_HEAD

printf 'const DATA = %s;\n' "$data"

cat <<'HTML_TAIL'
</script>
<header>
  <h1>RALPH HARNESS</h1>
  <span id="live" class="pill"></span>
  <span id="health" class="pill"></span>
  <span id="loop" class="pill"></span>
  <div class="spacer"></div>
  <span id="clock" class="pill"></span>
</header>
<main id="grid"></main>
<section class="feed"><h2>Events</h2><div id="feed"></div></section>
<footer id="footer"></footer>
<script>
  const s=DATA.state||{}, c=DATA.counters||{}, t=DATA.telemetry||{}, ev=DATA.events||[];
  const $=(id)=>document.getElementById(id);
  const live=$("live");
  if(DATA.alive){live.textContent="\u25CF live";live.classList.add("live");}
  else{live.textContent="\u25CB idle";live.classList.add("dead");}
  const h=s.health||"green";
  $("health").textContent="health "+h; $("health").classList.add("h"+h);
  $("loop").textContent=(s.active_loop||"none")+(s.current_task?(" \u00B7 "+s.current_task):"");

  const card=(title,body)=>'<div class="card"><h2>'+title+'</h2>'+body+'</div>';
  const row=(k,v,cls)=>'<div class="row"><span class="k">'+k+'</span><span class="'+(cls||'')+'">'+v+'</span></div>';
  const sprintTotal=(c.sprint_open||0)+(c.sprint_done||0);
  const pct=sprintTotal>0?Math.round((c.sprint_done||0)/sprintTotal*100):0;

  const cards=[];
  cards.push(card("Runtime",
    row("cycle",s.cycle!=null?s.cycle:"-")+row("active",s.active_loop||"-")+
    row("task",s.current_task||"-")+row("last review",s.last_review||"-",
      s.last_review==="pass"?"ok":(s.last_review==="fail"?"err":""))));
  cards.push(card("Sprint",
    '<div class="big">'+pct+'%</div><div class="bar"><span style="width:'+pct+'%"></span></div>'+
    row("open / done",(c.sprint_open||0)+" / "+(c.sprint_done||0))));
  cards.push(card("Queue",
    row("inbox pending",c.inbox_pending||0)+row("parked",c.parked||0,(c.parked>0?"warn":""))+
    row("roadmap pending",c.roadmap_pending||0)+row("roadmap done",c.roadmap_done||0)));
  cards.push(card("Cadence",
    '<div class="big">'+(t.cycles||0)+'<span style="font-size:12px;color:var(--muted)"> cycles</span></div>'+
    row("median",(t.median_s||0)+"s")+row("avg",(t.avg_s||0)+"s")));
  const loops=t.loops||{};
  const dist=Object.keys(loops).length?Object.entries(loops).map(([k,v])=>row(k,v)).join(""):'<span class="k">no cycles yet</span>';
  cards.push(card("Loops",dist));
  $("grid").innerHTML=cards.join("");

  const cls=(e)=>{const r=e.result||"";if(e.event&&e.event.indexOf("fail")>=0||e.event&&e.event.indexOf("red")>=0||r==="fail")return"err";
    if(e.event&&e.event.indexOf("yellow")>=0)return"warn";if(r==="pass"||e.event&&e.event.indexOf("passed")>=0)return"ok";return"";};
  $("feed").innerHTML=ev.slice().reverse().map(e=>{
    const ts=(e.ts||"").replace("T"," ").replace("Z","").slice(11,19);
    return '<div class="ev"><span class="t">'+ts+'</span><span class="n '+cls(e)+'">'+(e.event||"")+
      '</span><span class="m">'+[e.loop,e.task,e.result].filter(Boolean).join(" \u00B7 ")+'</span></div>';
  }).join("")||'<span class="k">no events yet</span>';

  if(s.message) $("footer").textContent="message: "+s.message+"  \u00B7  ";
  $("footer").textContent=($("footer").textContent||"")+"generated "+(DATA.generated_at||"")+"  \u00B7  updated "+(s.updated_at||"-");
  const tick=()=>{$("clock").textContent=new Date().toISOString().replace("T"," ").slice(0,19)+"Z";};
  tick(); setInterval(tick,1000);
</script>
</body></html>
HTML_TAIL
} >"$OUT_FILE.tmp" && mv "$OUT_FILE.tmp" "$OUT_FILE"

echo "dashboard: wrote $OUT_FILE" >&2
