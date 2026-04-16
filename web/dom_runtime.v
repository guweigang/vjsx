module web

import vjsx { Context }

// Add generic DOM/browser runtime compatibility helpers to globals.
// This augments environments that already expose `DOMParser` with a
// minimal browser-like host (`document`, `window`, `getComputedStyle`,
// `document.implementation.createHTMLDocument`, and safer selector handling).
pub fn dom_runtime_api(ctx &Context) {
	ctx.eval_runtime_file('web/js/dom_runtime.js', vjsx.type_module) or { panic(err) }
}
