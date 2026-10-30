<p align="center"><img src="tasarim/uygulama_simgesi.png" width="160" alt="GlassBar"></p>

# GlassBar

> **A personal note**
> GlassBar is the result of about four months of work, and I've been using it every day on my own MacBook for the past two months. It took much longer than I expected, and it still needs more time: some features are missing or only partly working. If you run into any of them, I'd really appreciate it if you let me know.
>
> I'm not fully happy with the design yet either, and I'll keep improving it.
>
> I haven't been able to measure any direct impact on battery life; in my use, CPU usage stays around 1%.
>
> — Yüksel Özge

13" M2 MacBook Pro'nun Touch Bar'ı için yerel macOS uygulaması. Dizilim ve özellikler orijinalle aynı (esc · uygulama alanı · Control Strip, genişletilmiş şerit, parlaklık/ses kaydırıcıları, fn ile F1–F12); görünüm Liquid Glass, Siri iOS 27'deki gibi koyu cam küre + renkli ses dalgası.

## Görseller / Screenshots

**Siri** — cam damla, mikrofona göre hareket eden renkli dalgalar / glass drop with mic-reactive waves

<p align="center"><img src="gorseller/siri.gif" width="720" alt="Siri animasyonu"></p>

![Siri çubukta](gorseller/siri-cubuk.gif)

**Finder**
![Finder](gorseller/varsayilan.png)

**Safari**
![Safari](gorseller/safari.png)

**Notlar / Notes**
![Notlar](gorseller/notlar.png)

**Genişletilmiş Control Strip / Expanded Control Strip**
![Genişletilmiş şerit](gorseller/genis.png)

**Parlaklık ve ses / Brightness and volume**
![Parlaklık](gorseller/parlaklik.png)
![Ses](gorseller/ses.png)

**fn → F1–F12**
![F tuşları](gorseller/fn.png)

**Emoji**
![Emoji](gorseller/emoji.png)

**Donanıma uyum** (`Sistem.swift` → `Donanim`): model `hw.model`'den okunur. 2019 sonu ve sonrası Touch Bar'lı MacBook Pro'larda (MacBookPro16,x, 17,1, Mac14,7) esc fizikseldir, çubuk 1004 pt'dir ve çubukta esc gösterilmez; önceki modellerde çubuk 1085 pt ve esc çubuktadır. Menüdeki "Çubukta esc tuşu" bunu değiştirir. Fiziksel esc de Siri hapını ve kaydırıcıyı kapatır.

## Kurulum
```
./build.sh --ac
```
`~/Applications/GlassBar.app` olarak kurulur ve açılır. Menü çubuğunda ✨ simgesi çıkar (göster, uygulamanın kendi tuşları, Mac açılınca başlat, çık).

**Erişilebilirlik izni gerekir** (Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik → GlassBar): esc, F1–F12, kısayollar, medya tuşları, yazma tahminleri ve fn'yi algılamak için. `build.sh`, anahtar zincirindeki "TouchBar2 Yerel Imza" sertifikasıyla imzalar (2026-10-30'da oluşturuldu, 10 yıl geçerli); böylece izin yeniden derlemelerde düşmez. Sertifika yoksa geçici imza kullanılır ve izin her derlemede yeniden verilmelidir. Açılıştaki izin durumu `~/Library/Logs/GlassBar.log` dosyasına yazılır. Müzik ve Finder etiketleri için ilk kullanımda Otomasyon izni sorulur.

## Nasıl çalışır
- Touch Bar'ı sistem kipinde kaplamak için MTMR/Pock'un da kullandığı gizli API'ler (`NSTouchBar presentSystemModalTouchBar…`, DFRFoundation). Apple bunları değiştirirse kırılabilir.
- Uygulama simgesi tuşu (esc'nin yanında) GlassBar'ı küçültüp öndeki uygulamanın kendi Touch Bar tuşlarını gösterir (yazı önerileri vb.); Control Strip'teki ✨ ya da başka uygulamaya geçmek geri getirir.
- Parlaklık: DisplayServices; klavye ışığı: CoreBrightness; ses: CoreAudio; adım tuşları sistemin HUD'unu çıkarsın diye medya tuşu gönderir.
- Launchpad tuşu macOS 26'dan beri "Uygulamalar"ı açar.
- Siri tuşu gerçek Siri'yi açar; çubuktaki cam damladaki dalgalar mikrofon seviyesine göre hareket eder (arka plan gürültüsü süzülür). Hap 12 sn sonra, dokununca, esc ile ya da başka uygulamaya geçince kapanır.

## Menü (✨)
Touch Bar gösterir / fn basılı tutulunca (uygulama, genişletilmiş şerit, F tuşları, masaüstü alanları), Control Strip'i göster, Control Strip tuşları, yazma önerileri, çubukta esc, ve öndeki uygulama için “kendi Touch Bar'ını göster” / “hep F tuşları”.

Masaüstü alanları arasında geçiş ⌃1…⌃9 kısayollarıyla yapılır; Sistem Ayarları → Klavye → Klavye Kısayolları → Mission Control'de "Masaüstü N'ye geç" kısayollarının açık olması gerekir. Öneriler ve emoji Erişilebilirlik izniyle çalışır; Spotify için ilk kullanımda Otomasyon izni sorulur.

Ayrıntılı özellik listesi: `OZELLIKLER.md`.

## Dosyalar
`Sources/main.swift` (gizli API, menü), `Durum.swift` (durum ve tuş işleri), `Cubuk.swift` (dizilim, uygulamaya özel tuşlar: Safari, Notlar, Müzik, Finder), `Cam.swift` (cam tuş, grup, kaydırıcı), `Siri.swift` (iOS 27 küre ve dalga), `Sistem.swift` (sistem çağrıları), `Ayarlar.swift` (ayarlar, Control Strip tuşları, Night Shift, giriş kaynağı, alanlar), `Calan.swift` (Şimdi Oynatılan, QuickTime film şeridi), `Yazi.swift` (öneriler, emoji, kaydırma şeridi).

## Sıvı cam dokunuşu (`Cam.swift` → `SiviBasma`)
Dokununca tuş büyür (%10), parmağın altında ışık yanar, oradan bir ışık halkası yayılır, kenar parlar ve camın arkasındaki ortam ışığı o noktada yanar. Parmak kaydıkça tuş o yöne esner; bırakınca yaylanıp salınarak yerine oturur. Gruplardaki tuşlarda grubun içinden cam bir damla kabarır; kaydırıcının topuzu sürüklenirken şeffaf merceğe dönüşür. Eylem, parmak tuşun üstündeyken kalkınca çalışır.

Ekran görüntüsü denemesi: `open ~/Applications/GlassBar.app --args -tb2kip genis|parlaklik|ses|siri|fn|emoji|simdi` (basılı görünüm için ayrıca `-tb2basili YES`), sonra `screencapture -b cubuk.png`.

**Yakında:** Spotify entegrasyonu — hesapla bağlanıp çalma listeleri, arama, Sıradakine Ekle ve Spotify Connect cihaz seçimi Touch Bar'dan.

---

Made by **Yüksel Özge** · [github.com/Moryel/touch-bar-2](https://github.com/Moryel/touch-bar-2)
