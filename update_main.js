const fs = require('fs');

// 1) Read main.dart
let mainCode = fs.readFileSync('d:/FYP/project/frontend/lib/main.dart', 'utf8');

// Update FYPApp build method
let oldBuild = `  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, storage, child) {
        return MaterialApp(
          title: 'FYP ML Pipeline',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const MainApp(),
        );
      },
    );
  }`;

let newBuild = `  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, storage, child) {
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        AppTheme.isLightMode = storage.themeMode == ThemeMode.light || (storage.themeMode == ThemeMode.system && platformBrightness == Brightness.light);

        return MaterialApp(
          title: 'FYP ML Pipeline',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: storage.themeMode,
          home: const MainApp(),
        );
      },
    );
  }`;

mainCode = mainCode.replace(oldBuild, newBuild);
fs.writeFileSync('d:/FYP/project/frontend/lib/main.dart', mainCode);
console.log('main.dart updated');
