# v2.1 Final Candidate

- RoomPlan Coordinator güncel Xcode derleme hatası giderildi.
- AR kaydında sceneDepth verisi yaklaşık 2 Hz hızında 32×24 örnek grid olarak saklanır.
- Kamera pose + intrinsics + depth ile video noktası AR dünya koordinatına projekte edilebilir.
- AI cihaz çıktısına video zamanı ve normalize bounding box alanları eklendi.
- Cihazlar AI → AR 3B eşleme ekranından dünya koordinatına bağlanabilir.
- Boru başlangıç/bitiş kotları ve cihaz kotları eklendi; 3B görünüm ve DXF Z koordinatları kullanır.
- RoomPlan duvar/açıklıkları 3B sahnede görünür.
- Manuel kolon/şaft/baca/dolap/yasak bölge tanımı ve akıllı rotada kaçınma eklendi.
- Doğrulanmış proje limitlerinden ön boru çapı önerisi eklendi; öneriler manuel inceleme işaretlidir.
- AR kayıt temizliği aktif proje oturumunu silmez.
- Depth kalite puanı yalnız cihaz sceneDepth destekliyorsa uygulanır.
- Saha kanıt fotoğraflarına SHA-256 bütünlük izi eklendi.
- Cihaz etiketi OCR akışına QR/barkod okuma eklendi.
- AR video orientation metadata düzeltmesi eklendi.
- iOS 2.1.0 build 21 / backend API 2.1.0.
