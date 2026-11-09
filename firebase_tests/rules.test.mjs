import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  collection,
  getDocs,
  increment,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const S = 'businesses/b1/stores/s1';
const S2 = 'businesses/b1/stores/s2';
const OTHER = 'businesses/b2/stores/x1';
let env;

const db = (uid) =>
  uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();

const future = () => Timestamp.fromDate(new Date(Date.now() + 86400000));
const past = () => Timestamp.fromDate(new Date(Date.now() - 86400000));

const bill = (byUid, extra = {}) => ({
  number: 'N1',
  items: [],
  subtotalPaise: 1000,
  discountPaise: 100,
  totalPaise: 900,
  cashPaise: 400,
  upiPaise: 500,
  creditPaise: 0,
  customerId: null,
  byUid,
  voided: false,
  ...extra,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-kirana',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    const member = (role, storeIds, active = true) => ({ name: role, role, storeIds, active });
    await setDoc(doc(d, 'businesses/b1'), { name: 'Shop', ownerUid: 'owner' });
    await setDoc(doc(d, 'businesses/b2'), { name: 'Rival', ownerUid: 'rival' });
    await setDoc(doc(d, 'businesses/b1/members/owner'), member('owner', []));
    await setDoc(doc(d, 'businesses/b1/members/mgr'), member('manager', ['s1']));
    await setDoc(doc(d, 'businesses/b1/members/cash'), member('cashier', ['s1']));
    await setDoc(doc(d, 'businesses/b1/members/cash2'), member('cashier', ['s2']));
    await setDoc(doc(d, 'businesses/b1/members/gone'), member('cashier', ['s1'], false));
    await setDoc(doc(d, 'businesses/b2/members/rival'), member('owner', []));
    await setDoc(doc(d, S), { name: 'One' });
    await setDoc(doc(d, S2), { name: 'Two' });
    await setDoc(doc(d, OTHER), { name: 'Rival store' });
    await setDoc(doc(d, `${S}/customers/c1`), { name: 'Ravi', balancePaise: 500, creditLimitPaise: 0 });
    await setDoc(doc(d, `${S}/products/p1`), { name: 'Rice', pricePaise: 100, costPaise: 80, stockMilli: 5000 });
    await setDoc(doc(d, `${S}/bills/b1`), bill('cash'));
    await setDoc(doc(d, `${S}/khata/k1`), { customerId: 'c1', amountPaise: 500, byUid: 'cash' });
    await setDoc(doc(d, `${S}/expenses/e1`), { amountPaise: 100, voided: false, byUid: 'cash' });
    await setDoc(doc(d, `${S}/suppliers/su1`), { name: 'W', balancePaise: 0 });
    await setDoc(doc(d, 'invites/GOODCODE'), {
      businessId: 'b1', businessName: 'Shop', role: 'cashier', storeIds: ['s1'],
      createdBy: 'owner', expiresAt: future(), usedBy: null,
    });
    await setDoc(doc(d, 'invites/OLDCODE1'), {
      businessId: 'b1', businessName: 'Shop', role: 'manager', storeIds: ['s1'],
      createdBy: 'owner', expiresAt: past(), usedBy: null,
    });
  });
});

describe('isolation', () => {
  test('anonymous users read nothing', () => assertFails(getDoc(doc(db(null), `${S}/customers/c1`))));
  test('another business is unreadable', () => assertFails(getDoc(doc(db('rival'), `${S}/customers/c1`))));
  test('another business cannot write', () =>
    assertFails(setDoc(doc(db('rival'), `${S}/customers/x`), { name: 'Spy' })));
  test('a member cannot read a store they are not assigned', () =>
    assertFails(getDoc(doc(db('cash2'), `${S}/customers/c1`))));
  test('a member can read their own store', () =>
    assertSucceeds(getDoc(doc(db('cash'), `${S}/customers/c1`))));
  test('the owner reaches every store', () =>
    assertSucceeds(getDoc(doc(db('owner'), `${S2}`))));
  test('a deactivated member is locked out', () =>
    assertFails(getDoc(doc(db('gone'), `${S}/customers/c1`))));
  test('a deactivated member cannot queue a sale', () =>
    assertFails(setDoc(doc(db('gone'), `${S}/bills/x`), bill('gone'))));
  test('a user profile is private', () =>
    assertFails(getDoc(doc(db('cash'), 'users/owner'))));
});

describe('onboarding', () => {
  test('a new owner creates business, member and store together', async () => {
    const d = db('newbie');
    const batch = writeBatch(d);
    batch.set(doc(d, 'businesses/b9'), { name: 'New', ownerUid: 'newbie' });
    batch.set(doc(d, 'businesses/b9/members/newbie'), {
      name: 'N', role: 'owner', storeIds: [], active: true,
    });
    batch.set(doc(d, 'businesses/b9/stores/first'), { name: 'First' });
    batch.set(doc(d, 'users/newbie'), { businessId: 'b9' });
    await assertSucceeds(batch.commit());
  });

  test('a store cannot be added to someone else\'s business', () =>
    assertFails(setDoc(doc(db('newbie'), 'businesses/b1/stores/mine'), { name: 'Mine' })));

  test('nobody can make themselves owner of an existing business', () =>
    assertFails(setDoc(doc(db('newbie'), 'businesses/b1/members/newbie'), {
      name: 'N', role: 'owner', storeIds: [], active: true,
    })));

  const join = (d, uid, code, role = 'cashier', storeIds = ['s1'], bid = 'b1') => {
    const batch = writeBatch(d);
    batch.set(doc(d, `businesses/${bid}/members/${uid}`), {
      name: 'N', role, storeIds, active: true, inviteCode: code,
    });
    batch.update(doc(d, `invites/${code}`), { usedBy: uid, usedAt: serverTimestamp() });
    return batch.commit();
  };

  test('a valid invite joins with the invited role', () =>
    assertSucceeds(join(db('newbie'), 'newbie', 'GOODCODE')));
  test('an invite cannot be upgraded to manager', () =>
    assertFails(join(db('newbie'), 'newbie', 'GOODCODE', 'manager')));
  test('an invite cannot grant other stores', () =>
    assertFails(join(db('newbie'), 'newbie', 'GOODCODE', 'cashier', ['s1', 's2'])));
  test('an invite cannot be used on another business', () =>
    assertFails(join(db('newbie'), 'newbie', 'GOODCODE', 'cashier', ['s1'], 'b2')));
  test('an expired invite is refused', () =>
    assertFails(join(db('newbie'), 'newbie', 'OLDCODE1', 'manager')));
  test('an invite works once only', async () => {
    await assertSucceeds(join(db('newbie'), 'newbie', 'GOODCODE'));
    await assertFails(join(db('second'), 'second', 'GOODCODE'));
  });
  test('joining without burning the invite is refused', () =>
    assertFails(setDoc(doc(db('newbie'), 'businesses/b1/members/newbie'), {
      name: 'N', role: 'cashier', storeIds: ['s1'], active: true, inviteCode: 'GOODCODE',
    })));
  test('joining with a made-up code is refused', () =>
    assertFails(setDoc(doc(db('newbie'), 'businesses/b1/members/newbie'), {
      name: 'N', role: 'cashier', storeIds: ['s1'], active: true, inviteCode: 'NOPE',
    })));
  test('invites cannot be enumerated by outsiders', () =>
    assertFails(getDocs(collection(db('newbie'), 'invites'))));
  test('managers can list their own open invites', () =>
    assertSucceeds(getDocs(query(collection(db('mgr'), 'invites'), where('businessId', '==', 'b1')))));
  test('cashiers cannot create invites', () =>
    assertFails(setDoc(doc(db('cash'), 'invites/NEWCODE1'), {
      businessId: 'b1', role: 'cashier', storeIds: ['s1'], createdBy: 'cash', usedBy: null,
    })));
  test('nobody can invite an owner', () =>
    assertFails(setDoc(doc(db('owner'), 'invites/NEWCODE1'), {
      businessId: 'b1', role: 'owner', storeIds: [], createdBy: 'owner', usedBy: null,
    })));
});

describe('staff control', () => {
  const m = 'businesses/b1/members/cash';
  test('a cashier cannot promote themselves', () =>
    assertFails(updateDoc(doc(db('cash'), m), { role: 'manager' })));
  test('a manager cannot change staff', () =>
    assertFails(updateDoc(doc(db('mgr'), m), { active: false })));
  test('the owner can change staff', () =>
    assertSucceeds(updateDoc(doc(db('owner'), m), { role: 'manager', storeIds: ['s1', 's2'] })));
  test('the owner record cannot be demoted', () =>
    assertFails(updateDoc(doc(db('owner'), 'businesses/b1/members/owner'), { role: 'cashier' })));
  test('business ownership cannot be transferred from the client', () =>
    assertFails(updateDoc(doc(db('owner'), 'businesses/b1'), { ownerUid: 'cash' })));
  test('only the owner adds stores', () =>
    assertFails(setDoc(doc(db('mgr'), 'businesses/b1/stores/s3'), { name: 'Three' })));
  test('cashiers cannot list staff', () =>
    assertFails(getDocs(collection(db('cash'), 'businesses/b1/members'))));
});

describe('sales', () => {
  test('a cashier completes a sale as one batch', async () => {
    const d = db('cash');
    const batch = writeBatch(d);
    batch.set(doc(d, `${S}/bills/new`), bill('cash'));
    batch.set(doc(d, `${S}/products/p1`), { stockMilli: increment(-1000), updatedAt: serverTimestamp() }, { merge: true });
    batch.set(doc(d, `${S}/stockMoves/m1`), { productId: 'p1', deltaMilli: -1000, reason: 'sale', byUid: 'cash' });
    batch.set(doc(d, `${S}/days/2026-11-09`), { dayKey: '2026-11-09', salesPaise: increment(900) }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test('a credit sale updates the khata in the same batch', async () => {
    const d = db('cash');
    const batch = writeBatch(d);
    batch.set(doc(d, `${S}/bills/new`), bill('cash', { cashPaise: 0, upiPaise: 0, creditPaise: 900, customerId: 'c1' }));
    batch.set(doc(d, `${S}/khata/new`), {
      customerId: 'c1', kind: 'purchase', amountPaise: 900, reversesId: null, byUid: 'cash',
    });
    batch.set(doc(d, `${S}/customers/c1`), { balancePaise: increment(900), updatedAt: serverTimestamp() }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test('a bill cannot be signed as someone else', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/bills/x`), bill('owner'))));
  test('payments must add up to the total', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/bills/x`), bill('cash', { cashPaise: 1 }))));
  test('the total must equal subtotal less discount', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/bills/x`), bill('cash', { discountPaise: 200 }))));
  test('credit requires a customer', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/bills/x`), bill('cash', { cashPaise: 0, upiPaise: 0, creditPaise: 900 }))));
  test('money must be whole paise', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/bills/x`), bill('cash', { totalPaise: 900.5 }))));
  test('a cashier cannot void a bill', () =>
    assertFails(updateDoc(doc(db('cash'), `${S}/bills/b1`), { voided: true, voidReason: 'x' })));
  test('a manager can void a bill', () =>
    assertSucceeds(updateDoc(doc(db('mgr'), `${S}/bills/b1`), {
      voided: true, voidReason: 'x', voidedBy: 'mgr', voidedAt: serverTimestamp(),
    })));
  test('a void cannot alter the bill amounts', () =>
    assertFails(updateDoc(doc(db('mgr'), `${S}/bills/b1`), { voided: true, totalPaise: 1 })));
  test('bills cannot be deleted, even by the owner', () =>
    assertFails(deleteDoc(doc(db('owner'), `${S}/bills/b1`))));
});

describe('khata ledger', () => {
  const entry = (extra = {}) => ({
    customerId: 'c1', kind: 'payment', amountPaise: -100, reversesId: null, byUid: 'cash', ...extra,
  });
  test('a cashier records a payment', () =>
    assertSucceeds(setDoc(doc(db('cash'), `${S}/khata/x`), entry())));
  test('entries cannot be edited', () =>
    assertFails(updateDoc(doc(db('owner'), `${S}/khata/k1`), { amountPaise: 1 })));
  test('entries cannot be deleted', () =>
    assertFails(deleteDoc(doc(db('owner'), `${S}/khata/k1`))));
  test('a cashier cannot post an adjustment', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/khata/x`), entry({ kind: 'adjustment' }))));
  test('a manager can post an adjustment', () =>
    assertSucceeds(setDoc(doc(db('mgr'), `${S}/khata/x`), entry({ kind: 'adjustment', byUid: 'mgr' }))));
  test('a cashier cannot reverse an entry', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/khata/rev_k1`), entry({ reversesId: 'k1' }))));
  test('a reversal must use the id derived from the original', () =>
    assertFails(setDoc(doc(db('mgr'), `${S}/khata/random`), entry({ reversesId: 'k1', byUid: 'mgr' }))));
  test('the same entry cannot be reversed twice', async () => {
    const data = entry({ reversesId: 'k1', byUid: 'mgr' });
    await assertSucceeds(setDoc(doc(db('mgr'), `${S}/khata/rev_k1`), data));
    await assertFails(setDoc(doc(db('mgr'), `${S}/khata/rev_k1`), data));
  });
  test('a cashier cannot change a credit limit', () =>
    assertFails(updateDoc(doc(db('cash'), `${S}/customers/c1`), { creditLimitPaise: 99999 })));
  test('a cashier cannot archive a customer', () =>
    assertFails(updateDoc(doc(db('cash'), `${S}/customers/c1`), { archived: true })));
  test('a manager can change a credit limit', () =>
    assertSucceeds(updateDoc(doc(db('mgr'), `${S}/customers/c1`), { creditLimitPaise: 99999 })));
  test('customers cannot be deleted', () =>
    assertFails(deleteDoc(doc(db('owner'), `${S}/customers/c1`))));
});

describe('inventory and suppliers', () => {
  test('a cashier cannot change prices', () =>
    assertFails(updateDoc(doc(db('cash'), `${S}/products/p1`), { pricePaise: 1 })));
  test('a cashier cannot hide a price change inside a stock update', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/products/p1`), { stockMilli: increment(-1), pricePaise: 1 }, { merge: true })));
  test('a cashier cannot create products', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/products/x`), { name: 'X' })));
  test('a cashier cannot log a manual stock adjustment', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/stockMoves/x`), {
      productId: 'p1', deltaMilli: 100, reason: 'adjustment', byUid: 'cash',
    })));
  test('a manager can edit a product', () =>
    assertSucceeds(updateDoc(doc(db('mgr'), `${S}/products/p1`), { pricePaise: 150 })));
  test('stock history is immutable', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), `${S}/stockMoves/m`), { deltaMilli: 1 }));
    await assertFails(updateDoc(doc(db('owner'), `${S}/stockMoves/m`), { deltaMilli: 2 }));
  });
  test('cashiers cannot see suppliers', () =>
    assertFails(getDoc(doc(db('cash'), `${S}/suppliers/su1`))));
  test('managers can see suppliers', () =>
    assertSucceeds(getDoc(doc(db('mgr'), `${S}/suppliers/su1`))));
  test('cashiers cannot record supplier payments', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/supplierTxns/x`), { amountPaise: 1, byUid: 'cash' })));
});

describe('expenses and rollups', () => {
  test('a cashier can add an expense', () =>
    assertSucceeds(setDoc(doc(db('cash'), `${S}/expenses/x`), { amountPaise: 100, voided: false, byUid: 'cash' })));
  test('an expense must be positive', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/expenses/x`), { amountPaise: -1, voided: false, byUid: 'cash' })));
  test('a cashier cannot void an expense', () =>
    assertFails(updateDoc(doc(db('cash'), `${S}/expenses/e1`), { voided: true })));
  test('a manager can void an expense', () =>
    assertSucceeds(updateDoc(doc(db('mgr'), `${S}/expenses/e1`), {
      voided: true, voidedBy: 'mgr', voidedAt: serverTimestamp(),
    })));
  test('a rollup must be written to its own day', () =>
    assertFails(setDoc(doc(db('cash'), `${S}/days/2026-01-01`), { dayKey: '2026-01-02' })));
  test('rollups cannot be deleted', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), `${S}/days/2026-01-01`), { dayKey: '2026-01-01' }));
    await assertFails(deleteDoc(doc(db('owner'), `${S}/days/2026-01-01`)));
  });
});
