# Doğalgaz Proje AI v1.1

## Production hardening
- Üretim backend adreslerinde HTTPS zorunlu; HTTP yalnızca localhost geliştirmede kabul edilir.
- AI video yüklemeleri ephemeral URLSession, connectivity wait, cache kapalı ve daha ayrıntılı hata sınıfları ile güçlendirildi.
- 401/403, 413, 429, timeout, offline ve cancellation kullanıcıya anlaşılır hata olarak gösterilir.
- Müşteri adı, adresi ve proje adı AI backend/Gemini'ye artık gönderilmez; yalnız seçilen tesisat videosu analiz için yüklenir.
- Proje verisi atomic + complete file protection ile kaydedilir; son yerel dosya yedeklenir ve bozulmada kurtarma denenir.
- JSON import boyut ve yapı doğrulaması eklendi.
- Apple PrivacyInfo.xcprivacy eklendi; UserDefaults required-reason beyanı ve video/environment scanning veri kullanım beyanları içerir.
- Uygulama içine Üretime Hazırlık kontrol ekranı eklendi.
- Backend'e request ID, production-safe error response, readiness endpoint, graceful shutdown, daha sıkı multipart limitleri eklendi.
- Backend bağımlılıkları exact sürümlere sabitlendi ve Dockerfile eklendi.
- Sürüm 1.1.0 / build 11.

## Önemli
Bu uygulamanın ürettiği çıktı saha keşfi ve proje taslağıdır. Yetkili mühendisin teknik şartname, hesap ve resmî proje onayı yerine geçmez.
