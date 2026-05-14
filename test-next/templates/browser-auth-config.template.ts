// <tmp-runtime>/auth.config.ts
// Copy into the target project and replace login/check signals with project evidence.

import os from 'node:os';
import path from 'node:path';

const projectSlug = '<project-slug>';

export const authConfig = {
  // 专用 automation profile，由 headed auth-login.ts 初始化。
  // 不要从日常 Chrome 主 profile 复制。
  sourceProfileDir:
    process.env.TEST_NEXT_SOURCE_PROFILE_DIR ||
    process.env.TEST_NEXT_PROFILE_DIR ||
    path.join(os.homedir(), '.test-next-profile', projectSlug, 'auth-source'),

  loginUrl: '<login-url>',

  checkUrls: [
    '<logged-in-page-url>',
  ],

  loggedInSignals: [
    /<logged-in-text-or-title>/i,
  ],

  loginPageSignals: [
    /login|sign in|signin|登录|账号|密码|验证码/i,
  ],
};

export function isLoginPage(url: string, bodyText: string) {
  return (
    /login|signin|passport|auth/i.test(url) ||
    authConfig.loginPageSignals.some(signal => signal.test(bodyText))
  );
}
