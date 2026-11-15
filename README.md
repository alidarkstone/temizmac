# TemizMac

Kişisel, açık kaynak macOS temizleyici. **Telemetri yok, ağ erişimi yok.**

## Özellikler
- Akıllı Tarama: önbellekler, günlükler, Xcode/geliştirici artıkları, Çöp Sepeti, 90 günden eski indirmeler
- Büyük dosya bulucu (ev dizini, eşik ayarlanabilir)
- Uygulama kaldırıcı (.app + ~/Library artıkları)

## Güvenlik
- **Önizleme (dry-run) varsayılan olarak açık**: kapatana kadar hiçbir şey taşınmaz.
- Silme = Çöp Sepeti'ne taşıma (geri alınabilir). Kalıcı silme yalnızca "Çöp Sepeti" kategorisinde.
- Yalnızca ev dizini (ve kaldırıcı için /Applications); symlink izlenmez; Keychain, Mail, Messages, iCloud, Photos, .ssh vb. korumalı.
- Oturum/kimlik önbellekleri (auth, token, CloudKit…) listeye alınmaz.
- Her işlem `~/Library/Logs/TemizMac/actions.log` dosyasına yazılır.
- Derleme betiği, kodda ağ API'si bulursa derlemeyi durdurur.

## Derleme
```bash
xcode-select --install   # yoksa
./scripts/build-app.sh
open build/TemizMac.app
```
Tam tarama için: Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi → TemizMac.
