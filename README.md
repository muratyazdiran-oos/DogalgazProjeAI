# DogalgazProjeAI v2.2 Final Candidate

SwiftUI iOS uygulaması + Node/Gemini backend. Video analizinden 2B tesisat taslağı, RoomPlan/LiDAR gerçek ölçü, AR depth/trajectory, AR↔RoomPlan hizalama, 3B tesisat, mühendislik ön kontrolü, PDF/DXF, ekip/bulut ve kanıt artifact senkronizasyonu içerir.

## v2.2 öne çıkanlar
- AI cihaz bounding-box alanında median sceneDepth ile daha dayanıklı 3B AR konumu.
- İki fiziksel referans noktasıyla AR dünya koordinatı ↔ RoomPlan metre koordinatı similarity hizalaması.
- Boru hidrolik hesabında nominal çap yerine gerçek/hesaplanmış iç çap desteği.
- Malzemeye bağlı boru ölçü kataloğu ve tüm ağı birlikte yeniden hesaplayan global çap önerisi.
- AI, gerçek ölçek yoksa boru metresi uydurmaz; lengthMeters=0 bırakır ve RoomPlan/LiDAR metreye çevirir.
- Kolon/şaft/yasak bölge rotasında yükseklik aralığı dikkate alınır.
- Batch sync yeni proje oluştururken takım üyeliği zorunlu.
- Production AI endpointinde APP_API_TOKEN zorunlu.
- AR video/depth/trajectory ve saha fotoğrafları için yetkili artifact upload/download, PostgreSQL manifesti ve SHA-256 doğrulaması.
- Kanıt bulut senkron ekranı.
- iOS 2.2.0 build 22 / backend API 2.2.0.

## Mühendislik sınırı
Çap/rota/AI önerileri resmî proje kararı değildir. Dağıtım şirketi değerleri yalnız doğrulanmış kural profiliyle uygulanır. Yetkili mühendis doğrulaması zorunludur.

## Production
- HTTPS
- güçlü TEAM_AUTH_SECRET
- APP_API_TOKEN
- PostgreSQL
- kalıcı ARTIFACT_STORAGE_DIR volume
- düzenli veritabanı ve artifact yedeği
zorunludur.
