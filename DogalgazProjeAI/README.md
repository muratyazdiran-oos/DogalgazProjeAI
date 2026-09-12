# Doğalgaz Proje AI – iOS v1.0

SwiftUI iOS 17+ proje hazırlama MVP'si.

## Akış
1. Proje oluştur veya JSON yedeğini içe aktar.
2. LiDAR ile alanı tara ya da gerçek ölçüyü elle gir.
3. Tesisat videosunu seç.
4. Backend videoyu Gemini'ye gönderip şemalı JSON döndürür.
5. Kullanıcı cihaz/boru konumlarını, cihaz kW değerlerini ve çapları doğrular.
6. Mühendislik profilini/limitlerini proje bazında girer.
7. Ön kontrol ve hidrolik özet incelenir.
8. PDF pafta ve JSON yedeği dışa aktarılır.

## Önemli dosyalar
- `AIProjectService.swift`: dosya tabanlı multipart video yükleme
- `RoomPlanScannerView.swift`: RoomPlan/LiDAR
- `ProjectEditorView.swift`: 2B düzenleyici ve branşman snap/bölme
- `HydraulicCalculator.swift`: ağ topolojisi, segment debisi/hız/basınç kaybı
- `EngineeringSettings.swift`: proje bazlı mühendislik profili
- `ProjectValidation.swift`: veri/ağ/limit ön kontrolleri
- `PDFExporter.swift`: pafta çıktısı
- `KeychainStore.swift`: backend erişim tokenı

## AI bağlantısı
Backend adresi kaynak koddan değiştirilmez. Ana ekran > **AI Ayarları** üzerinden girilir. Gemini API anahtarı yalnız backend ortam değişkeninde tutulur.

## Test dönemi
Ödeme ve abonelik yoktur. Analiz, tarama, düzenleme, hesap, PDF ve JSON özellikleri serbesttir.

## Mühendislik uyarısı
Uygulamanın otomatik hesabı resmî uygunluk sonucu üretmez. Seçilen şartname profili, basınç/hız limitleri ve tüm kritik tasarım kararları yetkili mühendis tarafından güncel dokümana göre doğrulanmalıdır.


### v1.9
AR saha kaydı, kamera trajectory verisi, 3B tesisat ve firma dashboardu eklendi.
