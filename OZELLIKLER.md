# Orijinal Touch Bar'ın özellikleri ve GlassBar'daki durumu

English: [FEATURES.md](FEATURES.md)

Kaynaklar: Apple Destek "Touch Bar'ı kullanma" ve "Touch Bar'ı özelleştirme", MacRumors özelleştirme rehberi, iMore "Touch Bar ile neler yapılabilir", 9to5Mac Apple uygulamaları galerisi (2016), WWDC17 oturum 211 (AVKit), WebKit kaynak kodu (`generateTouchBarThumbnailsForTimes`). Uygulama çubukları 2026-10-30'da 13" M2'de (macOS 26) GlassBar kapalıyken her uygulama öne getirilip `screencapture -b` ile çekilen orijinallerle karşılaştırıldı.

Durum: ✅ var · 🟡 kısmen · ❌ yok · ⛔ yapılamaz (veriyi yalnız o uygulama verir)

## Düzen
| Özellik | Durum |
|---|---|
| esc / uygulama alanı / Control Strip dizilimi | ✅ |
| Fiziksel esc'li modellerde esc'siz, kısa çubuk | ✅ |
| Touch ID (donanım; dokunulmaz) | ✅ |
| Boşta kısılma, dokununca uyanma (sistem yapar) | ✅ sistemde |
| esc'in bağlama göre değişmesi (Kişiler'de "Bitti") | ❌ |
| Yer yetmeyince önceliğe göre tuş gizleme | ❌ |
| Ortam ışığına göre beyaz nokta (True Tone) | ❌ |

## Control Strip
| Özellik | Durum |
|---|---|
| Daraltılmış: genişlet, parlaklık, ses, sessiz, Siri | ✅ |
| Genişletilmiş: parlaklık ±, Mission Control, Launchpad/Uygulamalar, klavye ışığı ±, medya, ses ±/sessiz, Siri | ✅ |
| Tuşa dokunup **kaldırmadan kaydırma** (parlaklık/ses) | ✅ |
| Kaydırıcıya dokununca açılıp kapatma tuşu | ✅ |
| **Şimdi Oynatılan** tuşu (medya çalarken şeritte) | ✅ Müzik, Spotify, QuickTime (diğer uygulamalar ⛔: MediaRemote kapalı) |
| Şeridi özelleştirme | ✅ menüden 19 tuştan en çok 5'i, seçim sırasıyla · sürükle-bırak ❌ |
| Eklenebilir tuşlar | ✅ Spotlight, Bildirim Merkezi, Night Shift, Ekran Resmi, Giriş Kaynakları, Masaüstünü Göster, Ekran Koruyucu, Ekranı Kilitle, Uyut, Oynat/Duraklat, Mission Control, Uygulamalar, Klavye Aydınlatması, Dikte, Hızlı Eylemler (öndeki uygulamanın Servisler menüsü) · ❌ Rahatsız Etme, AirPlay (genel API yok) |

## Ayarlar (Klavye → Touch Bar Ayarları)
| Özellik | Durum |
|---|---|
| "Touch Bar gösterir": Uygulama Denetimleri / Genişletilmiş Control Strip / F1, F2 / Hızlı Eylemler / Alanlar (Spaces) | ✅ Hızlı Eylemler hariç |
| "fn basılı tutulunca": aynı 5 seçenek | ✅ Hızlı Eylemler hariç |
| Control Strip'i göster/gizle | ✅ |
| Belirli uygulamalarda hep F tuşları | ✅ |
| Yazma önerilerini göster | ✅ |
| fn + ⌃/⌥/⇧/⌘ + F tuşu | ✅ basılı değiştiriciler F tuşuna eklenir |
| Orijinalde olmayan: Tema (Klasik / Sade Liquid Glass) | ✅ |
| Orijinalde olmayan: Arka plan — Kapalı, Uygulamanın rengi, Aurora, Gün batımı, Okyanus, Siri renkleri, Duvar kağıdı (Mac'in masaüstü görseli), Görsel seç… | ✅ (`ArkaPlan.swift`) |
| Orijinalde olmayan: Siri hapı Apple'ın yeni Siri'si gibi şeffaf bir cam damla; içindeki renkli dalgalar mikrofondan gelen sese göre hareket eder, arka plan gürültüsü süzülür (ilk kullanımda mikrofon izni; ses kaydedilmez) | ✅ (`Siri.swift`, `Mikrofon.swift`) |
| Dil | ✅ GlassBar'ın yazıları sistemin dilinde (Türkçe, İngilizce; diğer dillerde İngilizce) — `Resources/<dil>.lproj/Localizable.strings`. Menü komutları kimlik, kısayol harfi ya da Türkçe/İngilizce başlıkla bulunur |

## Uygulamaya özel içerik

⛔ olanlar için menüden “… için kendi Touch Bar'ını göster” (ya da uygulama simgesini basılı tutmak): o uygulamanın kendi çubuğu görünür.

Menü komutları öndeki uygulamanın menüsünden Erişilebilirlik ile çalıştırılır (`AXYardim.swift`): Mail ve Mesajlar'da dilden bağımsız kimlikle, diğerlerinde Türkçe başlıkla. ⌘ kısayolları da önce menüde aranır (Türkçe Q'da ⌘[ → ⌘Ğ).

| Uygulama | Durum |
|---|---|
| **Safari** | ✅ geri/ileri, adres çubuğu, yeni sekme, pencere ve sekme şeridi (başlıklarla), tüm sekmeler görünümü · sekme küçük resimleri ⛔ · Sık Kullanılanlar ❌ (yer imleri dosyası Tam Disk Erişimi ister) · web videosu ✅ oynat/duraklat, ±10 sn, sarma şeridi, süre; YouTube'da küçük resimler sitenin kare görsellerinden (diğer sitelerde küçük resimsiz) — Safari'de Geliştir → "Apple Event'lerden gelen JavaScript'e izin ver" açık olmalı |
| **Finder** | ✅ orijinal düzen: geri/ileri, görünüm (açılır: simge/liste/sütun/galeri), Hızlı Bakış, Paylaş, Etiketler (açılır renk paleti) |
| **Mail** | ✅ orijinal düzen: Yeni İleti, Yanıtla (basılı kaydırınca Tümünü Yanıtla / İlet), Arşivle, Şuraya Taşı… (posta kutuları menüden), Sil, Bayrak (renkler menüden) · yazarken Gönder çubuğu ❌ |
| **Hesap Makinesi** | ✅ orijinal düzen: ± % , ve turuncu ÷ × − + = (Hesap Makinesi'nin düğmelerine basar) · Bilimsel mod tuşları ❌ |
| **Takvim** | ✅ Bugün ve ay şeridi (gösterilen ay çerçeveli, kırmızı) · gün/hafta görünümüne göre birim değişimi ❌ (hep ay) · etkinlik seçiliyken tuşlar ❌ |
| **Anımsatıcılar** | ✅ yeni anımsatıcı |
| **Kişiler** | ✅ yeni kişi, seçili kişinin adıyla mesaj, ara, FaceTime, e-posta, Düzenle, Paylaş (ilk kullanımda Kişiler için Otomasyon izni) |
| **Önizleme** | ✅ ayarlar (açılır: İşaretleme, Renk Ayarla, Boyutu Ayarla), sola/sağa döndür, yatay/düşey çevir |
| **Fotoğraflar** | ✅ Favori, Otomatik İyileştir, Döndür (araç çubuğu düğmeleri) · video açıkken oynat/duraklat, videonun karelerinden küçük resimli sarma şeridi, süreler (video geçici klasöre aktarılır; ilk kullanımda Otomasyon izni) · arşivdeki fotoğraf küçük resimleri şeridi ⛔ |
| **Mesajlar** | ✅ yeni ileti, Tapback (açılır: ❤️ 👍 👎 😂 ‼️ ❓), emoji, öneriler |
| **Notlar** | ✅ yazmıyorken orijinal düzen (yeni not, yapılacaklar, sil, liste); yazarken yapılacaklar, Aa (başlık stilleri, kalın/italik/altı çizili), liste türleri, emoji, öneriler |
| **TextEdit** | ✅ biçim (açılır: kalın/italik/altı çizili, hizalama), emoji, öneriler · renk seçici ⛔ |
| **Müzik / Spotify** | ✅ oynat/duraklat, önceki/sonraki, parça çubuğunda sarma, beğen · Sıradakine Ekle ✅ (Müzik) · Spotify: albüm kapağı, parça adı ve sanatçı, geçen/kalan süre ve kapak renklerinde ses dalgası, GlassBar'ın kendi Control Strip'inin yanında |
| **Spotify entegrasyonu** | 🔜 yakında: Spotify hesabıyla bağlanma (Web API), çalma listeleri, arama, Sıradakine Ekle, beğen, Spotify Connect ile cihaz seçimi |
| **QuickTime / AVKit video** | ✅ QuickTime (15 sn ileri/geri, küçük resimli film şeridi, cam mercekli oynatma başı) · diğer oynatıcılar ⛔ |
| **⇧⌘5 ekran resmi** | ✅ orijinal düzen: üç yakalama, üç kayıt, "Şuraya kaydet" (aracın düğmelerine basar) |
| Yazma önerileri (QuickType) | 🟡 kelime tamamlama, mavi düzeltme, orijinal görünüm (mavi-gri grup, "‹ ⌨") · kişi önerileri ⛔ |
| Emoji | ✅ orijinal 9 kategori: Sık Kullanılanlar, Suratlar ve İnsanlar, Hayvanlar ve Doğa, Yiyecek ve İçecek, Etkinlik, Seyahat ve Yerler, Nesneler, Semboller, Bayraklar; momentumlu kaydırma |
| Renk seçici (renk/ton, Basit/Gri/RGB/CMYK/HSB) | ⛔ rengi yalnız uygulama uygular |
| Haritalar, Sistem Ayarları | orijinalde de boş (macOS 26'da denendi) |
| Kitaplar ilerleme çubuğu, Takvim tarih ayrıntısı, Keynote slaytları, FaceTime | ⛔ |
| Pages, Numbers, Keynote, iMovie, GarageBand, Final Cut, Logic, Xcode, üçüncü taraf | "kendi Touch Bar'ını göster" ile uygulamanın kendi çubuğu |
| Touch ID / Apple Pay istemleri, gelen arama | ⛔ sistemin kendi çubuğu |
| Uygulamada "Touch Bar'ı Özelleştir" | ⛔ |

## Dokunuş davranışları
| Özellik | Durum |
|---|---|
| Dokun-kaldır ile tuş | ✅ |
| Açılır çubuk (popover): dokununca ya da basılı tutup kaydırınca diğer öğelerin üstüne açılır, köşede küçük ok | ✅ (`Acilir.swift`) |
| Basılı tut + kaydır + bırak ile tek harekette seçim | ✅ açılır çubuklarda (8 öğeye kadar) ve parlaklık/seste |
| Basılı tutunca alternatif (Mail Yanıtla) | ✅ |
| Şeritlerde momentumlu kaydırma ve yerine oturma (scrubber) | ✅ emoji, Safari sekmeleri, Takvim ayları, uzun açılır listeler |
| Kaydırıcı sürükleme | ✅ |

## Erişilebilirlik
| Özellik | Durum |
|---|---|
| Touch Bar Büyütme | ❌ |
| VoiceOver | denenmedi |
