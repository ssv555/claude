
const { chromium, firefox, webkit, devices } = require('playwright');
const helpers = require('./lib/helpers');

// Extra headers from environment variables (if configured)
const __extraHeaders = helpers.getExtraHeadersFromEnv();

/**
 * Utility to merge environment headers into context options.
 * Use when creating contexts with raw Playwright API instead of helpers.createContext().
 * @param {Object} options - Context options
 * @returns {Object} Options with extraHTTPHeaders merged in
 */
function getContextOptionsWithHeaders(options = {}) {
  if (!__extraHeaders) return options;
  return {
    ...options,
    extraHTTPHeaders: {
      ...__extraHeaders,
      ...(options.extraHTTPHeaders || {})
    }
  };
}

(async () => {
  try {
    
const browser = await chromium.launch({ headless: false, slowMo: 200 });
const page = await browser.newPage();
await page.goto('https://chatgpt.com/s/t_69db2bf2bcd08191bf06b577f4f82543', { waitUntil: 'networkidle', timeout: 30000 });
await page.waitForTimeout(5000);
const text = await page.innerText('body');
console.log('=== PAGE TEXT START ===');
console.log(text);
console.log('=== PAGE TEXT END ===');
await browser.close();

  } catch (error) {
    console.error('❌ Automation error:', error.message);
    if (error.stack) {
      console.error(error.stack);
    }
    process.exit(1);
  }
})();
