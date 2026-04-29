const fs = require("fs");
let code = fs.readFileSync("d:/FYP/project/frontend/lib/screens/history.dart", "utf8");

// Rewrite the cards to GlassCard
code = code.replace(/Card\(\n\s*elevation:[^]+?child: Padding\(/g, "GlassCard(\n      padding: const EdgeInsets.all(0),\n      child: Padding(");
code = code.replace(/Card\(\n\s*elevation: 0,\n\s*shape: RoundedRectangleBorder\([^)]+\),\n\s*color: .+,/g, "GlassCard(\n      padding: const EdgeInsets.all(0),");

// Just blanket replace colorScheme uses
code = code.replace(/colorScheme/g, "theme.colorScheme");
code = code.replace(/theme\.theme\.colorScheme/g, "theme.colorScheme");

fs.writeFileSync("d:/FYP/project/frontend/lib/screens/history.dart", code);
console.log("history.dart UI replaced done");
