
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
    
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 375, height: 812 }, colorScheme: 'dark' });
const page = await context.newPage();
await page.addInitScript(() => {
  window.Telegram = { WebApp: { ready:()=>{},expand:()=>{},close:()=>{},initData:'',initDataUnsafe:{user:{id:123,first_name:'Test'}},colorScheme:'dark',themeParams:{},BackButton:{show:()=>{},hide:()=>{},onClick:()=>{},offClick:()=>{}},MainButton:{show:()=>{},hide:()=>{},onClick:()=>{},offClick:()=>{},setText:()=>{}},HapticFeedback:{impactOccurred:()=>{},selectionChanged:()=>{},notificationOccurred:()=>{}},platform:'tdesktop',version:'7.0',isExpanded:true,viewportHeight:812,viewportStableHeight:812}};
});
await page.goto('http://localhost:5173/app/car/new', { waitUntil: 'networkidle', timeout: 15000 });
await page.addStyleTag({ content: ':root,*{--tg-theme-bg-color:#1c1c1e!important;--tg-theme-text-color:#fff!important;--tg-theme-hint-color:#98989e!important;--tg-theme-link-color:#007aff!important;--tg-theme-button-color:#007aff!important;--tg-theme-button-text-color:#fff!important;--tg-theme-secondary-bg-color:#2c2c2e!important;--tg-theme-header-bg-color:#1c1c1e!important;--tg-theme-section-bg-color:#2c2c2e!important} html,body{background-color:#1c1c1e!important}' });
await page.waitForTimeout(500);
await page.screenshot({ path: 'd:/Data/Documents/Programming/Projects/Telegram/ai_sky_net_bot/webapp/tmp_step0.png' });

// Click Далее to go to step 1
await page.click('button:has-text("Далее")');
await page.waitForTimeout(500);
await page.screenshot({ path: 'd:/Data/Documents/Programming/Projects/Telegram/ai_sky_net_bot/webapp/tmp_step1.png' });
console.log('done');
await browser.close();

  } catch (error) {
    console.error('❌ Automation error:', error.message);
    if (error.stack) {
      console.error(error.stack);
    }
    process.exit(1);
  }
})();
