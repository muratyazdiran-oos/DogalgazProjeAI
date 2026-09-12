# DogalgazProjeAI v2.0 Final Candidate

SwiftUI iOS uygulaması + Node/Gemini backend. Video analizinden 2B tesisat taslağı, LiDAR/manuel gerçek ölçü, cihaz marka-model adayları, hidrolik ön kontrol, mühendislik doğrulaması, PDF/DXF/JSON çıktı, revizyon, teklif, onay, offline saha akışı ve isteğe bağlı PostgreSQL ekip/bulut senkronizasyonu içerir.

## v2.0 öne çıkanlar
- Engel duyarlı A* rota taslağı: oda sınırını korur ve RoomPlan açıklıkları etrafından kaçınır.
- 0-100 proje kalite puanı.
- Son revizyonlar arası fark özeti.
- Offline senkron ve özel cihaz kataloğu için Application Support dosya deposu.
- Gelişmiş ticari teklif alanları ve PDF teklifi.
- AI marka/model adayı + katalog eşleme + kullanıcı/mühendis doğrulaması.
- Gerçek mm ölçekli AutoCAD/GasLine DXF; GasLine native kapalı formatı değildir.

## Güvenlik / mühendislik sınırı
Uygulama resmî dağıtım şirketi onayı vermez. Kural değerleri yalnız doğrulanmış profil olarak girilmelidir. AI model seçimi ve rota önerileri kullanıcı/mühendis doğrulaması olmadan kesin kabul edilmez. PDF/DXF çıktıları yetkili mühendis incelemesi olmadan resmî proje olarak kullanılmamalıdır.

## Backend
`backend/.env.example` temel alınır. AI için `GEMINI_API_KEY`; ekip/bulut için `TEAM_AUTH_SECRET` ve production kullanımında PostgreSQL gereklidir. HTTPS, yedekleme ve migration akışı korunur.

## Sürüm
- iOS: 2.0.0 (build 20)
- Backend API: 2.0.0
- Deployment target: iOS 17+


## v2.0
Uygulama içi ARKit saha video kaydı + kamera poz trajectory verisi, metre ölçekli 3B tesisat görünümü, firma dashboardu ve GitHub Actions iOS/backend CI eklendi.
