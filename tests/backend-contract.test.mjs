import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../backend/server.js', import.meta.url), 'utf8');

test('v2.1 API and critical production routes are present', () => {
  assert.match(source, /const apiVersion = "2\\.1\\.0"/);
  for (const route of ['/v1/projects/analyze-video','/v1/team-projects/sync-batch','/v1/teams/:id/dashboard','/v1/auth/logout','/v1/auth/change-password']) assert.ok(source.includes(route));
});

test('team dashboard enforces authentication and membership', () => {
  const line = source.split('\n').find(v => v.includes('/v1/teams/:id/dashboard')) ?? '';
  assert.match(line, /requireTeamAuth/);
  assert.match(source, /Takım üyeliği gerekli/);
});

test('video upload is bounded and remote AI file is deleted', () => {
  assert.match(source, /fileSize:maxVideoMB\*1024\*1024/);
  assert.match(source, /ai\.files\.delete/);
  assert.match(source, /fs\.unlink/);
});

test('optimistic locking protects project updates', () => {
  assert.match(source, /WHERE id=\$4 AND version=\$5/);
  assert.match(source, /status\(409\)/);
});
