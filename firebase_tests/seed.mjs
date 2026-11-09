// Fills the local emulators with demo data. Refuses to run against anything else.
// Start emulators first: firebase emulators:start --project demo-kirana
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';

initializeApp({ projectId: 'demo-kirana' });
const db = getFirestore();
const auth = getAuth();

const DEMO_PASSWORD = 'demo-pass-123';
const makeUser = async (email, displayName) =>
  (await auth.createUser({ email, password: DEMO_PASSWORD, displayName })).uid;

const owner = await makeUser('owner@demo.test', 'Lakshmi');
const cashier = await makeUser('cashier@demo.test', 'Suresh');

const b = db.doc('businesses/demo');
await b.set({ name: 'Sri Lakshmi Stores', ownerUid: owner });
await b.collection('members').doc(owner).set({
  name: 'Lakshmi', email: 'owner@demo.test', role: 'owner', storeIds: [], active: true,
});
await b.collection('members').doc(cashier).set({
  name: 'Suresh', email: 'cashier@demo.test', role: 'cashier', storeIds: ['main'], active: true,
});
await db.doc(`users/${owner}`).set({ businessId: 'demo' });
await db.doc(`users/${cashier}`).set({ businessId: 'demo' });

const store = b.collection('stores').doc('main');
await store.set({
  name: 'Sri Lakshmi Stores, Kukatpally', address: 'KPHB Colony, Hyderabad', phone: '9876543210',
  gstin: '', upiId: 'srilakshmi@upi', receiptFooter: 'ధన్యవాదాలు! మళ్లీ రండి.',
});
await b.collection('stores').doc('second').set({
  name: 'Sri Lakshmi Stores, Miyapur', address: 'Miyapur, Hyderabad', phone: '9876500000',
  gstin: '', upiId: '', receiptFooter: '',
});

const products = [
  ['rice', 'Sona Masoori Rice', 'సోనా మసూరి బియ్యం', 'Grains', 'kg', 6200, 5400, 80000, 20000],
  ['toor', 'Toor Dal', 'కంది పప్పు', 'Pulses', 'kg', 14000, 12200, 25000, 10000],
  ['oil', 'Sunflower Oil', 'పొద్దుతిరుగుడు నూనె', 'Oil', 'litre', 16500, 14800, 18000, 5000],
  ['sugar', 'Sugar', 'చక్కెర', 'Essentials', 'kg', 4600, 4100, 40000, 10000],
  ['salt', 'Iodised Salt', 'ఉప్పు', 'Essentials', 'packet', 2800, 2200, 3000, 5000],
  ['soap', 'Bath Soap', 'స్నానపు సబ్బు', 'Personal', 'piece', 4500, 3700, 60000, 12000],
  ['milk', 'Milk Packet', 'పాల ప్యాకెట్', 'Dairy', 'packet', 3300, 3000, 2000, 10000],
];
for (const [id, name, nameTe, category, unit, pricePaise, costPaise, stockMilli, lowStockMilli] of products) {
  await store.collection('products').doc(id).set({
    name, nameTe, barcode: '', category, unit, pricePaise, costPaise, stockMilli, lowStockMilli, active: true,
  });
}

const addDues = async (id, name, phone, balancePaise, daysUntilDue) => {
  await store.collection('customers').doc(id).set({
    name, phone, address: '', creditLimitPaise: 500000, balancePaise, archived: false,
    dueDate: Timestamp.fromMillis(Date.now() + daysUntilDue * 86400000),
  });
  await store.collection('khata').add({
    customerId: id, kind: 'purchase', amountPaise: balancePaise, method: 'credit', billId: null,
    note: 'Opening balance', reversesId: null, at: Timestamp.now(), byUid: owner, byName: 'Lakshmi',
    createdAt: FieldValue.serverTimestamp(),
  });
};
await addDues('ravi', 'Ravi Kumar', '9876543211', 245000, -3);
await addDues('padma', 'Padma', '9876543212', 87500, 5);

const pad = (n) => String(n).padStart(2, '0');
for (let i = 0; i < 30; i++) {
  const d = new Date(Date.now() - i * 86400000);
  const key = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const sales = 1500000 + ((i * 7919) % 900000);
  const cash = Math.round(sales * 0.5);
  const upi = Math.round(sales * 0.35);
  await store.collection('days').doc(key).set({
    dayKey: key, salesPaise: sales, discountPaise: 0, billCount: 40 + (i % 17),
    cogsPaise: Math.round(sales * 0.86), cashSalesPaise: cash, upiSalesPaise: upi,
    creditSalesPaise: sales - cash - upi, collectionCashPaise: 40000, collectionUpiPaise: 15000,
    expensePaise: 60000, expenseCashPaise: 60000, expenseUpiPaise: 0, purchasePaise: 0,
    supplierCashPaise: 0, supplierUpiPaise: 0,
    items: {
      rice: { q: 40000, r: Math.round(sales * 0.6), c: Math.round(sales * 0.52) },
      oil: { q: 12000, r: Math.round(sales * 0.4), c: Math.round(sales * 0.34) },
    },
  });
}

await store.collection('suppliers').doc('wholesale').set({
  name: 'Balaji Wholesale', phone: '9876543220', address: 'Begum Bazaar', gstin: '', balancePaise: 1250000, archived: false,
});

console.log('Seeded. Sign in as owner@demo.test or cashier@demo.test; password is in this file.');
process.exit(0);
