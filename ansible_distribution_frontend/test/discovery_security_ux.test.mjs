import assert from 'node:assert/strict';
import {parseRoute, routeToHash, createPageController} from '../src/page_routes.mjs';
import {buildAppViewModel, PAGE_IDS} from '../src/state_model.mjs';
import {renderPageBody, safeApprovalLink} from '../src/forum_page_renderers.mjs';
import {searchPublicContent} from '../src/appview_client.mjs';
import {setCurrentLocale} from '../src/web_i18n.mjs';
setCurrentLocale('zh-Hant');
const query = '隱私 & <script>alert(1)</script>';
assert.equal(parseRoute(routeToHash({pageId:PAGE_IDS.discover,params:{query}})).params.query, query);
let requested;
const result=await searchPublicContent({appViewBaseUrl:'https://appview.example',query,fetchImpl:async(url)=>{requested=url;return {ok:true,status:200,json:async()=>({actors:[],posts:[{entity_id:'p1'}]})};}});
assert.deepEqual(result.items,[{entity_id:'p1'}]);
assert.equal(new URL(requested).searchParams.get('q'),query);
const view = buildAppViewModel({route:parseRoute('#/discover?q=test'),forum:{discovery:{actors:[{did:'did:elix:abc',display_name:'<img src=x onerror=alert(1)>'}],posts:[{entity_type:'thread',entity_id:'t1',board_id:'b1',payload:{body:'<script>bad</script>'}}],boards:[],unavailable:true}}});
const html=renderPageBody(view);
assert.match(html,/data-public-search/);
assert.match(html,/#\/boards\/b1\/threads\/t1/);
assert.doesNotMatch(html,/<script>bad|<img src=x/);
assert.match(html,/role="status"/);
const link='trisaura://web-session/approve?challenge_id=wsc_1&relay_origin=https%3A%2F%2Frelay.elix.cool';
const challenge={challengeId:'wsc_1',deepLink:link,expectedRelayOrigin:'https://relay.elix.cool'};
assert.equal(safeApprovalLink(challenge),link);
for(const deepLink of [link.replace('wsc_1','wsc_other'),link.replace('relay.elix.cool','evil.example'),link+'&challenge_id=wsc_2','javascript:alert(1)']) {
  assert.equal(safeApprovalLink({...challenge,deepLink}),null);
}
assert.equal(safeApprovalLink({...challenge,expectedRelayOrigin:undefined}),null);
console.log('ok - discovery reads real posts contract, escapes content, and binds app handoff to challenge and Relay');

const boardsHtml = renderPageBody(buildAppViewModel({route:parseRoute('#/boards'),forum:{boards:[{id:'general',title:'General',permissions:{canWrite:true}}]}}));
assert.match(boardsHtml,/可瀏覽的公開看板/);
assert.doesNotMatch(boardsHtml,/已訂閱與可用看板|BOARDS · 訂閱的板/);
assert.match(boardsHtml,/需登入與符合資格/);
