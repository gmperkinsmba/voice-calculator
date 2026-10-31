"use strict";

const WORDS = new Map([
  ["plus", "+"], ["add", "+"], ["added", "+"], ["minus", "-"], ["subtract", "-"],
  ["times", "*"], ["multiplied", "*"], ["multiply", "*"], ["x", "*"],
  ["divided", "/"], ["divide", "/"], ["over", "/"], ["percent", "%"],
  ["of", "OF"], ["open", "("], ["close", ")"], ["parenthesis", "("],
  ["parentheses", "()"], ["point", "."], ["decimal", "."]
]);

function tokenize(text, decimalStyle = "dot") {
  if (typeof text !== "string" || text.length > 160) throw Error("Keep the calculation under 160 characters.");
  if (/[^\p{L}\p{N}\s()+*/%.,'-]/u.test(text)) throw Error("That symbol is not supported. Use numbers, parentheses, and basic operations.");
  if (/\d+[,.]\d+[,.]\d+/.test(text)) throw Error("Mixed decimal marks are unclear. Edit the expression using one style.");
  const lower = text.toLowerCase().replace(/\bopen parenthesis\b/g, " ( ").replace(/\bclose parenthesis\b/g, " ) ").replace(/\bparentheses\b/g, " ( ) ").replace(/\bdivided by\b/g, " divided ").replace(/\b(what is|what's|calculate|equals|equal to)\b/g, " ");
  const raw = lower.match(/\d+(?:[.,]\d+)?|[a-z]+|[()+*/%-]/g) || [];
  if (raw.join("") !== lower.replace(/\s/g, "")) throw Error("I could not read every part of that request. Edit the expression before calculating.");
  if (raw.join("").length === 0) throw Error("Enter a calculation to begin.");
  if (raw.some(t => /^(dollar|dollars|usd|cent|cents|meter|meters|mile|miles|foot|feet|inch|inches|kg|kilogram|kilograms|pound|pounds)$/.test(t))) throw Error("Units: currency and measurement units are not supported. Use unitless values.");
  const normalized = [];
  for (const token of raw) {
    if (/^\d/.test(token)) {
      if (token.includes(",") && token.includes(".")) throw Error("Mixed decimal marks are unclear. Edit the expression using one style.");
      if (token.includes(",") && (decimalStyle !== "comma" || /,\d{3}$/.test(token))) throw Error("This comma could mark a decimal or a thousands group. Edit it using one decimal style.");
      normalized.push(token.replace(",", "."));
    } else if (/^[()+*/%-]$/.test(token)) normalized.push(token);
  else if (WORDS.has(token)) normalized.push(WORDS.get(token));
    else if (/^(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred)$/.test(token)) normalized.push(String(wordNumber(token)));
    else throw Error(`I did not understand “${token}”. Edit the expression before calculating.`);
  }
  let s = normalized.join(" ").replace(/(\d)\s+\.\s+(\d)/g, "$1.$2").replace(/\bOF\b/g, " * ").replace(/%\s+of\b/g, "% *");
  s = s.replace(/(\d+(?:\.\d+)?)\s*%/g, "($1 / 100)").replace(/\s+/g, " ").trim();
  if (/[,.]/.test(text) && /\d+\.\d+/.test(s) && text.includes(",") && text.includes(".")) throw Error("Mixed decimal marks are unclear. Edit the expression using one style.");
  return s;
}

function wordNumber(w) {
  const nums = {zero:0,one:1,two:2,three:3,four:4,five:5,six:6,seven:7,eight:8,nine:9,ten:10,eleven:11,twelve:12,twenty:20,thirty:30,forty:40,fifty:50,sixty:60,seventy:70,eighty:80,ninety:90,hundred:100};
  return nums[w];
}

function evaluate(source) {
  const tokens = source.match(/\d+(?:\.\d+)?|[()+*/-]/g) || [];
  if (!tokens.length || tokens.join("") !== source.replace(/\s/g, "")) throw Error("Use numbers, parentheses, and + − × ÷ operators.");
  let i = 0;
  function expr() {
    let v = term();
    while (tokens[i] === "+" || tokens[i] === "-") { const op = tokens[i++], n = term(); v = op === "+" ? v + n : v - n; }
    return v;
  }
  function term() {
    let v = factor();
    while (["*", "/"].includes(tokens[i])) { const op = tokens[i++], n = factor(); if (op === "/" && n === 0) throw Error("You cannot divide by zero."); v = op === "*" ? v * n : v / n; }
    return v;
  }
  function factor() {
    if (tokens[i] === "+" || tokens[i] === "-") return (tokens[i++] === "-" ? -1 : 1) * factor();
    if (tokens[i] === "(") { i++; const v = expr(); if (tokens[i++] !== ")") throw Error("Check the parentheses."); return v; }
    const t = tokens[i++]; if (!t || !/^\d/.test(t)) throw Error("Check the expression near an operator.");
    const n = Number(t); if (!Number.isFinite(n)) throw Error("That number is too large."); return n;
  }
  const result = expr();
  if (i !== tokens.length) throw Error("Check the expression near the end.");
  if (!Number.isFinite(result) || Math.abs(result) > 1e15) throw Error("The result is outside the supported range.");
  return Number(result.toPrecision(12));
}

function parseAndEvaluate(text, decimalStyle) {
  const expression = tokenize(text, decimalStyle);
  return { expression, result: evaluate(expression), unit: "unitless" };
}
if (typeof module !== "undefined") module.exports = { tokenize, evaluate, parseAndEvaluate };
if (typeof window !== "undefined") window.VoiceCalc = { tokenize, evaluate, parseAndEvaluate };
