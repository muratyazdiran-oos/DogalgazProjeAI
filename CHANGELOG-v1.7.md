# v1.7

- Engel duyarlı A* tabanlı boru güzergâh taslağı: RoomPlan oda sınırını korur, kapı/pencere/açıklık çevresinden kaçınır; mühendis kontrolü zorunludur.
- Proje Kalite Puanı (0-100): ön kontrol, AI/model doğrulama, gerçek ölçü, kural profili ve manuel kalite kontrolünü tek skorda toplar.
- Revizyon Karşılaştırma: son iki revizyonda cihaz/boru sayısı, boru metrajı, çap, kalibrasyon ve kural profili farklarını gösterir.
- Offline senkron kuyruğu UserDefaults yerine Application Support altında atomik, file-protected JSON depoya taşındı.
- Özel cihaz kataloğu da Application Support dosya deposuna taşındı.
- Teklif: firma, vergi/iletişim, teklif no, geçerlilik, ödeme koşulu ve ticari not alanları; PDF'e taşınır.
- Sürüm: iOS 1.7.0 build 17, backend API 1.7.0.

Not: Akıllı rota taslaktır; mevzuat/şartname ve saha engellerinin tamamını temsil ettiği varsayılmamalıdır. GasLine entegrasyonu DXF aktarımıdır; native kapalı proje formatı üretilmez.
