const fs = require("fs");

function removeConst(filePath, regexes) {
  let content = fs.readFileSync(filePath, "utf8");
  for (const r of regexes) {
    content = content.replace(r, (match, prefix, suffix) => prefix + suffix);
  }
  fs.writeFileSync(filePath, content);
  console.log("Fixed const refs in " + filePath);
}

// dashboard.dart
removeConst("d:/FYP/project/frontend/lib/screens/dashboard.dart", [
  /(const )(Icon[^;]+?AppTheme\.primary[A-Za-z0-9_()., ]*\))/g,
  /(const )(TextStyle[^;]+?color:[ ]*AppTheme\.[A-Za-z0-9_()., ]*\))/g,
]);

// history.dart
removeConst("d:/FYP/project/frontend/lib/screens/history.dart", [
  /(const )(Center\([^;]+?CircularProgressIndicator[^;]+?AppTheme\.primary[A-Za-z0-9_()., ]*\)))\)/g,
]);

// multi_camera_grid.dart
removeConst("d:/FYP/project/frontend/lib/screens/multi_camera_grid.dart", [
  /(const )(Icon[^;]+?AppTheme\.primary[A-Za-z0-9_()., ]*\))/g,
]);

// settings.dart
removeConst("d:/FYP/project/frontend/lib/screens/settings.dart", [
  /(const )(Icon[^;]+?AppTheme\.primary[A-Za-z0-9_()., ]*\))/g,
]);

// live_feed.dart
removeConst("d:/FYP/project/frontend/lib/screens/live_feed.dart", [
  /(const )(Icon[^;]+?AppTheme\.primary[A-Za-z0-9_()., ]*\))/g,
  /(const )(TextStyle[^;]+?color:[ ]*AppTheme\.[A-Za-z0-9_()., ]*\))/g,
]);

