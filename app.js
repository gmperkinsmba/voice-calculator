"use strict";
const $ = (id) => document.getElementById(id);
const input = $("transcript"), expression = $("expression"), answer = $("answer"), error = $("error"), copy = $("copy");
const HISTORY = "voice-calc-history-v1", SETTINGS = "voice-calc-settings-v1";
let reviewed = false, lastValue = null, lastUnit = "", recognition = null, pressStarted = false;
const safeLoad = (key, fallback) => { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } };
let history = safeLoad(HISTORY, []).filter(x => typeof x.text === "string" && typeof x.result === "number").slice(0, 20);
let settings = Object.assign({decimalStyle:"dot"}, safeLoad(SETTINGS, {}));
function save() { try { localStorage.setItem(HISTORY, JSON.stringify(history.slice(0, 20))); } catch {} }
function renderHistory() {
  const list = $("history"); list.replaceChildren();
  if (!history.length) { const li=document.createElement("li"); li.className="empty"; li.textContent="Your checked calculations will show up here."; list.append(li); return; }
  for (const item of history) { const li=document.createElement("li"), btn=document.createElement("button"), val=document.createElement("span"); btn.textContent=item.text; btn.setAttribute("aria-label",`Load ${item.text}`); btn.addEventListener("click",()=>{input.value=item.text;expression.value=item.expression;lastValue=item.result;lastUnit=item.unit||"unitless";answer.value=format(item.result,lastUnit);reviewed=true;copy.disabled=false;$("reviewState").textContent="REVIEWED";}); val.className="hist-result"; val.textContent=format(item.result,item.unit||"unitless"); li.append(btn,val); list.append(li); }
}
function format(n, unit="") { if(unit==="USD") return new Intl.NumberFormat(undefined,{style:"currency",currency:"USD"}).format(n); const value=new Intl.NumberFormat(undefined,{maximumSignificantDigits:12}).format(n); return unit==="cents"?`${value}¢`:value; }
function setUnreviewed() { reviewed=false; lastValue=null; lastUnit=""; answer.value="—"; copy.disabled=true; $("reviewState").textContent="EDIT BEFORE COPY"; }
function calculate() {
  error.textContent=""; const text=expression.value.trim();
  try { if(!text) throw Error("Enter or review an expression first."); const value=VoiceCalc.evaluate(text); lastValue=value; reviewed=true; answer.value=format(value,lastUnit); copy.disabled=false; $("reviewState").textContent="REVIEWED"; document.querySelector(".result-card").classList.add("fresh"); setTimeout(()=>document.querySelector(".result-card").classList.remove("fresh"),360); history.unshift({text:input.value||text,expression:text,result:value,unit:lastUnit,time:Date.now()}); history=history.slice(0,20); save(); renderHistory(); }
  catch(e) { setUnreviewed(); error.textContent=e.message; }
}
function parseInput() {
  error.textContent=""; setUnreviewed();
  try { const parsed=VoiceCalc.parseAndEvaluate(input.value,settings.decimalStyle); expression.value=parsed.expression; lastValue=parsed.result; lastUnit=parsed.unit; answer.value=format(parsed.result,parsed.unit); reviewed=false; copy.disabled=true; $("reviewState").textContent="CHECK THEN CALCULATE"; }
  catch(e) { expression.value=""; error.textContent=e.message; }
}
input.addEventListener("input",parseInput); expression.addEventListener("input",()=>{setUnreviewed();error.textContent="";});
$("calculate").addEventListener("click",calculate); input.addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();parseInput();if(expression.value)calculate();}}); expression.addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();calculate();}});
copy.addEventListener("click",async()=>{if(!reviewed||lastValue===null)return;try{await navigator.clipboard.writeText(format(lastValue,lastUnit));copy.textContent="Copied";setTimeout(()=>copy.textContent="Copy answer",1200);}catch{error.textContent="Clipboard access was blocked. Select and copy the answer.";}});
$("clear").addEventListener("click",()=>{input.value="";expression.value="";answer.value="—";error.textContent="";setUnreviewed();input.focus();});
document.querySelectorAll("[data-example]").forEach(b=>b.addEventListener("click",()=>{input.value=b.dataset.example;parseInput();}));
$("settingsOpen").addEventListener("click",()=>$("settings").showModal()); $("decimalStyle").value=settings.decimalStyle;
$("decimalStyle").addEventListener("change",e=>{settings.decimalStyle=e.target.value;localStorage.setItem(SETTINGS,JSON.stringify(settings));});
function clearHistory(){history=[];save();renderHistory();} $("clearHistory").addEventListener("click",clearHistory); $("removeHistory").addEventListener("click",()=>{clearHistory();$("settings").close();});
const Speech = window.SpeechRecognition || window.webkitSpeechRecognition;
if(Speech){ recognition=new Speech(); recognition.lang=navigator.language||"en-US"; recognition.interimResults=true; recognition.continuous=false;
  recognition.onresult=e=>{input.value=Array.from(e.results).map(r=>r[0].transcript).join("");parseInput();$("micStatus").textContent="Transcript ready. Check it, then calculate.";};
  recognition.onerror=e=>{$("micStatus").textContent=e.error==="not-allowed"?"Microphone access was denied. Type your calculation instead.":"Speech did not come through. Type or try again.";};
  recognition.onend=()=>{$("mic").setAttribute("aria-pressed","false");$("micStatus").textContent="Recording stopped. Check the transcript before calculating.";};
  const begin=()=>{if(pressStarted)return;pressStarted=true;try{recognition.start();$("mic").setAttribute("aria-pressed","true");$("micStatus").textContent="Listening. Release to stop. Speech may use your browser service.";}catch{pressStarted=false;$("micStatus").textContent="Speech is starting. Try again in a moment.";}};
  const stop=()=>{if(!pressStarted)return;pressStarted=false;try{recognition.stop();}catch{}};
  const mic=$("mic"); mic.addEventListener("pointerdown",e=>{e.preventDefault();mic.setPointerCapture(e.pointerId);begin();}); mic.addEventListener("pointerup",stop); mic.addEventListener("pointercancel",stop); mic.addEventListener("lostpointercapture",stop); mic.addEventListener("keydown",e=>{if((e.key===" "||e.key==="Enter")&&!pressStarted){e.preventDefault();begin();}}); mic.addEventListener("keyup",e=>{if(e.key===" "||e.key==="Enter"){e.preventDefault();stop();}}); mic.addEventListener("blur",stop);
} else { const mic=$("mic");mic.disabled=true;mic.title="Speech recognition is not available in this browser";mic.querySelector(".mic-label").textContent="Speech unavailable";$("micStatus").textContent="Speech recognition is not available here. Type your calculation instead."; }
renderHistory();
