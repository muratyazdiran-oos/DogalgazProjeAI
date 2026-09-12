import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../backend/server.js', import.meta.url), 'utf8');

test('v1.9 API and critical production routes are present', () => {
  assert.match(source, /const apiVersion = "1\.9\.0"/);
  assert.match(source, /\/v1\/projects\/analyze-video/);
  assert.match(source, /\/v1\/team-projects\/sync-batch/);
  assert.match(source, /\/v1\/teams\/:id\/dashboard/);
  assert.match(source, /\/v1\/auth\/logout/);
});

test('team dashboard enforces authentication and membership', () => {
  const line = source.split('\n').find(v => v.includes('/v1/teams/:id/dashboard')) ?? '';
  assert.match(line, /requireTeamAuth/);
  assert.match(source, /Takım üyeliği gerekli/);
});
