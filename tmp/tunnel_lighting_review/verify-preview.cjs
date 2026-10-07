const { chromium } = require('C:/Users/akadi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 760, height: 800 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('file:///P:/Deepdraft/tmp/tunnel_lighting_review/preview.html');
  const frame = page.frameLocator('iframe');
  await frame.locator('#tunnel-lighting-study img').first().waitFor();
  for (const variant of ['Current lighting', 'Unlit tunnel', 'With torches']) {
    await frame.locator(`[data-variant="${variant}"]`).waitFor({state:'visible'});
    if (await frame.locator('[data-variant]:visible').count() !== 1) throw Error('Multiple variants visible');
    console.log({variant, loaded:await frame.locator(`[data-variant="${variant}"] img`).evaluate(i => i.complete && i.naturalWidth === 1400)});
    if (variant !== 'With torches') await frame.getByRole('button', {name:'Next variant', exact:true}).click();
  }
  await page.screenshot({path:'P:/Deepdraft/tmp/tunnel_lighting_review/preview-check.png', fullPage:true});
  await page.setViewportSize({width:352,height:600});
  const overflow = await frame.locator('body').evaluate(e => e.scrollWidth > e.clientWidth);
  if (overflow || errors.length) throw Error(JSON.stringify({overflow,errors}));
  console.log({errors});
  await browser.close();
})().catch(error => { console.error(error); process.exitCode = 1; });
