import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const addonRoot = path.dirname(testDir);
const files = fs.readdirSync(addonRoot).filter((name) => name.endsWith(".lua"));
const failures = [];

function longBracketAt(source, index) {
  const match = source.slice(index).match(/^\[(=*)\[/);
  return match ? { open: match[0], close: `]${match[1]}]` } : null;
}

function tokens(source, file) {
  const words = [];
  const delimiters = [];
  const pairs = { ")": "(", "]": "[", "}": "{" };
  let index = 0;
  while (index < source.length) {
    const char = source[index];
    const next = source[index + 1];

    if (char === "-" && next === "-") {
      const long = longBracketAt(source, index + 2);
      if (long) {
        const end = source.indexOf(long.close, index + 2 + long.open.length);
        index = end < 0 ? source.length : end + long.close.length;
      } else {
        const end = source.indexOf("\n", index + 2);
        index = end < 0 ? source.length : end + 1;
      }
      continue;
    }

    if (char === '"' || char === "'") {
      const quote = char;
      index += 1;
      while (index < source.length) {
        if (source[index] === "\\") index += 2;
        else if (source[index] === quote) { index += 1; break; }
        else index += 1;
      }
      continue;
    }

    const long = char === "[" ? longBracketAt(source, index) : null;
    if (long) {
      const end = source.indexOf(long.close, index + long.open.length);
      index = end < 0 ? source.length : end + long.close.length;
      continue;
    }

    if (/[A-Za-z_]/.test(char)) {
      const match = source.slice(index).match(/^[A-Za-z_][A-Za-z0-9_]*/)[0];
      words.push(match);
      index += match.length;
      continue;
    }

    if ("([{)]}".includes(char)) {
      if ("([{".includes(char)) delimiters.push(char);
      else if (delimiters.pop() !== pairs[char]) failures.push(`${file}: unausgeglichenes ${char}`);
    }
    index += 1;
  }
  if (delimiters.length) failures.push(`${file}: offene Klammern ${delimiters.join("")}`);
  return words;
}

for (const file of files) {
  const source = fs.readFileSync(path.join(addonRoot, file), "utf8");
  const blocks = [];
  for (const word of tokens(source, file)) {
    if (word === "function" || word === "if" || word === "do" || word === "repeat") {
      blocks.push(word);
    } else if (word === "end") {
      const open = blocks.pop();
      if (!open || open === "repeat") failures.push(`${file}: unerwartetes end`);
    } else if (word === "until") {
      const open = blocks.pop();
      if (open !== "repeat") failures.push(`${file}: unerwartetes until`);
    }
  }
  if (blocks.length) failures.push(`${file}: offene Blöcke ${blocks.join(", ")}`);
}

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`Lua balance audit passed: ${files.length} Dateien.`);
