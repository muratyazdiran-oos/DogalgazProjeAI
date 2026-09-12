import express from "express";
import multer from "multer";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import pg from "pg";
import { GoogleGenAI } from "@google/genai";

const apiKey = process.env.GEMINI_API_KEY?.trim();
if (!apiKey) { console.error("GEMINI_API_KEY eksik."); process.exit(1); }
const model = process.env.GEMINI_MODEL?.trim() || "gemini-3.8-flash";
const maxVideoMB = Math.max(25, Math.min(Number(process.env.MAX_VIDEO_MB || 500), 1024));
const allowedOrigins = (process.env.ALLOWED_ORIGINS || "").split(",").map(v=>v.trim()).filter(Boolean);
const appApiToken = process.env.APP_API_TOKEN?.trim() || "";
const teamAuthSecret = process.env.TEAM_AUTH_SECRET?.trim() || "";
const databaseURL = process.env.DATABASE_URL?.trim() || "";
const isProduction = process.env.NODE_ENV === "production";
const apiVersion = "2.1.0";
const uploadDir = path.join(os.tmpdir(), "gas-ai"); fs.mkdirSync(uploadDir,{recursive:true});
const artifactStorageDir = process.env.ARTIFACT_STORAGE_DIR?.trim() || path.join(process.cwd(),"data","artifacts"); fs.mkdirSync(artifactStorageDir,{recursive:true});

if (isProduction && teamAuthSecret && !databaseURL) {
  console.error("Production ekip/bulut özelliği için DATABASE_URL (PostgreSQL) zorunludur.");
  process.exit(1);
}
if (isProduction && !appApiToken) {
  console.error("Production AI endpoint için APP_API_TOKEN zorunludur.");
  process.exit(1);
}

let pool = null;
const migrations = [
  { version: 1, sql: `
    CREATE TABLE IF NOT EXISTS users (email TEXT PRIMARY KEY, name TEXT NOT NULL, salt TEXT NOT NULL, password_hash TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS teams (id UUID PRIMARY KEY, name TEXT NOT NULL, owner_email TEXT NOT NULL REFERENCES users(email), created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS team_members (team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE, email TEXT NOT NULL REFERENCES users(email) ON DELETE CASCADE, role TEXT NOT NULL, PRIMARY KEY(team_id,email));
    CREATE TABLE IF NOT EXISTS projects (id UUID PRIMARY KEY, owner_email TEXT NOT NULL REFERENCES users(email), team_id UUID NULL REFERENCES teams(id), version INTEGER NOT NULL DEFAULT 1, project JSONB NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS idx_projects_team ON projects(team_id);
  `},
  { version: 2, sql: `
    CREATE TABLE IF NOT EXISTS revoked_tokens (jti UUID PRIMARY KEY, expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS idx_revoked_tokens_exp ON revoked_tokens(expires_at);
    CREATE TABLE IF NOT EXISTS audit_log (id BIGSERIAL PRIMARY KEY, actor_email TEXT, action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT, request_id TEXT, metadata JSONB, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(entity_type, entity_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS project_versions (project_id UUID NOT NULL, version INTEGER NOT NULL, project JSONB NOT NULL, saved_by TEXT, saved_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(project_id,version));
  `},
  { version: 3, sql: `
    CREATE TABLE IF NOT EXISTS project_artifacts (
      remote_id UUID PRIMARY KEY,
      project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      file_name TEXT NOT NULL,
      sha256 TEXT NOT NULL,
      byte_count BIGINT NOT NULL,
      storage_path TEXT NOT NULL,
      uploaded_by TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS idx_project_artifacts_project ON project_artifacts(project_id, created_at DESC);
  `}
];
async function runMigrations(db) {
  await db.query("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())");
  for (const m of migrations) {
    const { rows } = await db.query("SELECT 1 FROM schema_migrations WHERE version=$1", [m.version]);
    if (rows.length) continue;
    const client = await db.connect();
    try { await client.query("BEGIN"); await client.query(m.sql); await client.query("INSERT INTO schema_migrations(version) VALUES($1)",[m.version]); await client.query("COMMIT"); }
    catch (e) { await client.query("ROLLBACK"); throw e; } finally { client.release(); }
  }
}
if (databaseURL) {
  pool = new pg.Pool({ connectionString: databaseURL, ssl: process.env.PGSSL === "0" ? false : { rejectUnauthorized: process.env.PGSSL_REJECT_UNAUTHORIZED === "1" } });
  await runMigrations(pool);
}

function passwordHash(password,saltHex){return crypto.scryptSync(password,Buffer.from(saltHex,"hex"),64).toString("hex");}
function safeEmail(v){return String(v||"").trim().toLowerCase();}
function createTeamToken(email){const payload=Buffer.from(JSON.stringify({email,jti:crypto.randomUUID(),exp:Date.now()+7*86400000})).toString("base64url");const sig=crypto.createHmac("sha256",teamAuthSecret).update(payload).digest("base64url");return `${payload}.${sig}`;}
function verifyTeamToken(token){if(!teamAuthSecret||!token)return null;const[p,s]=token.split(".");if(!p||!s)return null;const e=crypto.createHmac("sha256",teamAuthSecret).update(p).digest("base64url");try{if(!crypto.timingSafeEqual(Buffer.from(s),Buffer.from(e)))return null;}catch{return null;}try{const d=JSON.parse(Buffer.from(p,"base64url").toString("utf8"));return d.exp>Date.now()?d:null;}catch{return null;}}
async function requireTeamAuth(req,res,next){try{if(!pool)return res.status(503).json({error:"Ekip/bulut veritabanı yapılandırılmadı."});const a=req.get("authorization")||"";const raw=a.startsWith("Bearer ")?a.slice(7):"";const d=verifyTeamToken(raw);if(!d)return res.status(401).json({error:"Ekip oturumu gerekli."});if(d.jti){const {rows}=await pool.query("SELECT 1 FROM revoked_tokens WHERE jti=$1 AND expires_at>now()",[d.jti]);if(rows.length)return res.status(401).json({error:"Oturum sonlandırılmış."});}req.teamUser=d.email;req.teamToken=d;req.rawTeamToken=raw;next();}catch(e){next(e);}}
async function teamRole(teamID,email){if(!teamID)return null;const {rows}=await pool.query("SELECT role FROM team_members WHERE team_id=$1 AND email=$2",[teamID,email]);return rows[0]?.role||null;}
async function canRead(record,email){if(record.owner_email===email)return true;return Boolean(await teamRole(record.team_id,email));}
async function canWrite(record,email){if(record.owner_email===email)return true;return ["owner","engineer","technician"].includes(await teamRole(record.team_id,email));}
async function audit(req,action,entityType,entityId=null,metadata={}){if(!pool)return;try{await pool.query("INSERT INTO audit_log(actor_email,action,entity_type,entity_id,request_id,metadata) VALUES($1,$2,$3,$4,$5,$6)",[req.teamUser||null,action,entityType,entityId,req.requestId||null,metadata]);}catch(e){console.error(`[${req.requestId}] audit`,e?.message||e);}}

const app=express(); app.disable("x-powered-by"); if(process.env.TRUST_PROXY==="1")app.set("trust proxy",1);
app.use((req,res,next)=>{const id=req.get("x-request-id")?.slice(0,100)||crypto.randomUUID();res.setHeader("X-Request-ID",id);req.requestId=id;next();});
app.use(helmet({crossOriginResourcePolicy:false})); app.use(cors({origin:allowedOrigins.length?allowedOrigins:false})); app.use(rateLimit({windowMs:60000,limit:60,standardHeaders:"draft-8",legacyHeaders:false})); app.use(express.json({limit:"2mb"}));
const authLimiter=rateLimit({windowMs:15*60*1000,limit:8,standardHeaders:"draft-8",legacyHeaders:false,message:{error:"Çok fazla giriş denemesi. Daha sonra tekrar deneyin."}});
function requireAppToken(req,res,next){if(!appApiToken)return next();if((req.get("authorization")||"")!==`Bearer ${appApiToken}`)return res.status(401).json({error:"Yetkisiz istek."});next();}

const upload=multer({dest:uploadDir,limits:{fileSize:maxVideoMB*1024*1024,files:1,fields:2,fieldSize:4096,parts:3},fileFilter:(_,f,cb)=>{const ok=["video/mp4","video/quicktime","video/x-m4v"].includes(f.mimetype);cb(ok?null:new Error("Desteklenmeyen video biçimi."),ok);}});
const artifactUpload=multer({dest:uploadDir,limits:{fileSize:1024*1024*1024,files:1,fields:4,fieldSize:8192,parts:6}});
const ai=new GoogleGenAI({apiKey});
const schema={type:"object",additionalProperties:false,properties:{confidence:{type:"number",minimum:0,maximum:1},notes:{type:"array",items:{type:"string"}},rooms:{type:"array",items:{type:"object",additionalProperties:false,properties:{id:{type:"string"},name:{type:"string"},polygon:{type:"array",items:{$ref:"#/$defs/point"}}},required:["id","name","polygon"]}},pipes:{type:"array",items:{type:"object",additionalProperties:false,properties:{id:{type:"string"},start:{$ref:"#/$defs/point"},end:{$ref:"#/$defs/point"},diameterMM:{type:"integer",minimum:0},lengthMeters:{type:"number",minimum:0},aiConfidence:{type:"number",minimum:0,maximum:1},requiresReview:{type:"boolean"}},required:["id","start","end","diameterMM","lengthMeters","aiConfidence","requiresReview"]}},devices:{type:"array",items:{type:"object",additionalProperties:false,properties:{id:{type:"string"},type:{type:"string",enum:["meter","boiler","stove","valve","vent"]},position:{$ref:"#/$defs/point"},label:{type:"string"},capacityKW:{anyOf:[{type:"number",minimum:0},{type:"null"}]},aiConfidence:{type:"number",minimum:0,maximum:1},requiresReview:{type:"boolean"},brand:{anyOf:[{type:"string"},{type:"null"}]},model:{anyOf:[{type:"string"},{type:"null"}]},modelConfidence:{anyOf:[{type:"number",minimum:0,maximum:1},{type:"null"}]},modelCandidates:{type:"array",items:{type:"object",additionalProperties:false,properties:{brand:{type:"string"},model:{type:"string"},confidence:{type:"number",minimum:0,maximum:1}},required:["brand","model","confidence"]}},videoTimeSeconds:{anyOf:[{type:"number",minimum:0},{type:"null"}]},videoBoundingBox:{anyOf:[{type:"object",additionalProperties:false,properties:{x:{type:"number",minimum:0,maximum:1},y:{type:"number",minimum:0,maximum:1},width:{type:"number",minimum:0,maximum:1},height:{type:"number",minimum:0,maximum:1}},required:["x","y","width","height"]},{type:"null"}]}},required:["id","type","position","label","capacityKW","aiConfidence","requiresReview","brand","model","modelConfidence","modelCandidates","videoTimeSeconds","videoBoundingBox"]}},dimensions:{type:"array",items:{type:"object",additionalProperties:false,properties:{id:{type:"string"},start:{$ref:"#/$defs/point"},end:{$ref:"#/$defs/point"},meters:{type:"number",minimum:0}},required:["id","start","end","meters"]}},materialSummary:{type:"object",additionalProperties:false,properties:{totalPipeMeters:{type:"number",minimum:0},valves:{type:"integer",minimum:0},elbows:{type:"integer",minimum:0},tees:{type:"integer",minimum:0},vents:{type:"integer",minimum:0}},required:["totalPipeMeters","valves","elbows","tees","vents"]}},required:["confidence","notes","rooms","pipes","devices","dimensions","materialSummary"],$defs:{point:{type:"object",additionalProperties:false,properties:{x:{type:"number",minimum:0,maximum:1},y:{type:"number",minimum:0,maximum:1}},required:["x","y"]}}};
const prompt=`Bir doğalgaz tesisatı keşif videosunu analiz et ve yalnızca videoda görülebilen verilere dayalı 2B proje TASLAĞI üret. Sayaç, kombi, ocak, vana, menfez, görülebilen borular ve oda sınırlarını tespit et. Koordinatlar 0..1 normalize olsun. Kombi/ocak etiketinde marka veya model okunuyorsa brand/model alanlarına yaz; emin değilsen null kullan. Model için en fazla 3 olası aday üret ve her adayda confidence ver. Logo/etiket görünmüyorsa marka/model UYDURMA. capacityKW yalnız etiketten güvenilir okunuyorsa doldur; model adına bakıp tahmin etme. Her boru ve cihaz için aiConfidence ve requiresReview üret. Her cihaz için mümkünse cihazın en net görüldüğü videoTimeSeconds zamanını ve o karedeki 0..1 normalize videoBoundingBox alanını ver; güvenilir değilse null kullan. AI marka/model önerisi mühendis veya kullanıcı onayı olmadan resmî hesapta kesin kabul edilmemelidir. Bu veri resmî proje değildir; mühendis kontrolü gerekir.`;

app.get("/health",(_,res)=>res.json({ok:true,version:apiVersion,model,maxVideoMB,authRequired:Boolean(appApiToken),teamAuthEnabled:Boolean(teamAuthSecret),postgres:Boolean(pool)}));
app.get("/ready",async(_,res)=>{try{if(pool)await pool.query("SELECT 1");res.json({ready:true,version:apiVersion});}catch{res.status(503).json({ready:false});}});

app.post("/v1/auth/register",authLimiter,async(req,res)=>{if(!teamAuthSecret||!pool)return res.status(503).json({error:"Ekip hesabı yapılandırılmadı."});const email=safeEmail(req.body?.email),password=String(req.body?.password||""),name=String(req.body?.name||"").trim();if(!email.includes("@")||password.length<8||name.length<2)return res.status(400).json({error:"Geçerli e-posta, ad ve en az 8 karakter şifre gerekli."});const salt=crypto.randomBytes(16).toString("hex");try{await pool.query("INSERT INTO users(email,name,salt,password_hash) VALUES($1,$2,$3,$4)",[email,name,salt,passwordHash(password,salt)]);res.json({token:createTeamToken(email)});}catch(e){if(e.code==="23505")return res.status(409).json({error:"Bu e-posta kayıtlı."});throw e;}});
app.post("/v1/auth/login",authLimiter,async(req,res)=>{if(!teamAuthSecret||!pool)return res.status(503).json({error:"Ekip hesabı yapılandırılmadı."});const email=safeEmail(req.body?.email),password=String(req.body?.password||"");const {rows}=await pool.query("SELECT salt,password_hash FROM users WHERE email=$1",[email]);const u=rows[0];if(!u)return res.status(401).json({error:"E-posta veya şifre hatalı."});const c=passwordHash(password,u.salt);let ok=false;try{ok=crypto.timingSafeEqual(Buffer.from(c,"hex"),Buffer.from(u.password_hash,"hex"));}catch{}if(!ok)return res.status(401).json({error:"E-posta veya şifre hatalı."});res.json({token:createTeamToken(email)});});
app.post("/v1/auth/logout",requireTeamAuth,async(req,res)=>{if(req.teamToken?.jti)await pool.query("INSERT INTO revoked_tokens(jti,expires_at) VALUES($1,to_timestamp($2/1000.0)) ON CONFLICT DO NOTHING",[req.teamToken.jti,req.teamToken.exp]);await audit(req,"logout","user",req.teamUser);res.json({ok:true});});
app.post("/v1/auth/change-password",authLimiter,requireTeamAuth,async(req,res)=>{const current=String(req.body?.currentPassword||""),next=String(req.body?.newPassword||"");if(next.length<10)return res.status(400).json({error:"Yeni şifre en az 10 karakter olmalı."});const {rows}=await pool.query("SELECT salt,password_hash FROM users WHERE email=$1",[req.teamUser]);const u=rows[0],c=passwordHash(current,u.salt);let ok=false;try{ok=crypto.timingSafeEqual(Buffer.from(c,"hex"),Buffer.from(u.password_hash,"hex"));}catch{}if(!ok)return res.status(401).json({error:"Mevcut şifre hatalı."});const salt=crypto.randomBytes(16).toString("hex");await pool.query("UPDATE users SET salt=$1,password_hash=$2 WHERE email=$3",[salt,passwordHash(next,salt),req.teamUser]);await audit(req,"change_password","user",req.teamUser);res.json({ok:true});});
app.post("/v1/teams",requireTeamAuth,async(req,res)=>{const name=String(req.body?.name||"").trim();if(name.length<2)return res.status(400).json({error:"Takım adı gerekli."});const id=crypto.randomUUID();const client=await pool.connect();try{await client.query("BEGIN");await client.query("INSERT INTO teams(id,name,owner_email) VALUES($1,$2,$3)",[id,name,req.teamUser]);await client.query("INSERT INTO team_members(team_id,email,role) VALUES($1,$2,'owner')",[id,req.teamUser]);await client.query("COMMIT");res.json({id,name});}catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}});
app.post("/v1/teams/:id/members",requireTeamAuth,async(req,res)=>{const role=String(req.body?.role||"viewer"),email=safeEmail(req.body?.email);if(!["owner","engineer","technician","viewer"].includes(role))return res.status(400).json({error:"Rol geçersiz."});const {rows}=await pool.query("SELECT owner_email FROM teams WHERE id=$1",[req.params.id]);if(rows[0]?.owner_email!==req.teamUser)return res.status(403).json({error:"Takım yöneticisi gerekli."});try{await pool.query("INSERT INTO team_members(team_id,email,role) VALUES($1,$2,$3) ON CONFLICT(team_id,email) DO UPDATE SET role=EXCLUDED.role",[req.params.id,email,role]);res.json({ok:true});}catch(e){if(e.code==="23503")return res.status(404).json({error:"Kullanıcı önce hesap oluşturmalı."});throw e;}});
app.get("/v1/teams/:id/dashboard",requireTeamAuth,async(req,res)=>{
  const teamID=req.params.id;
  const role=await teamRole(teamID,req.teamUser);
  if(!role)return res.status(403).json({error:"Takım üyeliği gerekli."});
  const {rows:teams}=await pool.query("SELECT name FROM teams WHERE id=$1",[teamID]);
  if(!teams[0])return res.status(404).json({error:"Takım bulunamadı."});
  const {rows:members}=await pool.query("SELECT tm.email,tm.role,u.name FROM team_members tm JOIN users u ON u.email=tm.email WHERE tm.team_id=$1 ORDER BY tm.role,tm.email",[teamID]);
  const {rows:projects}=await pool.query("SELECT id,version,owner_email,updated_at,COALESCE(project->>'name','Proje') AS name,COALESCE(project->'projectWorkflow'->>'status','draft') AS status,project->'projectWorkflow'->>'assignedToEmail' AS assigned_to_email,project->'projectWorkflow'->>'dueDate' AS due_date FROM projects WHERE team_id=$1 ORDER BY updated_at DESC LIMIT 100",[teamID]);
  const countsByRole={}; for(const m of members) countsByRole[m.role]=(countsByRole[m.role]||0)+1;
  const countsByStatus={}; for(const p of projects) countsByStatus[p.status]=(countsByStatus[p.status]||0)+1;
  await audit(req,"dashboard_view","team",teamID,{memberCount:members.length,projectCount:projects.length});
  res.json({teamName:teams[0].name,members,projects:projects.map(p=>({id:p.id,name:p.name,version:p.version,updatedAt:p.updated_at,ownerEmail:p.owner_email,status:p.status,assignedToEmail:p.assigned_to_email,dueDate:p.due_date})),countsByRole,countsByStatus});
});


app.put("/v1/team-projects/:id",requireTeamAuth,async(req,res)=>{const envelope=req.body||{},project=envelope.project,expectedVersion=Number.isInteger(envelope.expectedVersion)?envelope.expectedVersion:null;if(!project||String(project.id||"").toLowerCase()!==req.params.id.toLowerCase())return res.status(400).json({error:"Proje kimliği uyuşmuyor."});const id=req.params.id.toLowerCase(),teamID=project?.collaboration?.teamID||null;const {rows}=await pool.query("SELECT * FROM projects WHERE id=$1",[id]);const existing=rows[0];if(existing&&!await canWrite(existing,req.teamUser))return res.status(403).json({error:"Projeyi düzenleme yetkin yok."});if(teamID&&!await teamRole(teamID,req.teamUser))return res.status(403).json({error:"Takım üyeliği gerekli."});if(existing){if(expectedVersion===null||expectedVersion!==existing.version)return res.status(409).json({error:"Buluttaki proje daha yeni.",currentVersion:existing.version});const next=existing.version+1;const client=await pool.connect();try{await client.query("BEGIN");await client.query("INSERT INTO project_versions(project_id,version,project,saved_by) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING",[id,existing.version,existing.project,req.teamUser]);const update=await client.query("UPDATE projects SET project=$1,team_id=$2,version=$3,updated_at=now() WHERE id=$4 AND version=$5 RETURNING version",[project,teamID,next,id,existing.version]);if(!update.rowCount){await client.query("ROLLBACK");return res.status(409).json({error:"Senkronizasyon çakışması."});}await client.query("COMMIT");await audit(req,"update","project",id,{version:next});return res.json({ok:true,version:next});}catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}}await pool.query("INSERT INTO projects(id,owner_email,team_id,version,project) VALUES($1,$2,$3,1,$4)",[id,req.teamUser,teamID,project]);await audit(req,"create","project",id,{version:1});res.json({ok:true,version:1});});
app.post("/v1/team-projects/sync-batch",requireTeamAuth,async(req,res)=>{const items=Array.isArray(req.body?.items)?req.body.items:[];if(items.length<1||items.length>30)return res.status(400).json({error:"1-30 proje gerekli."});const results=[];for(const item of items){const project=item?.project,id=String(project?.id||"").toLowerCase(),expectedVersion=Number.isInteger(item?.expectedVersion)?item.expectedVersion:null;if(!id){results.push({ok:false,error:"project id missing"});continue;}const {rows}=await pool.query("SELECT * FROM projects WHERE id=$1",[id]);const existing=rows[0];if(existing&&!await canWrite(existing,req.teamUser)){results.push({id,ok:false,status:403});continue;}if(existing&&(expectedVersion===null||expectedVersion!==existing.version)){results.push({id,ok:false,status:409,currentVersion:existing.version});continue;}if(existing){const next=existing.version+1;const client=await pool.connect();try{await client.query("BEGIN");await client.query("INSERT INTO project_versions(project_id,version,project,saved_by) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING",[id,existing.version,existing.project,req.teamUser]);const update=await client.query("UPDATE projects SET project=$1,version=$2,updated_at=now() WHERE id=$3 AND version=$4 RETURNING version",[project,next,id,existing.version]);if(!update.rowCount){await client.query("ROLLBACK");results.push({id,ok:false,status:409,currentVersion:existing.version});continue;}await client.query("COMMIT");results.push({id,ok:true,version:next});}catch(e){await client.query("ROLLBACK");throw e;}finally{client.release();}}else{const teamID=project?.collaboration?.teamID||null;if(teamID&&!await teamRole(teamID,req.teamUser)){results.push({id,ok:false,status:403,error:"team membership required"});continue;}await pool.query("INSERT INTO projects(id,owner_email,team_id,version,project) VALUES($1,$2,$3,1,$4)",[id,req.teamUser,teamID,project]);results.push({id,ok:true,version:1});}}await audit(req,"sync_batch","project",null,{count:items.length});res.json({results});});
app.get("/v1/team-projects/:id",requireTeamAuth,async(req,res)=>{const {rows}=await pool.query("SELECT * FROM projects WHERE id=$1",[req.params.id.toLowerCase()]);const r=rows[0];if(!r)return res.status(404).json({error:"Proje bulunamadı."});if(!await canRead(r,req.teamUser))return res.status(403).json({error:"Projeyi görme yetkin yok."});res.json({project:r.project,version:r.version});});

app.post("/v1/team-projects/:id/artifacts",requireTeamAuth,artifactUpload.single("artifact"),async(req,res)=>{
  const id=req.params.id.toLowerCase();
  if(!req.file)return res.status(400).json({error:"Artifact dosyası gerekli."});
  const {rows}=await pool.query("SELECT * FROM projects WHERE id=$1",[id]);
  const project=rows[0];
  if(!project||!await canWrite(project,req.teamUser)){fs.unlink(req.file.path,()=>{});return res.status(project?403:404).json({error:project?"Yetki yok.":"Proje bulunamadı."});}
  const kind=String(req.body?.kind||"artifact").slice(0,40);
  const fileName=path.basename(String(req.body?.fileName||req.file.originalname||"artifact.bin")).slice(0,180);
  const remoteID=crypto.randomUUID();
  const dir=path.join(artifactStorageDir,id);fs.mkdirSync(dir,{recursive:true});
  const target=path.join(dir,remoteID);
  const data=await fs.promises.readFile(req.file.path);
  const sha256=crypto.createHash("sha256").update(data).digest("hex");
  await fs.promises.rename(req.file.path,target);
  await pool.query("INSERT INTO project_artifacts(remote_id,project_id,kind,file_name,sha256,byte_count,storage_path,uploaded_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",[remoteID,id,kind,fileName,sha256,data.length,target,req.teamUser]);
  await audit(req,"artifact_upload","project",id,{remoteID,kind,sha256,byteCount:data.length});
  res.json({remoteID,kind,fileName,sha256,byteCount:data.length,uploadedAt:new Date().toISOString()});
});
app.get("/v1/team-projects/:id/artifacts",requireTeamAuth,async(req,res)=>{
  const id=req.params.id.toLowerCase();
  const {rows:p}=await pool.query("SELECT * FROM projects WHERE id=$1",[id]);
  const project=p[0];
  if(!project)return res.status(404).json({error:"Proje bulunamadı."});
  if(!await canRead(project,req.teamUser))return res.status(403).json({error:"Yetki yok."});
  const {rows}=await pool.query('SELECT remote_id AS "remoteID",kind,file_name AS "fileName",sha256,byte_count AS "byteCount",created_at AS "uploadedAt" FROM project_artifacts WHERE project_id=$1 ORDER BY created_at DESC',[id]);
  res.json({artifacts:rows});
});
app.get("/v1/team-projects/:id/artifacts/:remoteID",requireTeamAuth,async(req,res)=>{
  const id=req.params.id.toLowerCase();
  const {rows:p}=await pool.query("SELECT * FROM projects WHERE id=$1",[id]);
  const project=p[0];
  if(!project)return res.status(404).end();
  if(!await canRead(project,req.teamUser))return res.status(403).end();
  const {rows}=await pool.query("SELECT * FROM project_artifacts WHERE project_id=$1 AND remote_id=$2",[id,req.params.remoteID]);
  const a=rows[0];
  if(!a||!fs.existsSync(a.storage_path))return res.status(404).end();
  res.setHeader("X-Artifact-SHA256",a.sha256);
  res.setHeader("Content-Disposition",'attachment; filename="'+encodeURIComponent(a.file_name)+'"');
  fs.createReadStream(a.storage_path).pipe(res);
});

app.get("/v1/team-projects/:id/versions",requireTeamAuth,async(req,res)=>{const id=req.params.id.toLowerCase();const {rows:projects}=await pool.query("SELECT * FROM projects WHERE id=$1",[id]);const r=projects[0];if(!r)return res.status(404).json({error:"Proje bulunamadı."});if(!await canRead(r,req.teamUser))return res.status(403).json({error:"Projeyi görme yetkin yok."});const {rows}=await pool.query("SELECT version,saved_by,saved_at FROM project_versions WHERE project_id=$1 ORDER BY version DESC LIMIT 50",[id]);res.json({currentVersion:r.version,versions:rows});});

app.post("/v1/projects/analyze-video",requireAppToken,upload.single("video"),async(req,res)=>{if(!req.file)return res.status(400).json({error:"Video gerekli."});let remoteFile;try{remoteFile=await ai.files.upload({file:req.file.path,config:{mimeType:req.file.mimetype||"video/mp4"}});let current=await ai.files.get({name:remoteFile.name});const started=Date.now();while(current.state==="PROCESSING"){if(Date.now()-started>9*60000)throw new Error("Video işleme zaman aşımına uğradı.");await new Promise(r=>setTimeout(r,3000));current=await ai.files.get({name:remoteFile.name});}if(current.state==="FAILED")throw new Error("Video işlenemedi.");const response=await ai.interactions.create({model,input:[{type:"text",text:prompt},{type:"video",uri:current.uri,mime_type:current.mimeType}],response_format:{type:"text",mime_type:"application/json",schema}});res.json(JSON.parse(response.output_text));}catch(error){console.error(`[${req.requestId}]`,error);const raw=error?.message||"AI analizi başarısız.";res.status(500).json({error:isProduction?"AI analizi şu anda tamamlanamadı.":raw,requestId:req.requestId});}finally{if(remoteFile?.name)try{await ai.files.delete({name:remoteFile.name});}catch{}if(req.file?.path)fs.unlink(req.file.path,()=>{});}});
app.use((error,_req,res,_next)=>{if(error instanceof multer.MulterError&&error.code==="LIMIT_FILE_SIZE")return res.status(413).json({error:`Video en fazla ${maxVideoMB} MB olabilir.`});console.error(error);res.status(400).json({error:error?.message||"Geçersiz istek."});});
app.use((error,req,res,_next)=>{console.error(`[${req.requestId}]`,error);res.status(500).json({error:"Sunucu hatası.",requestId:req.requestId});});

if(pool)await pool.query("DELETE FROM revoked_tokens WHERE expires_at<=now()");
const server=app.listen(Number(process.env.PORT||8080),()=>console.log(`API ${apiVersion} ready • ${model}`));
function shutdown(signal){console.log(`${signal} received; shutting down.`);server.close(async()=>{if(pool)await pool.end();process.exit(0);});setTimeout(()=>process.exit(1),10000).unref();}
process.on("SIGTERM",()=>shutdown("SIGTERM")); process.on("SIGINT",()=>shutdown("SIGINT"));
