// Tests for ../../firestore.rules, run against the Firestore emulator.
// The point: who can see whose progress, and who can create or change
// friend requests. `npm test` in this folder starts the emulator and runs it.

const { readFileSync } = require('node:fs');
const { test, before, after, beforeEach } = require('node:test');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc,
  collection, getDocs, query, where,
} = require('firebase/firestore');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ecosteps',
    firestore: { rules: readFileSync('../../firestore.rules', 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const as = (uid, claims = {}) => env.authenticatedContext(uid, claims).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();
const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

const pending = (from, to) => ({
  from, to, fromName: `${from} name`, toName: `${to} name`,
  status: 'pending', createdAt: new Date(),
});
const accepted = (from, to) => ({ ...pending(from, to), status: 'accepted' });

async function seedProfile(uid) {
  await seed(async (db) => {
    await setDoc(doc(db, `users/${uid}`), { displayName: uid, friendCode: 'ABC234' });
    await setDoc(doc(db, `users/${uid}/progress/summary`), { completed: 3, total: 10, areas: [] });
    await setDoc(doc(db, `users/${uid}/progress/state`), { schema: 1, items: [] });
  });
}

// ---------------------------------------------------------------- progress

test('a stranger cannot read anyone\'s profile or progress', async () => {
  await seedProfile('alice');
  const bob = as('bob');
  await assertFails(getDoc(doc(bob, 'users/alice')));
  await assertFails(getDoc(doc(bob, 'users/alice/progress/summary')));
});

test('signed-out visitors cannot read progress either', async () => {
  await seedProfile('alice');
  await assertFails(getDoc(doc(anonymous(), 'users/alice/progress/summary')));
});

test('the owner reads and writes their own progress', async () => {
  await seedProfile('alice');
  const alice = as('alice');
  await assertSucceeds(getDoc(doc(alice, 'users/alice/progress/summary')));
  await assertSucceeds(
    setDoc(doc(alice, 'users/alice/progress/summary'), { completed: 4, total: 10, areas: [] }),
  );
});

test('a pending request does not give access to progress', async () => {
  await seedProfile('alice');
  await seed((db) => setDoc(doc(db, 'friendRequests/bob_alice'), pending('bob', 'alice')));
  const bob = as('bob');
  await assertFails(getDoc(doc(bob, 'users/alice/progress/summary')));
  await assertFails(getDoc(doc(bob, 'users/alice')));
});

test('accepted friends can read each other, in either direction', async () => {
  await seedProfile('alice');
  await seedProfile('bob');
  await seed((db) => setDoc(doc(db, 'friendRequests/bob_alice'), accepted('bob', 'alice')));
  await assertSucceeds(getDoc(doc(as('bob'), 'users/alice/progress/summary')));
  await assertSucceeds(getDoc(doc(as('bob'), 'users/alice')));
  await assertSucceeds(getDoc(doc(as('alice'), 'users/bob/progress/summary')));
});

test('a friend of alice cannot read a third person\'s progress', async () => {
  await seedProfile('alice');
  await seedProfile('carol');
  await seed((db) => setDoc(doc(db, 'friendRequests/bob_alice'), accepted('bob', 'alice')));
  await assertFails(getDoc(doc(as('bob'), 'users/carol/progress/summary')));
});

test('friends cannot write each other\'s progress, and cannot read the sync state', async () => {
  await seedProfile('alice');
  await seed((db) => setDoc(doc(db, 'friendRequests/bob_alice'), accepted('bob', 'alice')));
  const bob = as('bob');
  await assertFails(
    setDoc(doc(bob, 'users/alice/progress/summary'), { completed: 99, total: 99, areas: [] }),
  );
  await assertFails(getDoc(doc(bob, 'users/alice/progress/state')));
});

test('removing the request ends access', async () => {
  await seedProfile('alice');
  await seed((db) => setDoc(doc(db, 'friendRequests/bob_alice'), accepted('bob', 'alice')));
  await assertSucceeds(getDoc(doc(as('bob'), 'users/alice/progress/summary')));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'friendRequests/bob_alice')));
  await assertFails(getDoc(doc(as('bob'), 'users/alice/progress/summary')));
});

test('the sync state keeps its shape check', async () => {
  const alice = as('alice');
  await assertSucceeds(setDoc(doc(alice, 'users/alice/progress/state'), { schema: 1, items: [] }));
  await assertFails(setDoc(doc(alice, 'users/alice/progress/state'), { schema: 1, items: [], extra: 1 }));
  await assertFails(setDoc(doc(alice, 'users/alice/progress/state'), { schema: 1, items: 'nope' }));
});

// ------------------------------------------------------------ friend codes

test('friend codes: signed-in users can look one up, nobody can list them', async () => {
  await seed((db) => setDoc(doc(db, 'friendCodes/ABC234'), { uid: 'alice', displayName: 'Alice' }));
  await assertSucceeds(getDoc(doc(as('bob'), 'friendCodes/ABC234')));
  await assertFails(getDoc(doc(anonymous(), 'friendCodes/ABC234')));
  await assertFails(getDocs(collection(as('bob'), 'friendCodes')));
});

test('friend codes: you can only claim a code for yourself', async () => {
  const bob = as('bob');
  await assertSucceeds(setDoc(doc(bob, 'friendCodes/BBB222'), { uid: 'bob', displayName: 'Bob' }));
  await assertFails(setDoc(doc(bob, 'friendCodes/BBB223'), { uid: 'alice', displayName: 'Alice' }));
  await assertFails(setDoc(doc(bob, 'friendCodes/TOOLONGCODE'), { uid: 'bob', displayName: 'Bob' }));
  await assertFails(setDoc(doc(bob, 'friendCodes/BBB224'), { uid: 'bob', displayName: '' }));
  await assertFails(setDoc(doc(bob, 'friendCodes/BBB225'), { uid: 'bob', displayName: 'Bob', extra: 1 }));
});

test('friend codes: nobody can take over or delete someone else\'s code', async () => {
  await seed((db) => setDoc(doc(db, 'friendCodes/ABC234'), { uid: 'alice', displayName: 'Alice' }));
  const bob = as('bob');
  await assertFails(setDoc(doc(bob, 'friendCodes/ABC234'), { uid: 'bob', displayName: 'Bob' }));
  await assertFails(updateDoc(doc(bob, 'friendCodes/ABC234'), { displayName: 'Hacked' }));
  await assertFails(deleteDoc(doc(bob, 'friendCodes/ABC234')));
  await assertSucceeds(updateDoc(doc(as('alice'), 'friendCodes/ABC234'), { displayName: 'Alice J' }));
});

// --------------------------------------------------------- friend requests

test('requests: you can send one as yourself, pending only, to someone else', async () => {
  const bob = as('bob');
  await assertSucceeds(setDoc(doc(bob, 'friendRequests/bob_alice'), pending('bob', 'alice')));
  await assertFails(setDoc(doc(bob, 'friendRequests/alice_carol'), pending('alice', 'carol')));
  await assertFails(setDoc(doc(bob, 'friendRequests/bob_carol'), accepted('bob', 'carol')));
  await assertFails(setDoc(doc(bob, 'friendRequests/bob_bob'), pending('bob', 'bob')));
  await assertFails(setDoc(doc(bob, 'friendRequests/wrong_id'), pending('bob', 'dave')));
  await assertFails(setDoc(doc(bob, 'friendRequests/bob_erin'), { ...pending('bob', 'erin'), extra: 1 }));
  await assertFails(setDoc(doc(anonymous(), 'friendRequests/bob_frank'), pending('bob', 'frank')));
});

test('requests: only the person asked can accept, and only the status changes', async () => {
  await seed((db) => setDoc(doc(db, 'friendRequests/bob_alice'), pending('bob', 'alice')));
  await assertFails(updateDoc(doc(as('bob'), 'friendRequests/bob_alice'), { status: 'accepted' }));
  await assertFails(updateDoc(doc(as('carol'), 'friendRequests/bob_alice'), { status: 'accepted' }));
  await assertFails(updateDoc(doc(as('alice'), 'friendRequests/bob_alice'), { status: 'accepted', toName: 'x' }));
  await assertFails(updateDoc(doc(as('alice'), 'friendRequests/bob_alice'), { status: 'weird' }));
  await assertSucceeds(updateDoc(doc(as('alice'), 'friendRequests/bob_alice'), { status: 'accepted' }));
});

test('requests: an accepted request cannot be changed back or edited', async () => {
  await seed((db) => setDoc(doc(db, 'friendRequests/bob_alice'), accepted('bob', 'alice')));
  await assertFails(updateDoc(doc(as('alice'), 'friendRequests/bob_alice'), { status: 'pending' }));
  await assertFails(updateDoc(doc(as('bob'), 'friendRequests/bob_alice'), { fromName: 'x' }));
});

test('requests: only the two people involved can see or delete one', async () => {
  await seed((db) => setDoc(doc(db, 'friendRequests/bob_alice'), pending('bob', 'alice')));
  await assertSucceeds(getDoc(doc(as('bob'), 'friendRequests/bob_alice')));
  await assertSucceeds(getDoc(doc(as('alice'), 'friendRequests/bob_alice')));
  await assertFails(getDoc(doc(as('carol'), 'friendRequests/bob_alice')));
  await assertFails(deleteDoc(doc(as('carol'), 'friendRequests/bob_alice')));
  await assertSucceeds(deleteDoc(doc(as('bob'), 'friendRequests/bob_alice')));
});

test('requests: looking for one that does not exist is fine, for your own pair only', async () => {
  await assertSucceeds(getDoc(doc(as('bob'), 'friendRequests/bob_alice')));
  await assertSucceeds(getDoc(doc(as('alice'), 'friendRequests/bob_alice')));
  await assertFails(getDoc(doc(as('carol'), 'friendRequests/bob_alice')));
});

test('requests: listing works for your own, not for everyone\'s', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'friendRequests/bob_alice'), pending('bob', 'alice'));
    await setDoc(doc(db, 'friendRequests/carol_dave'), pending('carol', 'dave'));
  });
  const alice = as('alice');
  const mine = await assertSucceeds(
    getDocs(query(collection(alice, 'friendRequests'), where('to', '==', 'alice'))),
  );
  if (mine.size !== 1) throw new Error(`expected 1 request, got ${mine.size}`);
  await assertSucceeds(
    getDocs(query(collection(alice, 'friendRequests'), where('from', '==', 'alice'))),
  );
  await assertFails(getDocs(collection(alice, 'friendRequests')));
  await assertFails(
    getDocs(query(collection(alice, 'friendRequests'), where('to', '==', 'dave'))),
  );
});

// ------------------------------------------------------------ demo friends

test('demo friends: anyone can read them, only the app owner can write', async () => {
  await seed((db) => setDoc(doc(db, 'demoFriends/demo-mila'), { name: 'Mila', completed: 1, total: 2, areas: [] }));
  await assertSucceeds(getDoc(doc(anonymous(), 'demoFriends/demo-mila')));
  await assertSucceeds(getDocs(collection(anonymous(), 'demoFriends')));
  await assertFails(setDoc(doc(as('bob'), 'demoFriends/demo-x'), { name: 'X' }));
  await assertFails(setDoc(doc(as('bob', { email: 'someone@else.com' }), 'demoFriends/demo-x'), { name: 'X' }));
  await assertSucceeds(
    setDoc(doc(as('thomas', { email: 'pennock.thomas@gmail.com' }), 'demoFriends/demo-x'), { name: 'X' }),
  );
});

// ------------------------------------------------------------ everything else

test('anything not listed is denied', async () => {
  await assertFails(getDoc(doc(as('alice'), 'somethingElse/doc')));
  await assertFails(setDoc(doc(as('alice'), 'somethingElse/doc'), { a: 1 }));
});
