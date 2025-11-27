# Quick Start: FLEX Dylib Injection

## What Was Changed

FLEX has been modified to support injection as a dynamic library (dylib) for debugging apps on non-jailbroken iOS devices.

### Key Files Added/Modified

1. **`Classes/FLEXDylibEntry.m`** - Entry point that auto-initializes FLEX when the dylib is loaded
2. **`DYLIB_INJECTION.md`** - Comprehensive guide for building and injecting
3. **`build_dylib.sh`** - Helper script with build instructions
4. **`entitlements.plist`** - Code signing entitlements template

## Quick Build Steps

### Automated Build (Recommended)

Simply run the build script:

```bash
./build_dylib.sh
```

This will:
- Automatically find all source files
- Compile them using clang
- Link into a dylib
- Code sign (if certificate is available)
- Output: `Build/FLEX.dylib`

**For iOS Simulator:**
```bash
./build_dylib.sh simulator
```

**For iOS Device (arm64):**
```bash
./build_dylib.sh arm64
```

### Manual Xcode Build (Alternative)

If you prefer using Xcode:

1. **Open Xcode project:**
   ```bash
   open FLEX.xcodeproj
   ```

2. **Create Framework target:**
   - File > New > Target > Framework
   - Name: `FLEXDylib`

3. **Configure target:**
   - Mach-O Type: `Dynamic Library`
   - Installation Directory: `@rpath`
   - Add all files from `Classes/` folder

4. **Build:**
   ```bash
   xcodebuild -project FLEX.xcodeproj \
              -target FLEXDylib \
              -configuration Release \
              -arch arm64 \
              -sdk iphoneos \
              CODE_SIGN_IDENTITY="Apple Development" \
              DEVELOPMENT_TEAM="YOUR_TEAM_ID"
   ```

### Inject with Frida

```bash
frida -U -f com.example.app -l Build/FLEX.dylib
```

## How It Works

When the dylib is injected:
- The `__attribute__((constructor))` function runs automatically
- FLEX initializes on the main thread
- After 0.5 seconds, the FLEX explorer UI appears automatically
- No manual code changes needed in the target app

## Requirements

- ✅ iOS device with Developer Mode enabled (iOS 16+)
- ✅ Apple Developer account
- ✅ Frida or similar injection tool
- ✅ Proper code signing

## Notes

- The Substrate dependency in SystemLog is optional and won't break on non-jailbroken devices
- All FLEX features work except some advanced system log hooks that require Substrate
- The dylib must be properly code signed to work on non-jailbroken devices

## Troubleshooting

**FLEX doesn't appear:**
- Check device logs: `idevicesyslog | grep FLEX`
- Verify dylib was injected successfully
- Ensure app has proper entitlements

**Build errors:**
- Make sure all source files are added to the FLEXDylib target
- Verify FLEXDylibEntry.m is included
- Check code signing settings

For detailed information, see `DYLIB_INJECTION.md`.

