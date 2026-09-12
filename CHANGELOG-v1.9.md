# v1.9 Final Candidate

- ARKit uygulama-içi saha video kaydı: MP4 video ile her karenin kamera transformu/intrinsics bilgisi aynı zaman çizelgesinde kaydedilir.
- LiDAR destekli cihazlarda sceneDepth bulunurluğu kare bazında izlenir.
- AR trajectory JSON ve video Application Support altında proje bazında saklanır.
- Metre ölçekli 3B tesisat görünümü: kat seviyesi, borular ve cihazlar SceneKit ile incelenebilir.
- Firma yönetim paneli: takım üyeleri/rolleri ve takım projeleri backend üzerinden görüntülenebilir.
- Backend `/v1/teams/:id/dashboard` endpointi ve audit kaydı.
- GitHub Actions CI: Linux kalite kapıları + backend contract testi + macOS iOS Simulator build.
- Sürüm 1.9.0 / build 19.

Not: AR kaydı video + kamera pozu + depth bulunurluğunu aynı ARSession içinde saklar. RoomPlan'in native oda modeli aynı anda üretilmiş gibi gösterilmez; saha geometri taraması ayrı doğrulama katmanıdır.
