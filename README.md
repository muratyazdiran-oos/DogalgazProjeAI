# DogalgazProjeAI v2.1 Final Candidate

SwiftUI iOS uygulaması + Node/Gemini backend. Video analizinden 2B tesisat taslağı, LiDAR/manuel gerçek ölçü, AR depth/trajectory, 3B tesisat, cihaz marka-model adayları, hidrolik ön kontrol, PDF/DXF/JSON çıktı, revizyon, teklif, onay ve ekip/bulut senkronizasyonu içerir.

## v2.1 öne çıkanlar
- Gerçek AR saha videosu + kamera pozu/intrinsics + örneklenmiş sceneDepth verisi.
- AI cihaz zaman/bounding-box çıktısını AR dünya koordinatına bağlama altyapısı.
- Boru başlangıç/bitiş kotu ve cihaz kotu; 3B görünüm ve DXF Z koordinatları.
- RoomPlan duvar/açıklıkları ve manuel kolon/şaft/baca/dolap/yasak bölge engelleri.
- Akıllı rota manuel engellerden de kaçınır.
- Doğrulanmış mühendislik limitlerinden ön boru çapı önerisi.
- OCR + QR/barkod cihaz etiketi okuma.
- Saha kanıtlarında SHA-256 bütünlük izi.
- AR kayıt kalite/tutarlılık analizi ve aktif oturumu koruyan temizlik.
- Firma dashboardu, PostgreSQL optimistic locking, audit ve offline sync.

## Güvenlik / mühendislik sınırı
Uygulama resmî dağıtım şirketi onayı vermez. Kural değerleri yalnız doğrulanmış profil olarak girilmelidir. AI cihaz/model, rota ve çap önerileri yetkili mühendis doğrulaması olmadan kesin/resmî kabul edilmez. GasLine entegrasyonu doğrulanmış katalog eşlemeleri + DXF aktarımıdır; kapalı native GasLine formatı taklit edilmez.

## Backend
`backend/.env.example` temel alınır. AI için `GEMINI_API_KEY`; ekip/bulut için `TEAM_AUTH_SECRET` ve production kullanımında PostgreSQL gereklidir. Secret değerleri repoya commit edilmemelidir.

## Sürüm
- iOS: 2.1.0 (build 21)
- Backend API: 2.1.0
- Deployment target: iOS 17+
