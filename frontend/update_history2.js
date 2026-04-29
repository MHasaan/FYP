const fs = require("fs");
let code = fs.readFileSync("d:/FYP/project/frontend/lib/screens/history.dart", "utf8");

// Add imports
if (!code.includes("app_theme.dart")) {
  code = code.replace(
    "import '../services/api_service.dart';",
    "import '../services/api_service.dart';\nimport '../theme/app_theme.dart';\nimport '../widgets/glass_card.dart';"
  );
}

// Replace Scaffold
code = code.replace(
  `  Widget build(BuildContext context) {\n    final colorScheme = Theme.of(context).colorScheme;\n    final child = _selectedView == 0\n        ? _buildSessionsView(context, colorScheme)\n        : _buildRecordingsView(context, colorScheme);\n\n    return Scaffold(\n      body: _isLoading\n          ? const Center(child: CircularProgressIndicator())\n          : RefreshIndicator(\n              onRefresh: _fetchSessions,\n              child: child,\n            ),\n    );\n  }`,
  `  Widget build(BuildContext context) {\n    final theme = Theme.of(context);\n    final child = _selectedView == 0\n        ? _buildSessionsView(context, theme)\n        : _buildRecordingsView(context, theme);\n\n    return Scaffold(\n      backgroundColor: AppTheme.background,\n      body: _isLoading\n          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))\n          : RefreshIndicator(\n              color: AppTheme.primary,\n              backgroundColor: AppTheme.surfaceHighlight,\n              onRefresh: _fetchSessions,\n              child: child,\n            ),\n    );\n  }`
);

code = code.replace("Widget _buildSessionsView(BuildContext context, ColorScheme colorScheme) {", "Widget _buildSessionsView(BuildContext context, ThemeData theme) {");
code = code.replace("Widget _buildRecordingsView(BuildContext context, ColorScheme colorScheme) {", "Widget _buildRecordingsView(BuildContext context, ThemeData theme) {");

fs.writeFileSync("d:/FYP/project/frontend/lib/screens/history.dart", code);
console.log("history.dart basic replace done");
