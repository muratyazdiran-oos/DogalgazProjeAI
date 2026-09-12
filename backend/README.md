# DogalgazProjeAI Backend v1.3

## Yerel kontrol
```bash
cp .env.example .env
npm install
npm run check
npm start
```

## Production
- `GEMINI_API_KEY`: zorunlu
- `GEMINI_MODEL`: varsayılan `gemini-3.8-flash`
- `APP_API_TOKEN`: mobil AI endpointi için güçlü Bearer token
- `TEAM_AUTH_SECRET`: ekip hesabı token imzası
- `DATABASE_URL`: ekip/bulut kullanılıyorsa production'da zorunlu PostgreSQL bağlantısı
- `PGSSL=1`: barındırma sağlayıcısının TLS ayarına göre kullanılır

Sunucu açılışta gerekli PostgreSQL tablolarını oluşturur. Proje kayıtlarında `version` alanıyla optimistic locking uygulanır; eski istemci güncel projeyi sessizce ezemez ve `409 Conflict` alır.

## Endpointler
- `GET /health`
- `GET /ready`
- `POST /v1/projects/analyze-video`
- `POST /v1/auth/register`, `POST /v1/auth/login`
- `POST /v1/teams`, `POST /v1/teams/:id/members`
- `PUT/GET /v1/team-projects/:id`

Mobil AI analizinde müşteri adı/adresi gönderilmez. Video analiz sonrası Gemini dosya servisinden ve backend geçici diskinden silinir.


## v1.4 production notları
- PostgreSQL şeması `schema_migrations` ile sürümlenir.
- Auth uçlarında ayrı rate-limit bulunur.
- Oturumlar JTI ile iptal edilebilir (`/v1/auth/logout`).
- Şifre değiştirme: `/v1/auth/change-password`.
- `audit_log` proje/hesap işlemlerini kaydeder.
- `project_versions` güncellemeden önce önceki bulut proje sürümünü saklar.
- `scripts/backup-postgres.sh` PostgreSQL `pg_dump` örneğidir; üretimde yönetilen snapshot/PITR ayrıca kullanılmalıdır.
