## Magicstone 1.1.0

Telemetri yok, ağ erişimi yok. Her şey bu Mac'te kalır.

**Özellikler**
- Akıllı Tarama: önbellek, log, Xcode/geliştirici artıkları, eski indirmeler — tek tıkla temizlik
- Eski uygulama kalıntıları: daha önce kaldırılmış uygulamaların ~/Library ve /Library'de bıraktığı klasör ve kayıtları bulur
- Bakım: tek tuşla RAM boşaltma, DNS önbelleği, bakım betikleri, Launch Services, Quick Look, yazı tipi önbelleği, Spotlight yeniden dizinleme, disk doğrulama (tek yönetici parolası)
- Performans: görsel efekt/Dock hızlandırma, Apple telemetrisini kapatma, üçüncü taraf başlangıç ajanlarını aç/kapa, en çok kaynak kullananlar — hepsi "Geri Al" ile geri alınabilir
- Büyük dosya ve kopya dosya bulucu
- Tam uygulama kaldırıcı: ~/Library ve /Library'de 25+ konumda (Containers, Group Containers, Preferences/ByHost, LaunchDaemons, PrivilegedHelperTools, paket makbuzları…) bundle ID ve ekip kimliğiyle artık arar; App Store uygulamaları dahil, tek yönetici parolasıyla
- Başlangıç öğeleri: yetim LaunchAgent'ları bulur ve kaldırır
- Menü çubuğu: disk durumu, hızlı tarama

- Denetim: salt-okunur sistem raporu (SIP, FileVault, Gatekeeper, disk, ayarlar, ajanlar, kalıntılar) dosyaya yazılır
- Tut listesi: sağ tık → "Tut" ile bir öğe bir daha önerilmez ve asla taşınmaz
- Eski paket kayıtları `pkgutil` ile doğrulanır

**Güvenlik:** Önizleme modu varsayılan açık; silinenler Çöp Sepeti'ne gider; korumalı yollar (Anahtar Zinciri, iCloud, Fotoğraflar, Metal/shader önbellekleri); SIP/Gatekeeper/FileVault/güvenlik duvarı/güncellemelere asla dokunulmaz; yerel işlem günlüğü.

**Kurulum:** Zip'i aç → `Magicstone.app`'i Uygulamalar'a taşı → ilk açılışta sağ tık → **Aç**.
Uygulama Apple tarafından notarize edilmemiştir (ücretli geliştirici hesabı gerekir).
