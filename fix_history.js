const fs = require('fs');

// Fix history.dart where we over-replaced colorScheme back to theme.colorScheme (except widget.colorScheme and colorScheme: colorScheme)
let history = fs.readFileSync('d:/FYP/project/frontend/lib/screens/history.dart', 'utf8');

// The build method starts with `final theme = Theme.of(context);` inside _HistoryScreenState.
// We'll just replace `colorScheme.` with `theme.colorScheme.` globally, and then fix the few places it's wrong, 
// OR just replace specific line locations since there are only 10.
history = history.replace(/= colorScheme/g, '= theme.colorScheme');
history = history.replace(/\(colorScheme/g, '(theme.colorScheme');
history = history.replace(/ colorScheme\./g, ' theme.colorScheme.');
history = history.replace(/colorScheme: theme\.colorScheme/g, 'theme.colorScheme: theme.colorScheme'); // fix back wait...
history = history.replace(/final ColorScheme theme\.colorScheme/g, 'final ColorScheme colorScheme'); // leave constructor arg fixed

// Clean up
history = history.replace(/theme\.theme\.colorScheme/g, 'theme.colorScheme');
history = history.replace(/widget\.theme\.colorScheme/g, 'widget.colorScheme');
history = history.replace(/colorScheme: colorScheme/g, 'colorScheme: theme.colorScheme');
history = history.replace(/final ColorScheme colorScheme/g, 'final ColorScheme colorScheme');

fs.writeFileSync('d:/FYP/project/frontend/lib/screens/history.dart', history);


// Fix multi_camera_grid.dart line 2171ish text primary
let multi = fs.readFileSync('d:/FYP/project/frontend/lib/screens/multi_camera_grid.dart', 'utf8');
multi = multi.replace(/const Text\([\s\S]*?'Layout',[\s\S]*?color: AppTheme\.textPrimary[\s\S]*?\)/, `Text(
            'Layout',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          )`);
fs.writeFileSync('d:/FYP/project/frontend/lib/screens/multi_camera_grid.dart', multi);

