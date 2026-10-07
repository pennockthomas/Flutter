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

// ------------------------------------------------------------------ houses

const { arrayUnion, arrayRemove } = require('firebase/firestore');

const newHouse = (members, extra = {}) => ({
  name: 'House', memberUids: members, createdBy: members[0], createdAt: new Date(), ...extra,
});
const invite = (houseId, from, to, name = 'House') => ({
  houseId, houseName: name, from, fromName: from, to, status: 'pending', createdAt: new Date(),
});
const friends = (a, b) => seed((db) => setDoc(doc(db, `friendRequests/${a}_${b}`), accepted(a, b)));

test('houses: you can create one with only yourself in it', async () => {
  const alice = as('alice');
  await assertSucceeds(setDoc(doc(alice, 'houses/h1'), newHouse(['alice'])));
  await assertFails(setDoc(doc(alice, 'houses/h2'), newHouse(['alice', 'bob'])));
  await assertFails(setDoc(doc(alice, 'houses/h3'), newHouse(['bob'], { createdBy: 'alice' })));
  await assertFails(setDoc(doc(alice, 'houses/h4'), newHouse(['alice'], { name: '' })));
  await assertFails(setDoc(doc(alice, 'houses/h5'), newHouse(['alice'], { name: 'x'.repeat(41) })));
  await assertFails(setDoc(doc(alice, 'houses/h6'), newHouse(['alice'], { extra: 1 })));
  await assertFails(setDoc(doc(anonymous(), 'houses/h7'), newHouse(['alice'])));
});

test('houses: only members can read one, and "my houses" works as a query', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob']));
    await setDoc(doc(db, 'houses/h2'), newHouse(['carol']));
  });
  await assertSucceeds(getDoc(doc(as('bob'), 'houses/h1')));
  await assertFails(getDoc(doc(as('dave'), 'houses/h1')));
  await assertFails(getDoc(doc(anonymous(), 'houses/h1')));
  const mine = await assertSucceeds(
    getDocs(query(collection(as('bob'), 'houses'), where('memberUids', 'array-contains', 'bob'))),
  );
  if (mine.size !== 1) throw new Error(`expected 1 house, got ${mine.size}`);
  await assertFails(getDocs(collection(as('bob'), 'houses')));
  await assertFails(
    getDocs(query(collection(as('bob'), 'houses'), where('memberUids', 'array-contains', 'carol'))),
  );
});

test('houses: any member can rename it, a stranger cannot', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob'])));
  await assertSucceeds(updateDoc(doc(as('bob'), 'houses/h1'), { name: 'Our place' }));
  await assertFails(updateDoc(doc(as('bob'), 'houses/h1'), { name: '' }));
  await assertFails(updateDoc(doc(as('dave'), 'houses/h1'), { name: 'Mine now' }));
  await assertFails(updateDoc(doc(as('bob'), 'houses/h1'), { createdBy: 'bob' }));
});

test('houses: a member can remove another member or leave, never add', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob', 'carol'])));
  const bob = as('bob');
  await assertFails(updateDoc(doc(bob, 'houses/h1'), { memberUids: arrayUnion('dave') }));
  await assertSucceeds(updateDoc(doc(bob, 'houses/h1'), { memberUids: arrayRemove('carol') }));
  await assertSucceeds(updateDoc(doc(bob, 'houses/h1'), { memberUids: arrayRemove('bob') }));
  await assertFails(updateDoc(doc(as('carol'), 'houses/h1'), { name: 'removed people cannot edit' }));
});

test('houses: nobody can empty a house by editing it', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  await assertFails(updateDoc(doc(as('alice'), 'houses/h1'), { memberUids: [] }));
});

test('houses: joining needs an invitation, and only adds yourself', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  const bob = as('bob');
  await assertFails(updateDoc(doc(bob, 'houses/h1'), { memberUids: arrayUnion('bob') }));

  await seed((db) => setDoc(doc(db, 'houseInvites/h1_bob'), invite('h1', 'alice', 'bob')));
  await assertFails(updateDoc(doc(bob, 'houses/h1'), { memberUids: arrayUnion('carol') }));
  await assertFails(updateDoc(doc(bob, 'houses/h1'), { memberUids: ['bob'] }));
  await assertFails(updateDoc(doc(bob, 'houses/h1'), { memberUids: arrayUnion('bob'), name: 'Mine' }));
  await assertSucceeds(updateDoc(doc(bob, 'houses/h1'), { memberUids: arrayUnion('bob') }));
});

test('houses: an invitation for one person does not let another join', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice']));
    await setDoc(doc(db, 'houseInvites/h1_bob'), invite('h1', 'alice', 'bob'));
  });
  await assertFails(updateDoc(doc(as('carol'), 'houses/h1'), { memberUids: arrayUnion('carol') }));
});

test('houses: a full house (8) cannot be joined', async () => {
  const eight = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(eight));
    await setDoc(doc(db, 'houseInvites/h1_ivy'), invite('h1', 'a', 'ivy'));
  });
  await assertFails(updateDoc(doc(as('ivy'), 'houses/h1'), { memberUids: arrayUnion('ivy') }));
});

test('houses: only the last member can delete the house', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob']));
    await setDoc(doc(db, 'houses/h2'), newHouse(['carol']));
  });
  await assertFails(deleteDoc(doc(as('alice'), 'houses/h1')));
  await assertFails(deleteDoc(doc(as('alice'), 'houses/h2')));
  await assertSucceeds(deleteDoc(doc(as('carol'), 'houses/h2')));
});

// ---------------------------------------------------------- house invites

test('invites: a member can invite their own friend', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  await friends('alice', 'bob');
  await assertSucceeds(setDoc(doc(as('alice'), 'houseInvites/h1_bob'), invite('h1', 'alice', 'bob')));
});

test('invites: not for someone who is not your friend, or while only pending', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  await assertFails(setDoc(doc(as('alice'), 'houseInvites/h1_bob'), invite('h1', 'alice', 'bob')));
  await seed((db) => setDoc(doc(db, 'friendRequests/alice_bob'), pending('alice', 'bob')));
  await assertFails(setDoc(doc(as('alice'), 'houseInvites/h1_bob'), invite('h1', 'alice', 'bob')));
});

test('invites: a non-member cannot invite, nor forge who sent it', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  await friends('dave', 'bob');
  await friends('alice', 'bob');
  await assertFails(setDoc(doc(as('dave'), 'houseInvites/h1_bob'), invite('h1', 'dave', 'bob')));
  await assertFails(setDoc(doc(as('dave'), 'houseInvites/h1_bob'), invite('h1', 'alice', 'bob')));
});

test('invites: not to someone already inside, not with the wrong id or house name', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob'])));
  await friends('alice', 'bob');
  await friends('alice', 'carol');
  const alice = as('alice');
  await assertFails(setDoc(doc(alice, 'houseInvites/h1_bob'), invite('h1', 'alice', 'bob')));
  await assertFails(setDoc(doc(alice, 'houseInvites/wrong'), invite('h1', 'alice', 'carol')));
  await assertFails(setDoc(doc(alice, 'houseInvites/h1_carol'), invite('h1', 'alice', 'carol', 'Fake name')));
  await assertFails(setDoc(doc(alice, 'houseInvites/h1_alice'), invite('h1', 'alice', 'alice')));
});

test('invites: no inviting into a full house', async () => {
  const eight = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(eight)));
  await friends('a', 'ivy');
  await assertFails(setDoc(doc(as('a'), 'houseInvites/h1_ivy'), invite('h1', 'a', 'ivy')));
});

test('invites: who can see and remove one', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'carol']));
    await setDoc(doc(db, 'houseInvites/h1_bob'), invite('h1', 'alice', 'bob'));
  });
  await assertSucceeds(getDoc(doc(as('bob'), 'houseInvites/h1_bob')));
  await assertFails(getDoc(doc(as('dave'), 'houseInvites/h1_bob')));
  const incoming = await assertSucceeds(
    getDocs(query(collection(as('bob'), 'houseInvites'), where('to', '==', 'bob'))),
  );
  if (incoming.size !== 1) throw new Error('bob should see his invitation');
  await assertSucceeds(
    getDocs(query(collection(as('carol'), 'houseInvites'), where('houseId', '==', 'h1'))),
  );
  await assertFails(
    getDocs(query(collection(as('dave'), 'houseInvites'), where('houseId', '==', 'h1'))),
  );
  await assertFails(deleteDoc(doc(as('dave'), 'houseInvites/h1_bob')));
  await assertSucceeds(deleteDoc(doc(as('bob'), 'houseInvites/h1_bob')));
});

// ------------------------------------------------------ house member names

const nameDoc = (name = 'Alice', extra = {}) => ({ name, updatedAt: new Date(), ...extra });

test('house names: members read each other, outsiders cannot', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob']));
    await setDoc(doc(db, 'houses/h1/members/alice'), nameDoc());
  });
  await assertSucceeds(getDoc(doc(as('bob'), 'houses/h1/members/alice')));
  await assertSucceeds(getDocs(collection(as('bob'), 'houses/h1/members')));
  await assertFails(getDoc(doc(as('dave'), 'houses/h1/members/alice')));
  await assertFails(getDoc(doc(anonymous(), 'houses/h1/members/alice')));
});

test('house names: you write only your own, with the right shape', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob'])));
  const alice = as('alice');
  await assertSucceeds(setDoc(doc(alice, 'houses/h1/members/alice'), nameDoc()));
  await assertFails(setDoc(doc(alice, 'houses/h1/members/bob'), nameDoc('Bob')));
  await assertFails(setDoc(doc(alice, 'houses/h1/members/alice'), nameDoc('Alice', { completed: 99 })));
  await assertFails(setDoc(doc(alice, 'houses/h1/members/alice'), nameDoc('')));
  await assertFails(setDoc(doc(alice, 'houses/h1/members/alice'), nameDoc('x'.repeat(61))));
});

test('house names: someone who is not in the house cannot write', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  await assertFails(setDoc(doc(as('dave'), 'houses/h1/members/dave'), nameDoc('Dave')));
});

test('house names: a member can delete someone\'s name before removing them', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob']));
    await setDoc(doc(db, 'houses/h1/members/bob'), nameDoc('Bob'));
  });
  await assertFails(deleteDoc(doc(as('dave'), 'houses/h1/members/bob')));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'houses/h1/members/bob')));
});

test('leaving a house: your name goes first, then you', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob']));
    await setDoc(doc(db, 'houses/h1/members/bob'), nameDoc('Bob'));
  });
  const bob = as('bob');
  await assertSucceeds(deleteDoc(doc(bob, 'houses/h1/members/bob')));
  await assertSucceeds(updateDoc(doc(bob, 'houses/h1'), { memberUids: arrayRemove('bob') }));
  await assertFails(getDoc(doc(bob, 'houses/h1')));
  await assertFails(setDoc(doc(bob, 'houses/h1/members/bob'), nameDoc('Bob')));
});

// ------------------------------------------------------- the house's tree

const swap = (by, done = true, extra = {}) => ({ done, at: 1760000000000, by, ...extra });
const branch = (by, open = true, extra = {}) => ({ open, at: 1760000000000, by, ...extra });

test('house tree: members read it, outsiders and signed-out visitors cannot', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob']));
    await setDoc(doc(db, 'houses/h1/swaps/kitchen.metal-knives'), swap('alice'));
    await setDoc(doc(db, 'houses/h1/tiers/Kitchen'), branch('alice'));
  });
  await assertSucceeds(getDoc(doc(as('bob'), 'houses/h1/swaps/kitchen.metal-knives')));
  await assertSucceeds(getDocs(collection(as('bob'), 'houses/h1/swaps')));
  await assertSucceeds(getDocs(collection(as('bob'), 'houses/h1/tiers')));
  await assertFails(getDoc(doc(as('dave'), 'houses/h1/swaps/kitchen.metal-knives')));
  await assertFails(getDocs(collection(as('dave'), 'houses/h1/swaps')));
  await assertFails(getDoc(doc(anonymous(), 'houses/h1/tiers/Kitchen')));
});

test('house tree: any member can tick a swap, recorded as themselves', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob'])));
  const bob = as('bob');
  await assertSucceeds(setDoc(doc(bob, 'houses/h1/swaps/kitchen.metal-knives'), swap('bob')));
  await assertSucceeds(setDoc(doc(bob, 'houses/h1/swaps/kitchen.metal-knives'), swap('bob', false)));
  await assertSucceeds(setDoc(doc(as('alice'), 'houses/h1/swaps/kitchen.metal-knives'), swap('alice')));
});

test('house tree: nobody can tick on someone else\'s behalf', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob'])));
  await assertFails(setDoc(doc(as('bob'), 'houses/h1/swaps/kitchen.metal-knives'), swap('alice')));
  await assertFails(setDoc(doc(as('bob'), 'houses/h1/tiers/Kitchen'), branch('alice')));
});

test('house tree: outsiders cannot change it', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  await assertFails(setDoc(doc(as('dave'), 'houses/h1/swaps/kitchen.metal-knives'), swap('dave')));
  await assertFails(setDoc(doc(as('dave'), 'houses/h1/tiers/Kitchen'), branch('dave')));
  await assertFails(setDoc(doc(anonymous(), 'houses/h1/swaps/kitchen.metal-knives'), swap('dave')));
});

test('house tree: a removed member can no longer tick', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice', 'bob']));
  });
  await assertSucceeds(updateDoc(doc(as('alice'), 'houses/h1'), { memberUids: arrayRemove('bob') }));
  await assertFails(setDoc(doc(as('bob'), 'houses/h1/swaps/kitchen.metal-knives'), swap('bob')));
});

test('house tree: ticks have a fixed shape', async () => {
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  const alice = as('alice');
  await assertFails(setDoc(doc(alice, 'houses/h1/swaps/a'), swap('alice', true, { extra: 1 })));
  await assertFails(setDoc(doc(alice, 'houses/h1/swaps/a'), swap('alice', 'yes')));
  await assertFails(setDoc(doc(alice, 'houses/h1/swaps/a'), { done: true, by: 'alice' }));
  await assertFails(setDoc(doc(alice, 'houses/h1/swaps/a'), { done: true, at: 'now', by: 'alice' }));
  await assertFails(setDoc(doc(alice, `houses/h1/swaps/${'x'.repeat(101)}`), swap('alice')));
  await assertFails(setDoc(doc(alice, 'houses/h1/tiers/Kitchen'), branch('alice', true, { extra: 1 })));
  await assertFails(setDoc(doc(alice, 'houses/h1/tiers/Kitchen'), branch('alice', 'open')));
});

test('house tree: ticks are never deleted, an untick is a record', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice']));
    await setDoc(doc(db, 'houses/h1/swaps/a'), swap('alice'));
    await setDoc(doc(db, 'houses/h1/tiers/Kitchen'), branch('alice'));
  });
  await assertFails(deleteDoc(doc(as('alice'), 'houses/h1/swaps/a')));
  await assertFails(deleteDoc(doc(as('alice'), 'houses/h1/tiers/Kitchen')));
});

test('house tree: a whole tree\'s worth of swaps can be written in one batch', async () => {
  const { writeBatch } = require('firebase/firestore');
  await seed((db) => setDoc(doc(db, 'houses/h1'), newHouse(['alice'])));
  const db = as('alice');
  const batch = writeBatch(db);
  for (let i = 0; i < 118; i += 1) {
    batch.set(doc(db, `houses/h1/swaps/swap.${i}`), swap('alice'));
  }
  await assertSucceeds(batch.commit());
});

test('houses cannot see each other\'s trees', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'houses/h1'), newHouse(['alice']));
    await setDoc(doc(db, 'houses/h2'), newHouse(['bob']));
    await setDoc(doc(db, 'houses/h2/swaps/a'), swap('bob'));
  });
  await assertFails(getDoc(doc(as('alice'), 'houses/h2/swaps/a')));
  await assertFails(setDoc(doc(as('alice'), 'houses/h2/swaps/a'), swap('alice')));
});

// ------------------------------------------------------------ everything else

test('anything not listed is denied', async () => {
  await assertFails(getDoc(doc(as('alice'), 'somethingElse/doc')));
  await assertFails(setDoc(doc(as('alice'), 'somethingElse/doc'), { a: 1 }));
});
