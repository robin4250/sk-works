// A counterexample to a proposed backfill shortcut; synthetic data only.
// It models the #1494 capacity branch, not the Collector database itself.
import {test} from 'node:test';import assert from 'node:assert/strict';
const event={event_id:'synthetic-event',collector_id:'synthetic-collector',received_at:100,kind:'current_lure_touched'};
function capacityGapAt(oldRecipient){
 const state={source:[],outbox:[],capacity_gaps:0,config:{recipient:oldRecipient,revision:1}};
 state.source.push(event);state.capacity_gaps++;// No event ID, original recipient or revision stored by the full-queue branch.
 state.config={recipient:'new-owner',revision:2};return state;
}
test('a gap count and source alone cannot recover the recipient bound at ingress',()=>{
 const scenarioA=capacityGapAt('old-owner-a'),scenarioB=capacityGapAt('old-owner-b');
 assert.deepEqual(scenarioA,scenarioB,'different prior owners leave identical observable data');
 assert.notEqual('old-owner-a','old-owner-b','required original recipients differ');
});
test('an unpinned old event may disappear under the existing seven-day source retention',()=>{
 const state=capacityGapAt('old-owner-a'),cutoff=200;
 state.source=state.source.filter(e=>e.received_at>=cutoff||state.outbox.some(o=>o.event_id===e.event_id));
 assert.equal(state.source.length,0);assert.equal(state.capacity_gaps,1,'counter cannot reconstruct purged event');
});
