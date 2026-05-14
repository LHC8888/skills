// <tmp-runtime>/auth-check.spec.ts
// Verifies that the local auth profile is still logged in.

import { chromium, expect, test } from '@playwright/test';
import { authConfig, isLoginPage } from './auth.config';

test.describe.configure({ mode: 'serial' });

test('auth profile is logged in', async () => {
  const context = await chromium.launchPersistentContext(authConfig.sourceProfileDir, {
    channel: 'chrome',
    headless: true,
    viewport: { width: 1440, height: 900 },
  });

  try {
    const page = context.pages()[0] || await context.newPage();

    for (const url of authConfig.checkUrls) {
      await page.goto(url, { waitUntil: 'domcontentloaded' });

      const bodyText = await page.locator('body').innerText();

      if (isLoginPage(page.url(), bodyText)) {
        throw new Error(
          `Auth profile is not logged in for ${url}. Run auth-login.ts to refresh ${authConfig.sourceProfileDir}.`,
        );
      }

      await expect(page).toHaveURL(/.+/);
      expect(authConfig.loggedInSignals.some(signal => signal.test(bodyText))).toBe(true);
    }
  }
  finally {
    await context.close();
  }
});
