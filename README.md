# Magicstone

<img src="Resources/Icon/icon_1024.png" width="128" alt="Magicstone">

Kişisel, açık kaynak macOS temizleyici. **Telemetri yok, ağ erişimi yok.**

## Özellikler
- Akıllı Tarama: önbellekler, günlükler, Xcode/geliştirici artıkları, Çöp Sepeti, 90 günden eski indirmeler
- Büyük dosya bulucu (ev dizini, eşik ayarlanabilir)
- Uygulama kaldırıcı (.app + ~/Library artıkları; App Store uygulamaları için yönetici izni)
- Bakım: tek tuşla sistem önbellek/veritabanı yenileme
- Performans ayarları (geri alınabilir): animasyonlar, Dock, telemetri kapatma, başlangıç ajanları, kaynak izleme
- Eski uygulama kalıntıları tarayıcısı
- Kopya dosya bulucu (SHA-256, yerel)
- Başlangıç öğeleri: yetim LaunchAgent temizliği
- Menü çubuğu simgesi: disk durumu, hızlı tarama

## İndir
[Releases](../../releases) sayfasından `Magicstone.zip`.

## Güvenlik
- **Önizleme (dry-run) varsayılan olarak açık**: kapatana kadar hiçbir şey taşınmaz.
- Silme = Çöp Sepeti'ne taşıma (geri alınabilir). Kalıcı silme yalnızca "Çöp Sepeti" kategorisinde.
- Yalnızca ev dizini (ve kaldırıcı için /Applications); symlink izlenmez; Keychain, Mail, Messages, iCloud, Photos, .ssh vb. korumalı.
- Oturum/kimlik önbellekleri (auth, token, CloudKit…) listeye alınmaz.
- Her işlem `~/Library/Logs/Magicstone/actions.log` dosyasına yazılır.
- Derleme betiği, kodda ağ API'si bulursa derlemeyi durdurur.

## Derleme
```bash
xcode-select --install   # yoksa
./scripts/build-app.sh
open build/Magicstone.app
```
Tam tarama için: Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi → Magicstone.
