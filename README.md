# DogalgazProjeAI v2.4 Final Candidate

SwiftUI iOS uygulaması + Node/Gemini backend. Video analizinden 2B taslak, RoomPlan/LiDAR ölçü, çok noktalı AR↔RoomPlan hizalama, confidence destekli çok-kare depth, tam 3B rota, hidrolik/çap optimizasyonu, PDF/DXF, firma paneli ve doğrulanabilir kanıt bulutu içerir.

## v2.4 öne çıkanlar
- Çok noktalı AR↔RoomPlan kalibrasyonunda yatay/dikey RMS, minimum referans mesafesi ve nokta yayılım kalite kapısı.
- RoomPlan polygon sınırına bağlı X/Z/kot 3B A* rota.
- Duvara yakın güzergâh tercihleri, düşey hareket ve gereksiz tavan rotası cezaları.
- 3B rota → gerçek uzunluk/kot → hidrolik yeniden hesap → çap önerisi tek akış.
- Hidrolik ağdan sayaç→kritik cihaz gerçek kritik boru yolu çıkarımı.
- ARKit sceneDepth confidence map kaydı, yaklaşık 4 Hz örnekleme ve çok-kare high/medium confidence median depth füzyonu.
- S3 / Cloudflare R2 / MinIO presigned doğrudan upload; backend multipart fallback.
- Presigned upload session takibi, süre dolan yarım upload GC, SHA race cleanup ve retry queue.
- Artifact SHA dedup, silme, uzaktan sağlık/SHA/boyut doğrulaması.
- Mühendis onayında yerel kanıt veya son 24 saatte doğrulanmış bulut kanıtı şartı.
- Firma panelinde geciken işler, onay kuyruğu, artifact sayısı ve filtreler.
- Üretime hazırlık ekranında AR RMS, 3B kot kapsamı, hidrolik ağ, saha kanıtı ve cloud health.
- iOS 2.4.0 build 24 / backend 2.4.0.

## Production
Gerekli bileşenler: HTTPS, APP_API_TOKEN, TEAM_AUTH_SECRET, PostgreSQL, kalıcı artifact storage veya S3/R2/MinIO, düzenli DB/object-storage yedeği.

## Mühendislik sınırı
AI/rota/çap önerileri taslaktır. Dağıtım şirketi teknik değerleri yalnız doğrulanmış kaynak/kural profiliyle kullanılmalı ve yetkili mühendis tarafından onaylanmalıdır.
