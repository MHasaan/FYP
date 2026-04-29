const fs = require('fs');

let history = fs.readFileSync('d:/FYP/project/frontend/lib/screens/history.dart', 'utf8');
history = history.replace(/widget\.Theme\.of\(context\)\.colorScheme/g, 'Theme.of(context).colorScheme');
fs.writeFileSync('d:/FYP/project/frontend/lib/screens/history.dart', history);


let multi = fs.readFileSync('d:/FYP/project/frontend/lib/screens/multi_camera_grid.dart', 'utf8');
// Fix all const Text with AppTheme.textPrimary
multi = multi.replace(/const Text\([\s\S]*?color: AppTheme\.textPrimary,/g, (match) => {
    return match.replace(/const Text\(/g, "Text(");
});
fs.writeFileSync('d:/FYP/project/frontend/lib/screens/multi_camera_grid.dart', multi);
