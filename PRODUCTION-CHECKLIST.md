# Production Checklist — v1.1

## Uygulama
- [x] Gerçek Xcode proje dosyası
- [x] AppIcon ve Info.plist
- [x] PrivacyInfo.xcprivacy
- [x] HTTPS production backend zorlaması
- [x] Keychain'de API erişim tokenı
- [x] Büyük video için dosya tabanlı multipart upload
- [x] Offline/timeout/401/413/429 hata akışları
- [x] Yerel proje yedeği ve bozuk veri kurtarma
- [x] JSON import doğrulaması
- [x] Uygulama içi production readiness ekranı
- [ ] macOS/Xcode ile Release Archive
- [ ] Gerçek iPhone üzerinde smoke test
- [ ] LiDAR destekli iPhone üzerinde saha ölçüm testi
- [ ] TestFlight gerçek backend testi

## Backend
- [x] GEMINI_API_KEY yalnız sunucu ortam değişkeninde
- [x] Bearer token desteği
- [x] Rate limit + Helmet + upload limit
- [x] Request ID
- [x] /health ve /ready
- [x] AI uzak video cleanup + yerel temp cleanup
- [x] Graceful shutdown
- [x] Exact dependency versions
- [x] Dockerfile
- [ ] Deployment platformunda HTTPS domain
- [ ] Güçlü APP_API_TOKEN secret
- [ ] Log/uptime alarmı

## Mühendislik
- [x] Segment debi, hız ve yaklaşık basınç kaybı
- [x] Kopuk hat / bağlı olmayan cihaz / döngü kontrolü
- [x] Proje bazlı teknik profil
- [ ] Güncel dağıtım şirketi teknik esaslarının yetkili mühendis tarafından doğrulanması
- [ ] Gerçek onaylı örnek projelerle sonuç karşılaştırması
- [ ] Resmî pafta formatının hedef dağıtım şirketi için doğrulanması

## App Store
- [x] Privacy manifest
- [ ] Privacy Policy URL
- [ ] App Privacy cevaplarını gerçek backend veri akışıyla eşleştirme
- [ ] Screenshots / açıklama / destek URL'si
- [ ] Archive Privacy Report kontrolü
- [ ] TestFlight / App Review smoke test
