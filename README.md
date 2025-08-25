# Web Scraper & Repo Analyzer (Flutter)

This is a cross‑platform Flutter app that:
- Crawls documentation websites (with robots.txt + sitemap respect)
- Pulls content from public GitHub repos (optionally docs‑only)
- Chunks content for RAG (JSONL) and also produces human‑readable Markdown/HTML
- Exports a ZIP you can download from the app

## What’s included
- **UI**: `lib/screens/scraper_dashboard.dart` + `lib/widgets/*`
- **Models**: `lib/models/*` (job config, RAG entries, chunking)
- **Scrapers**: `lib/services/website_scraper.dart`, `lib/services/github_scraper.dart`
- **Exports**: `lib/services/export_service.dart` (now saves a ZIP via FileSaver)
- **Themes**: `lib/theme.dart`
- **Samples**: `lib/samples/sample_data.dart`

## Build requirements
- Flutter SDK **3.16+** (Dart 3); run `flutter --version` to confirm.
- For **Android**: Android Studio + SDK, an emulator or a device with USB debugging.
- For **iOS** (on macOS): Xcode + CocoaPods, a simulator or device with proper signing.
- For **Web/Desktop**: Chrome (web) and optional desktop targets (`flutter config --enable-windows-desktop` / `--enable-macos-desktop`).

### Dependencies
Key pub packages used:
- `http`, `html`, `archive`, `uuid`, `crypto`, `path`
- `file_saver` (for cross‑platform download of the export ZIP)

## Quick start (Windsurf on Windows 11)
1. **Open the project**  
   Windsurf → *File → Open Folder…* → select this repo root.

2. **Install Flutter & Android tooling (once)**  
   - Install Flutter from: https://docs.flutter.dev/get-started/install/windows  
   - Add Flutter to PATH. Close/reopen Windsurf after install so the PATH refreshes.
   - Install Android Studio. Open **SDK Manager** → install latest SDK + platform tools.
   - In a Windsurf terminal (PowerShell):
     ```powershell
     flutter doctor
     ```
     Fix anything marked with ✗.

3. **Fetch deps**
   ```powershell
   flutter pub get
   ```

4. **Smoke test in Chrome (fastest path)**
   ```powershell
   flutter run -d chrome
   ```
   You should see the dashboard. Enter a URL (or use a sample), click **Validate**, then **Run**, then **Download** to save the ZIP.

5. **Run on Android (optional)**
   ```powershell
   flutter emulators
   flutter emulators --launch <emulator_id>
   flutter devices
   flutter run -d <device_id>
   ```

6. **Enable Windows desktop (optional)**
   ```powershell
   flutter config --enable-windows-desktop
   flutter doctor
   flutter run -d windows
   ```

## Using the app
1. **Source**: choose **Website** or **GitHub**.  
   - Website: set base path (optional), max depth, and allowed domains.  
   - GitHub: paste repo URLs (e.g., `https://github.com/flutter/flutter`), choose scope (**docs‑only** or **full repo**).
2. **Output**: pick **RAG JSONL**, **Readable Markdown**, **Readable HTML**, or **Both**.  
   - Adjust chunk size/overlap if exporting RAG JSONL.
3. **Crawler Controls**: max pages, concurrency, delay, follow sitemaps, custom User‑Agent.
4. Click **Validate** → review estimated pages/robots/sitemap/any issues.  
5. Click **Run** → progress appears in the banner and logs on the right.  
6. When status is **Completed**, click **Download** (saves a ZIP via FileSaver).

### Export contents
- `rag_export.jsonl` — one JSON object per line with `id`, `sourceUrl`, `title`, `headings`, `content`, and chunk metadata.
- `markdown/…` — readable `.md` files.
- `html/…` — readable `.html` files (light styling).

## Troubleshooting
- **`flutter: command not found`** — PATH not updated; reopen Windsurf or add Flutter bin to PATH.
- **Android cannot run** — accept Android SDK licenses:
  ```powershell
  flutter doctor --android-licenses
  ```
- **Web download didn’t prompt** — some browsers block multiple downloads; check the downloads panel. The app uses `file_saver` to trigger a `.zip` save.
- **Validation says robots disallow** — the app respects robots.txt; adjust your targets or crawl depth.

## Project scripts (handy)
- Fetch deps: `flutter pub get`
- Analyze: `flutter analyze`
- Format: `dart format .`
- Test (if any): `flutter test`

---

### Internals (for code readers)
- Website fetching uses `http` + `package:html` with a polite rate‑limit and sitemap discovery.
- GitHub fetching uses the public API to enumerate files and extracts docs‑like paths for **docs‑only** scope.
- RAG chunking is simple size/overlap token‑agnostic splitting suitable for most embedding workflows; tune sizes in UI.
- Exports are staged in memory and zipped; `FileSaver` handles cross‑platform save in `downloadResults()`.

