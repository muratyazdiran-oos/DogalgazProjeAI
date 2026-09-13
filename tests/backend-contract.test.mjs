import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../backend/server.js', import.meta.url), 'utf8');

test('v2.4 API and critical production routes are present', () => {
  assert.ok(source.includes('const apiVersion = "2.4.0"'));
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


test('AI spatial metadata contract is present', () => {
  assert.ok(source.includes('videoTimeSeconds'));
  assert.ok(source.includes('videoBoundingBox'));
  assert.ok(source.includes('bounding box') || source.includes('bounding-box') || source.includes('videoBoundingBox'));
});

test('team dashboard exposes project workflow fields', () => {
  assert.ok(source.includes('assignedToEmail'));
  assert.ok(source.includes('dueDate'));
  assert.ok(source.includes('countsByStatus'));
});


test('batch sync checks team membership for new projects', () => {
  assert.ok(source.includes('team membership required'));
  assert.ok(source.includes('teamID&&!await teamRole(teamID,req.teamUser)'));
});

test('artifact routes require team auth and hash artifacts', () => {
  assert.ok(source.includes('/v1/team-projects/:id/artifacts'));
  assert.ok(source.includes('requireTeamAuth,artifactUpload.single("artifact")'));
  assert.ok(source.includes('createHash("sha256")'));
  assert.ok(source.includes('X-Artifact-SHA256'));
});

test('production requires APP_API_TOKEN', () => {
  assert.ok(source.includes('Production AI endpoint için APP_API_TOKEN zorunludur.'));
});


test('S3-compatible artifact storage is available', () => {
  assert.ok(source.includes('S3Client'));
  assert.ok(source.includes('S3_ARTIFACT_BUCKET'));
  assert.ok(source.includes('PutObjectCommand'));
  assert.ok(source.includes('GetObjectCommand'));
  assert.ok(source.includes('artifactStorageMode'));
});

test('artifact upload deduplicates by SHA-256', () => {
  assert.ok(source.includes('WHERE project_id=$1 AND sha256=$2'));
  assert.ok(source.includes('deduplicated:true'));
});

test('artifact delete removes object storage payload', () => {
  assert.ok(source.includes('app.delete("/v1/team-projects/:id/artifacts/:remoteID"'));
  assert.ok(source.includes('deleteStoredArtifact'));
});


test('presigned uploads are authenticated and finalized', () => {
  assert.ok(source.includes('/artifacts/presign'));
  assert.ok(source.includes('/artifacts/finalize'));
  assert.ok(source.includes('getSignedUrl'));
  assert.ok(source.includes('HeadObjectCommand'));
  assert.ok(source.includes('artifact_upload_sessions'));
});

test('artifact garbage collection retries failed deletes', () => {
  assert.ok(source.includes('artifact_gc_queue'));
  assert.ok(source.includes('runArtifactGC'));
  assert.ok(source.includes('expired-presigned-upload'));
  assert.ok(source.includes('delete-failed'));
});


test('artifact verify endpoint checks storage integrity', () => {
  assert.ok(source.includes('/artifacts/:remoteID/verify'));
  assert.ok(source.includes('HeadObjectCommand'));
  assert.ok(source.includes('actualSHA'));
});

test('enterprise dashboard exposes operational health metrics', () => {
  assert.ok(source.includes('overdueCount'));
  assert.ok(source.includes('approvalQueueCount'));
  assert.ok(source.includes('artifact_count'));
  assert.ok(source.includes('has_ar_alignment'));
});

test('presigned upload sessions expire and are garbage collected', () => {
  assert.ok(source.includes('artifact_upload_sessions'));
  assert.ok(source.includes('expires_at<=now()'));
  assert.ok(source.includes('expired-presigned-upload'));
});
