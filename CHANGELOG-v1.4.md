# DogalgazProjeAI v1.4

## CAD / Kalibrasyon
- AI/LiDAR kalibrasyonu normalize koordinat yerine fiziksel metre uzayında uygulanır.
- X/Y kalibrasyon ofsetleri metre cinsindedir.
- PDF, DXF ve hidrolik hesap aynı `resolvedAnalysis` geometrisini kullanır.
- DXF gerçek mm ölçeğinde; WALL, PIPE, PIPE_TEXT, METER, BOILER, STOVE, VALVE, VENT, DEVICE_TEXT ve DIMENSION katmanları içerir.
- Cihazlar BLOCK/INSERT olarak dışa aktarılır.
- DXF başlığına proje revizyonu ve SHA-256 izi eklenir.

## Proje bütünlüğü
- Revizyon snapshot'ları kalibrasyon, katlar, aktif kat, kalite kontrolü ve onay akışını da saklar.
- Oda/boru/cihaz/ölçü modellerine geriye uyumlu `floorID` eklendi.
- Yeni kat oluştururken elemanlar kat kimliğiyle etiketlenir.
- PDF dosya adı ve başlığı revizyon/hash bilgisi taşır.

## Backend
- PostgreSQL şema migration sistemi (`schema_migrations`).
- Ayrı auth rate limit.
- Oturum tokenlarında JTI ve sunucu tarafı logout/revocation.
- Şifre değiştirme endpointi.
- Audit log.
- Proje geçmiş sürümlerini saklayan `project_versions` tablosu.
- Optimistic locking korunur.
