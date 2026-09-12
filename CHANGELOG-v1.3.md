# v1.3 Final Candidate

- DXF gerçek mm ölçeğine geçirildi (`$INSUNITS=4`); AutoCAD ve GasLine DXF içe aktarımı hedeflendi.
- Kalibrasyon için tek `resolvedAnalysis` doğruluk katmanı oluşturuldu; PDF, DXF, validasyon ve hidrolik hesap aynı geometri/metrajı kullanır.
- RoomPlan düzensiz oda alanı duvar zinciri + shoelace hesabıyla iyileştirildi.
- Hidrolik hesaba kot farkı ve otomatik dirsek/tee minör kayıp tahmini eklendi.
- Kural profiline kaynak dosyadan SHA-256 üretimi eklendi.
- Onay için bloklayıcı hata, mühendis/sicil, doğrulanmış+hashlenmiş kural profili, kalite kontrolü, mühendis imzası ve kaşe şartı eklendi.
- PencilKit mühendis/müşteri imzası ve kaşe görseli saklama; PDF'de mühendis imza/kaşe gösterimi eklendi.
- Proje değişince önceki onay otomatik iptal edilir; onay anında mühendislik içeriği SHA-256 ile mühürlenir.
- Privacy manifest hesap/bulut verilerini kullanıcıyla ilişkili olarak güncellendi.
- JSON ekip deposu kaldırıldı; production ekip/bulut için PostgreSQL zorunlu hale getirildi.
- Bulut senkronizasyonuna proje sürümü/optimistic locking ve 409 conflict koruması eklendi.
