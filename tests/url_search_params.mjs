let checks = 0;
function equal(actual, expected) {
  checks++;
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw Error(`check ${checks}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
const url = new URL('https://example.com/path?z=last&a=hello%20world&z=again#keep');
const params = url.searchParams;
equal(params === url.searchParams, true);
equal(params.get('a'), 'hello world');
equal([...params], [['z', 'last'], ['a', 'hello world'], ['z', 'again']]);
params.append('receive_id_type', 'open_id');
equal(url.href, 'https://example.com/path?z=last&a=hello+world&z=again&receive_id_type=open_id#keep');
equal(url.search, '?z=last&a=hello+world&z=again&receive_id_type=open_id');
params.set('z', 'first');
equal([...params], [['z', 'first'], ['a', 'hello world'], ['receive_id_type', 'open_id']]);
params.sort();
equal(url.href, 'https://example.com/path?a=hello+world&receive_id_type=open_id&z=first#keep');
params.delete('receive_id_type');
equal(url.toJSON(), 'https://example.com/path?a=hello+world&z=first#keep');
url.search = 'x=one%20two&x=three#text';
equal(url.searchParams === params, true);
equal(params.getAll('x'), ['one two', 'three#text']);
equal(url.href, 'https://example.com/path?x=one%20two&x=three%23text#keep');
params.delete('x', 'one two');
equal(url.search, '?x=three%23text');
url.href = 'https://other.com/new?b=two%20words#next';
equal(url.searchParams === params, true);
equal([...params], [['b', 'two words']]);
equal(url.pathname, '/new');
params.append('c', '中文 +&=');
equal(url.href, 'https://other.com/new?b=two+words&c=%E4%B8%AD%E6%96%87+%2B%26%3D#next');
url.search = '';
equal(params.size, 0);
equal(url.href, 'https://other.com/new#next');
params.sort();
equal(url.search, '');
url.search = '?';
equal(url.href, 'https://other.com/new?#next');
params.delete('absent');
equal(url.href, 'https://other.com/new#next');
url.href = 'https://third.com/empty#?not-a-query';
equal(params.size, 0);
params.append('k', 'v');
equal(String(url), 'https://third.com/empty?k=v#?not-a-query');
const copy = new URLSearchParams(params);
copy.set('k', 'detached');
equal(params.get('k'), 'v');
equal(new URLSearchParams().toString(), '');
equal(new URLSearchParams([['2', 'x'], ['1', 'y'], ['2', 'z']]).toString(), '2=x&1=y&2=z');
const iterator = params.entries();
params.append('next', 'live');
equal([...iterator], [['k', 'v'], ['next', 'live']]);
const visited = [];
params.forEach((value, key, owner) => {
  visited.push([key, value, owner === params]);
  if (key === 'k') owner.delete('next');
});
equal(visited, [['k', 'v', true]]);
equal(new URLSearchParams('zero=%00').toString(), 'zero=%00');
for (const [encoded, decoded] of [
  ['%', '%'], ['%GG', '%GG'], ['%FF', '\uFFFD'],
  ['%E2%82', '\uFFFD'], ['%E0%80%80', '\uFFFD\uFFFD\uFFFD'],
  ['%F0%9F%98%80', '😀'], ['a+b', 'a b'],
]) {
  url.search = `bad=${encoded}`;
  equal(params.get('bad'), decoded);
  params.append('ok', 'yes');
  equal(new URL(url.href).searchParams.get('bad'), decoded);
}
const before = url.href;
let rejected = false;
try { url.href = 'invalid absolute URL'; } catch { rejected = true; }
equal(rejected, true);
equal(url.href, before);
equal(params === url.searchParams, true);
const stable = new URLSearchParams('b=2&a=1&a=3');
stable.sort();
equal(stable.toString(), 'a=1&a=3&b=2');
equal(new URLSearchParams({__proto__: null, k: null}).get('k'), 'null');
console.log(`URL_SYNC_PASS ${checks}`);
