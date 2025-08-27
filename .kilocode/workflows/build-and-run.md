# Build and Run Workflow

This workflow automates the setup, development, and build process for the scraper UI.

## Steps

1. **Install Dependencies**
   ```bash
   pnpm i
   ```
   - Verifies successful installation by checking `node_modules` directory
   - Reports any missing dependencies or version conflicts

2. **Start Development Server**
   ```bash
   pnpm dev --port 5173
   ```
   - Confirms server is running at `http://localhost:5173`
   - Validates environment variables (especially VITE_API_URL)
   - Checks for compiler warnings/errors in real-time logs

3. **Production Build**
   ```bash
   pnpm build
   ```
   - Verifies successful asset generation in `dist/` directory
   - Checks bundle size and optimization metrics
   - Validates source map generation

4. **Log Analysis & Next Steps**
   - [ ] Confirm all steps completed without errors
   - [ ] Check console for warnings (TypeScript, accessibility)
   - [ ] Verify network requests to API endpoints
   - Next Actions:
     - Open browser to http://localhost:5173
     - Run accessibility audit with Lighthouse
     - Test form submissions with invalid inputs

## Trigger Instructions
Run this workflow by typing `/build-and-run.md` in chat. The system will execute all steps sequentially and report outcomes.