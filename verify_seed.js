// Verify each (id, ...) row in 03_seed_foods.sql has exactly 18 column-tokens
// (17 commas between tokens). Column count = commas + 1.
const fs = require('fs');
const path = 'c:/Users/Nazmul/StudioProjects/diabeticsmeal/supabasesql/03_seed_foods.sql';
const lines = fs.readFileSync(path, 'utf8').split(/\r?\n/);
let insertStmts = 0;
let rowCount = 0;
const bad = [];
for (const line of lines) {
  const t = line.trim();
  if (!t.startsWith("('")) continue;
  rowCount++;
  // Split on top-level commas (ignoring commas inside single quotes and paren-arrays).
  // We only count commas at depth 0 (outside any string/array literal).
  let depth = 0;
  let inStr = false;
  let arrDepth = 0;
  let commaCount = 0;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (inStr) { if (c === "'") inStr = false; continue; }
    if (c === "'") { inStr = true; continue; }
    if (c === '[') { arrDepth++; continue; }
    if (c === ']') { arrDepth--; continue; }
    if (arrDepth > 0) continue;
    if (c === '(') depth++;
    else if (c === ')') depth--;
    else if (c === ',' && depth === 0) commaCount++;
  }
  const id = t.slice(2, t.indexOf("'"));
  if (commaCount !== 17) bad.push({ id, commaCount });
}
if (t && t.endsWith(')')) {} // silence
console.log(`Total data rows: ${rowCount}`);
console.log(`Malformed rows: ${bad.length}`);
for (const b of bad) console.log(`  ${b.id}: ${b.commaCount} commas (expected 17)`);
