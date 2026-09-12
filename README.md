# DogalgazProjeAI v2.3 Final Candidate

SwiftUI iOS uygulaması + Node/Gemini backend. Video analizinden 2B tesisat taslağı, RoomPlan/LiDAR ölçü, AR depth/trajectory, çok noktalı AR↔RoomPlan hizalama, 3B güzergâh, mühendislik ön kontrolü, PDF/DXF, ekip/bulut ve kanıt artifact senkronizasyonu içerir.

## v2.3 öne çıkanlar
- 3–8 referans noktalı least-squares AR↔RoomPlan kalibrasyonu.
- RMS kalibrasyon hatası ve kalite göstergesi.
- Yatay X/Z similarity transform; dikey eksende ayrı datum offset.
- X/Z/kot kullanan 3B A* doğalgaz boru güzergâhı.
- 3B güzergâhı gerçek boru segmentlerine kot/elevation bilgisiyle taslak uygulama.
- Mühendis onay hash'ine saha fotoğrafı, AR video, trajectory, depth ve bulut artifact SHA-256 manifesti dahil.
- Kanıt/mühendislik hash'i değişirse onay otomatik iptal edilir.
- Artifact depolamada yerel disk veya AWS S3 / Cloudflare R2 / MinIO uyumlu object storage.
- SHA-256 artifact deduplication ve silme endpointi.
- iOS artifact indirmede streaming SHA-256 doğrulaması; büyük dosya RAM'e alınmaz.
- Backend 2.3.0, iOS 2.3.0 build 23.

## Mühendislik sınırı
AI, rota ve çap sonuçları taslaktır. Dağıtım şirketi teknik değerleri yalnız doğrulanmış kural profiliyle kullanılmalı ve yetkili mühendis tarafından doğrulanmalıdır.
