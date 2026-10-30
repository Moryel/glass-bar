# TouchBar2 — yapılacaklar (2026-10-30 sonu)

Yeni konuşmada önce bunu ve `OZELLIKLER.md`'yi oku. Kod `Sources/`, derleme `./build.sh --ac`, kayıt `~/Library/Logs/TouchBar2.log`.

## Bağlam (kısa)
- Kalıcı imza "TouchBar2 Yerel Imza"; izinler bu sürüme verildi (Erişilebilirlik, Otomasyon: Safari/Fotoğraflar, mikrofon). Safari'de "Apple Event'lerden gelen JavaScript'e izin ver" açık.
- Menü komutları `AXYardim.swift` (kimlik > başlık; Türkçe başlıkların İngilizcesi `AX.ingilizce`). ⌘ kısayolları önce menüde, Türkçe Q'da düzen karakteriyle (⌘[ → ⌘Ğ) aranır.
- Açılır çubuk `Acilir.swift`, uygulama çubukları `Cubuk.swift`, dil `Resources/<dil>.lproj` + `L()`.
- Touch Bar görüntüsü: `screencapture -b dosya.png` (TouchBar2'yi `open -g` ile arkada aç, ilgili uygulama önde olsun; yoksa boş çıkar). Orijinal çubuğu görmek için TouchBar2'yi kapatıp uygulamayı öne getir.
- Deneme bayrakları: `open ~/Applications/TouchBar2.app --args -tb2kip genis|parlaklik|ses|siri|fn|emoji|simdi|sekmeler`, `-AppleLanguages "(en)"`.
- Kullanıcı jeton tüketimine dikkat ediyor: kısa tut, gereksiz ekran görüntüsü ve okuma yapma.

## 1. Kullanıcı deneyecek (sonucu söyleyince düzelt)
- [ ] Finder: geri/ileri, görünüm (açılır), Hızlı Bakış, Paylaş, Etiketler
- [ ] Mail: Yeni İleti, Yanıtla (basılı kaydır → Tümünü Yanıtla/İlet), Arşivle, Şuraya Taşı…, Sil, Bayrak
- [ ] Hesap Makinesi, Takvim (Bugün, ay şeridi), Anımsatıcılar, Kişiler (ad, ara, FaceTime, mesaj, e-posta)
- [ ] Önizleme (döndür/çevir, ayarlar), Mesajlar (Tapback), Notlar (yazarken Aa, liste), TextEdit (biçim)
- [ ] Emoji 9 kategori; açılır çubukta basılı tut + kaydır + bırak
- [ ] Control Strip yeni tuşlar: Klavye Aydınlatması, Dikte, Hızlı Eylemler

## 2. Kısa düzeltmeler
- [x] Safari sekme şeridi: boşluk 1/7/12 sekmede görülmedi; şerit artık seçili sekmeye kayıyor, içerik daralınca boşluk kalmıyor (`Kaydirma.yerlestir`, `.seritteSecili`)
- [x] Mail "Move to…" İngilizcede kesikti: Touch Bar'da `Text.fixedSize()` sonu kesiyor ("Tod…"). Düğme yazıları artık `Yazi` (Cam.swift; AppKit'le ölçüp pay veriyor). Yeni düğme yazısında `fixedSize` kullanma
- [ ] İngilizce menü başlıkları gerçekten İngilizce açılmış uygulamada çalışıyor mu (Önizleme, Notlar, TextEdit) — **kullanıcı dener** (osascript'e Erişilebilirlik izni yok, buradan denenemedi)

## 3. Yapılabilir, yapılmadı
- [x] Control Strip'i Özelleştir (menü → "Control Strip'i Özelleştir…", `-tb2kip seritDuzenle`): Touch Bar'da sürükleyerek sırala, dokununca çıkar/ekle (`SeritDuzenleyici`) — sürükleme **dene**
- [x] "Touch Bar gösterir": Hızlı Eylemler (Servisler menüsü, `HizliEylemSatiri`) — denendi
- [x] Mail ileti yazarken Gönder çubuğu (yazarken: Gönder, Dosya Ekle, öneriler) — **dene**: menü başlığı "Gönder"/"Dosya Ekle…" tutmazsa kayıtta "bulunamadı" çıkar
- [ ] Hesap Makinesi Bilimsel mod tuşları — bilimsel düğmelerin AX kimlikleri bilinmiyor; Bilimsel modda bir kez `AX` ile pencere düğmelerinin kimliklerini kayda yazdırıp bakmak gerek
- [x] Takvim: gün/hafta/ay birimi Görüntü menüsündeki işaretten (`takvimYenile`, `AX.isaretli`) — **dene** (betikle görünüm değiştirilemedi). Etkinlik seçiliyken tuşlar yapılmadı
- [x] Müzik "Sıradakine Ekle" (çalarken) — **dene**: başlık tahmini "Sıradaki Olarak Çal"/"Sonra Çal"/"Play Next"
- [x] esc emoji/sekmeler/Şimdi Oynatılan açıkken "Bitti" (çubukta esc gösteriliyorsa; o kiplerde esc çoğu zaman gizli, X var)
- [x] Dar alanda: `ViewThatFits` ile önce yazılı etiketler simgeye döner (`darAlan` ortam değeri, şimdilik Mail "Şuraya Taşı"), sonra uygulama simgesi gizlenir
- [ ] Touch Bar Büyütme; VoiceOver denemesi
- [x] Renk sıcaklığı (menü: Kapalı / Ilık / Sıcak / Night Shift açıkken) — denendi
- [ ] Safari Sık Kullanılanlar (Tam Disk Erişimi gerekir)

## 3b. Gelecek: Spotify entegrasyonu
- [ ] Spotify Web API (hesapla bağlanma, OAuth PKCE): çalma listeleri şeridi, arama, Sıradakine Ekle, beğen, Spotify Connect cihaz seçimi. Şu an Spotify yalnız AppleScript ile (oynat/duraklat, önceki/sonraki, sarma).

## 4. HTML önizleme
- [x] (2026-10-30) Yayında sürüm 5: Klasik/Sade seçici, uygulama seçici (Safari, Mail, Mail yazarken, Takvim, Hesap Makinesi, Müzik, Finder), Safari sekmeleri, Hızlı Eylemler, Control Strip düzenleyici, ⇧⌘5, açılır çubuk (Mail Yanıtla basılı), arka plan stilleri, renk sıcaklığı. `touchbar2-onizleme.html` artık `onizleme_yap.py` ile v4'ten üretilir (`python3 onizleme_yap.py .`); v4 dosyasına dokunma. Eksik: Siri cam damlası ve video şeritleri (Safari/Fotoğraflar) önizlemede ayrı panel değil.
- Eski not: Uygulamanın yaptığı her şeyi birebir gösteren önizleme; görünüm seçici "Klasik" / "Sade Liquid Glass" (v4 korunacak). Dosyalar `onizleme/` (v4, SF Symbols PNG'leri, uygulama ikonları).
- (yapıldı) Bugün eklenenler de girmeli: uygulama çubukları, açılır çubuk, ⇧⌘5, Safari sekmeleri ve video, Fotoğraflar videosu, arka plan stilleri, Siri cam damlası.
