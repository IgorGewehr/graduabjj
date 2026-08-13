'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const testDirectory = path.resolve(__dirname, '..', 'test');
const testFiles = fs.readdirSync(testDirectory)
  .filter((name) => name.endsWith('.test.js'))
  .sort()
  .map((name) => path.join(testDirectory, name));

if (testFiles.length === 0) {
  console.error('No Node test files found in functions/test.');
  process.exit(1);
}

const result = spawnSync(process.execPath, ['--test', ...testFiles], {
  stdio: 'inherit',
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status == null ? 1 : result.status);
