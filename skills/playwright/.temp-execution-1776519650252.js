
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: false, slowMo: 50 });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    await page.goto('https://chatgpt.com/s/t_69e335ddfcfc819182d7212cacca9adc', {
      waitUntil: 'networkidle',
      timeout: 30000,
    });

    // Wait for content to load
    await page.waitForTimeout(5000);

    // Try to get all text content
    const content = await page.evaluate(() => {
      // Remove script and style elements
      const scripts = document.querySelectorAll('script, style, noscript');
      scripts.forEach(el => el.remove());
      
      // Get all text
      return document.body.innerText;
    });

    console.log('=== PAGE CONTENT START ===');
    console.log(content);
    console.log('=== PAGE CONTENT END ===');

  } catch (error) {
    console.error('Error:', error.message);
    // Take screenshot for debugging
    await page.screenshot({ path: '/tmp/chatgpt-debug.png', fullPage: true });
    console.log('Screenshot saved to /tmp/chatgpt-debug.png');
  } finally {
    await browser.close();
  }
})();
