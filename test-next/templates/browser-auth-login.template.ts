// <tmp-runtime>/auth-login.ts
// Run headed when the local auth profile needs first-time login or refresh.

import { chromium } from 'playwright';
import { authConfig } from './auth.config';

const context = await chromium.launchPersistentContext(authConfig.sourceProfileDir, {
  channel: 'chrome',
  headless: false,
  viewport: { width: 1440, height: 900 },
});

const page = context.pages()[0] || await context.newPage();

await page.goto(authConfig.loginUrl, { waitUntil: 'domcontentloaded' });

console.log(`Login URL: ${authConfig.loginUrl}`);
console.log(`Profile: ${authConfig.sourceProfileDir}`);
console.log('Finish login in the opened browser, then close the browser window or press Ctrl+C.');

await page.pause();
