const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '../../notification-server/.env');
const envContent = fs.readFileSync(envPath, 'utf8');
const match = envContent.match(/FIREBASE_SERVICE_ACCOUNT_JSON=(.+)/);
if (!match) {
  console.error('Service account não encontrado');
  process.exit(1);
}

const serviceAccount = JSON.parse(match[1]);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function run() {
  console.log('=== COLEÇÃO: tenants ===');
  const snapTenants = await db.collection('tenants').get();
  snapTenants.forEach(doc => {
    console.log(`\nID: ${doc.id}`);
    console.log(JSON.stringify(doc.data(), null, 2));
  });

  console.log('\n=== COLEÇÃO: users ===');
  const snapUsers = await db.collection('users').get();
  snapUsers.forEach(doc => {
    console.log(`\nID: ${doc.id}`);
    console.log(JSON.stringify(doc.data(), null, 2));
  });
}

run();
