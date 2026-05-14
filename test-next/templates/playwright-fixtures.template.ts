// <tmp-runtime>/fixtures.ts
// 默认由 skill 写入系统临时目录；不要复制到项目目录。
//
// 默认路径：
//   SOURCE_PROFILE: 用户通过 headed auth-login.ts 登录生成的专用 automation profile
//   默认 workers=1，直接使用 SOURCE_PROFILE。
//   并发/CI 时设置 TEST_NEXT_COPY_PROFILE_PER_WORKER=true，再为每个 worker hot-copy 独立临时 profile。
//
// 不要把日常 Chrome 主 profile 当 SOURCE_PROFILE。

import { chromium, expect, test as base } from '@playwright/test';
import type { Browser, BrowserContext, Page } from '@playwright/test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

type WorkerFixtures = {
  workerContext: BrowserContext;
};

type TestFixtures = {
  page: Page;
};

const projectSlug = process.env.TEST_NEXT_PROJECT_SLUG || '<project-slug>';

const sourceProfileDir =
  process.env.TEST_NEXT_SOURCE_PROFILE_DIR ||
  process.env.TEST_NEXT_PROFILE_DIR ||
  path.join(os.homedir(), '.test-next-profile', projectSlug, 'auth-source');

const testProfileBaseDir =
  process.env.TEST_NEXT_PROFILE_BASE_DIR ||
  path.join(os.tmpdir(), 'test-next-profile', projectSlug);

const ignoredProfileParts = new Set([
  'Cache',
  'Code Cache',
  'CacheStorage',
  'Crashpad',
  'GPUCache',
  'GrShaderCache',
  'ShaderCache',
  'SingletonCookie',
  'SingletonLock',
  'SingletonSocket',
]);

async function copyProfile(source: string, target: string) {
  await fs.rm(target, { recursive: true, force: true });
  await fs.mkdir(path.dirname(target), { recursive: true });
  await fs.cp(source, target, {
    recursive: true,
    force: true,
    filter: sourcePath => {
      const parts = sourcePath.split(path.sep);
      return !parts.some(part => ignoredProfileParts.has(part));
    },
  });
}

async function ensureSourceProfileReady() {
  if (process.env.TEST_NEXT_REQUIRE_AUTH_PROFILE !== 'true') {
    return;
  }

  try {
    await fs.access(sourceProfileDir);
  }
  catch {
    throw new Error(
      [
        `Missing auth source profile: ${sourceProfileDir}`,
        'Run auth-login.ts first, or set TEST_NEXT_SOURCE_PROFILE_DIR.',
      ].join('\n'),
    );
  }
}

export const test = base.extend<TestFixtures, WorkerFixtures>({
  workerContext: [
    async ({}, use, workerInfo) => {
      let externalBrowser: Browser | undefined;
      let context: BrowserContext;

      if (process.env.PLAYWRIGHT_CDP_URL) {
        externalBrowser = await chromium.connectOverCDP(process.env.PLAYWRIGHT_CDP_URL);
        context = externalBrowser.contexts()[0] || await externalBrowser.newContext();
      }
      else if (process.env.TEST_NEXT_COPY_PROFILE_PER_WORKER === 'true') {
        await ensureSourceProfileReady();
        const workerProfileDir = path.join(testProfileBaseDir, `worker-${workerInfo.parallelIndex}`);
        await copyProfile(sourceProfileDir, workerProfileDir);

        context = await chromium.launchPersistentContext(workerProfileDir, {
          headless: process.env.PLAYWRIGHT_HEADLESS !== 'false',
          baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:3000',
          viewport: { width: 1440, height: 900 },
          args: ['--remote-allow-origins=*'],
        });
      }
      else {
        await ensureSourceProfileReady();
        context = await chromium.launchPersistentContext(sourceProfileDir, {
          headless: process.env.PLAYWRIGHT_HEADLESS !== 'false',
          baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:3000',
          viewport: { width: 1440, height: 900 },
          args: ['--remote-allow-origins=*'],
        });
      }

      await use(context);

      if (externalBrowser) {
        await externalBrowser.close();
      }
      else {
        await context.close();
      }
    },
    { scope: 'worker' },
  ],

  page: async ({ workerContext }, use) => {
    const page = await workerContext.newPage();
    await use(page);
    await page.close();
  },
});

export { expect };
