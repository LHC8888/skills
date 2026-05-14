// playwright.config.ts —— skill 推荐默认配置
// persist-spec 模式下必须写入项目根；report-only 模式写入系统临时目录。

import { defineConfig } from '@playwright/test';
import os from 'node:os';
import path from 'node:path';

const projectSlug = process.env.TEST_NEXT_PROJECT_SLUG || '<project-slug>';
const artifactRoot = process.env.TEST_NEXT_ARTIFACT_ROOT || path.join(os.tmpdir(), 'test-next', projectSlug);
const outputDir = process.env.TEST_NEXT_OUTPUT_DIR || path.join(artifactRoot, 'test-results');
const htmlReportDir = process.env.TEST_NEXT_HTML_REPORT_DIR || path.join(artifactRoot, 'playwright-report');

export default defineConfig({
  // 必需：找同目录 spec 文件（默认只找 tests/）
  testMatch: '**/*.spec.ts',

  // 大 SSR / 慢 dev server 项目的保守默认；CI 或冷启动更慢时可上调到 90s。
  timeout: 60_000,
  expect: { timeout: 30_000 },

  // 默认串行使用专用 automation profile，避免 persistent profile 并发锁冲突。
  // 需要 CI 并发时再显式开启 workers > 1，并设置 TEST_NEXT_COPY_PROFILE_PER_WORKER=true。
  workers: 1,
  fullyParallel: false,
  outputDir,
  reporter: [
    ['list'],
    ['html', { outputFolder: htmlReportDir, open: 'never' }],
  ],

  use: {
    // 默认 headless（探索时用 CLI --headed 临时覆盖）
    headless: true,

    // 失败保 trace 便于诊断
    trace: 'retain-on-failure',
  },
});
