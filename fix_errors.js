const fs = require('fs');

// 1. Fix history.dart
let history = fs.readFileSync('d:/FYP/project/frontend/lib/screens/history.dart', 'utf8');
history = history.replace(/final ColorScheme theme\.colorScheme;/g, 'final ColorScheme colorScheme;');
history = history.replace(/required this\.theme\.colorScheme,/g, 'required this.colorScheme,');
history = history.replace(/theme\.colorScheme: theme\.colorScheme,/g, 'colorScheme: colorScheme,');
history = history.replace(/widget\.theme\.colorScheme/g, 'widget.colorScheme');
history = history.replace(/theme\.colorScheme\.onSurface/g, 'colorScheme.onSurface');
fs.writeFileSync('d:/FYP/project/frontend/lib/screens/history.dart', history);

// 2. Fix dashboard.dart
let dashboard = fs.readFileSync('d:/FYP/project/frontend/lib/screens/dashboard.dart', 'utf8');
dashboard = dashboard.replace(/Icon\(\$1, color: AppTheme\.primary\)/g, 'Icon(Icons.auto_awesome, color: AppTheme.primary)');
dashboard = dashboard.replace(/const LinearProgressIndicator\(/g, 'LinearProgressIndicator(');
fs.writeFileSync('d:/FYP/project/frontend/lib/screens/dashboard.dart', dashboard);

// 3. Fix settings.dart
let settings = fs.readFileSync('d:/FYP/project/frontend/lib/screens/settings.dart', 'utf8');
settings = settings.replace(/Icon\(\$1, color: AppTheme\.primary/g, 'Icon(Icons.palette_rounded, color: AppTheme.primary');
fs.writeFileSync('d:/FYP/project/frontend/lib/screens/settings.dart', settings);

// 4. Fix multi_camera_grid.dart
let multi = fs.readFileSync('d:/FYP/project/frontend/lib/screens/multi_camera_grid.dart', 'utf8');
multi = multi.replace(/Icon\(\$1, color: AppTheme\.primary/g, 'Icon(Icons.grid_view_rounded, color: AppTheme.primary');
multi = multi.replace(/style: const TextStyle\(/g, 'style: TextStyle(');
multi = multi.replace(/const Text\(\n\s*'Layout',/g, "Text(\n            'Layout',");
fs.writeFileSync('d:/FYP/project/frontend/lib/screens/multi_camera_grid.dart', multi);

console.log('Fixes applied successfully!');
