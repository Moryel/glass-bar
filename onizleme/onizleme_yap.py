#!/usr/bin/env python3
# v4 önizlemesinden (dokunulmaz) tam önizlemeyi üretir: Klasik/Sade seçici, uygulama çubukları ve bugünkü özellikler.
import base64, re, struct, sys, os

kok = sys.argv[1]  # onizleme klasörü
v4 = open(os.path.join(kok, 'touchbar2-onizleme.v4.html'), encoding='utf-8').read()

def png_boyut(yol):
    b = open(yol, 'rb').read(24)
    return struct.unpack('>II', b[16:24])

def veri(yol):
    return 'data:image/png;base64,' + base64.b64encode(open(yol, 'rb').read()).decode()

# 1) Sade (native Liquid Glass) kuralları yalnız data-tema="sade" iken geçerli olsun; Klasik = temel kurallar
bas = v4.index('/* ---------- native Liquid Glass')
son = v4.index('@media (prefers-reduced-motion: reduce)', bas)
blok = v4[bas:son]
satirlar = []
for s in blok.split('\n'):
    if s and not s[0].isspace() and not s.startswith('/*') and not s.startswith('}') and '{' in s:
        sec, kalan = s.split('{', 1)
        sec = ', '.join('.cubuk[data-tema="sade"] ' + x.strip() for x in sec.split(','))
        s = sec + ' {' + kalan
    satirlar.append(s)
html = v4[:bas] + '\n'.join(satirlar) + v4[son:]

# 2) yeni SF Symbols (48 pt'den 0.31 ölçekle, mevcutlarla aynı)
mevcut = set(re.findall(r'\.sf\[data-sf="([^"]+)"\]', html))
ekler = []
for ad in sorted(os.listdir(os.path.join(kok, 'simgeler'))):
    a = ad[:-4]
    if a in mevcut: continue
    yol = os.path.join(kok, 'simgeler', ad)
    w, h = png_boyut(yol)
    ekler.append(f'.sf[data-sf="{a}"] {{ width: {w*.31:.1f}px; height: {h*.31:.1f}px; --m: url({veri(yol)}); }}')
ikon = {k: veri(os.path.join(kok, 'ikonlar', k + '.png')) for k in
        ['com.apple.Safari', 'com.apple.mail', 'com.apple.iCal', 'com.apple.calculator', 'com.apple.Music', 'com.apple.finder']}

css = '\n'.join(ekler) + '''
/* ---------- tam önizleme eklemeleri ---------- */
.cam.uyg img { width: 20px; height: 20px; position: relative; z-index: 3; }
.cam.yazi { padding: 0 12px; }
.cam.kirmizi span { color: #ff453a; }
.cam.cerceve::after { box-shadow: inset 0 0 0 1.5px #fff; border-radius: inherit; }
.cam.secili::before { background: rgba(255,255,255,.28) !important; }
.serit2 { flex: 1; min-width: 0; display: flex; gap: 4px; overflow: hidden; border-radius: 13px; mask: linear-gradient(90deg, #000 92%, transparent); -webkit-mask: linear-gradient(90deg, #000 92%, transparent); }
.serit2 .cam { flex: none; }
.serit2 .cam span { max-width: 150px; overflow: hidden; text-overflow: ellipsis; }
.etiket { font-size: 11px; color: rgba(255,255,255,.5); padding: 0 6px; white-space: nowrap; }
.soluk { font-size: 12px; color: rgba(255,255,255,.5); padding-left: 6px; white-space: nowrap; }
.rozet-eksi { position: absolute; top: -2px; right: -1px; width: 10px; height: 10px; border-radius: 50%; background: #ff453a; z-index: 4; }
.rozet-eksi::after { content: ""; position: absolute; left: 2px; right: 2px; top: 4.25px; height: 1.5px; background: #fff; }
.duzen { padding: 0 4px; border-radius: 15px; background: rgba(255,255,255,.08); display: flex; gap: 4px; height: 26px; align-items: center; }
.oneri { flex: 1; min-width: 0; height: 26px; display: flex; border-radius: 13px; background: rgba(255,255,255,.1); overflow: hidden; }
.oneri span { flex: 1; display: grid; place-items: center; font-size: 13px; }
.oneri span + span { box-shadow: -1px 0 0 rgba(255,255,255,.12); }
.sarma { flex: 1; min-width: 0; display: flex; align-items: center; gap: 8px; font: 11px var(--f-kod, monospace); color: rgba(255,255,255,.6); }
.sarma .ray2 { flex: 1; height: 4px; border-radius: 2px; background: linear-gradient(90deg, #fff 38%, rgba(255,255,255,.2) 38%); }
.cubuk[data-arka="duvar"] canvas#ortam { background: linear-gradient(100deg, rgba(56,92,160,.55), rgba(140,70,120,.45) 45%, rgba(40,120,110,.5)); filter: blur(1px) brightness(.7); }
.sicak { position: absolute; inset: 0; pointer-events: none; mix-blend-mode: multiply; z-index: 20; border-radius: inherit; background: rgb(255, calc(255 - 41 * var(--g, 0)), calc(255 - 107 * var(--g, 0))); }
.cubuk:not([data-sicak]) .sicak { display: none; }
'''
html = html.replace('</style>', css + '\n</style>', 1)

# 3) yeni paneller (data-app: uygulama alanında hangi uygulamada görünür)
def tus(sf, eylem='', sinif='simge'):
    return f'<div class="cam {sinif}" data-eylem="{eylem}"><i class="sf" data-sf="{sf}"></i></div>'
def yazi(t, eylem='', sinif='yazi'):
    return f'<div class="cam {sinif}" data-eylem="{eylem}"><span>{t}</span></div>'
def uyg(k):
    return f'<div class="cam simge uyg" data-eylem="uygulama-tuslari" title="Basılı tut: uygulamanın kendi tuşları"><img alt="" src="{ikon[k]}"></div>'

aylar = ['Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara', 'Oca', 'Şub', 'Mar']
paneller = f'''
          <div class="panel gizli" data-panel="uygulama" data-app="mail">
            {uyg('com.apple.mail')}
            {tus('square.and.pencil', 'mail-yaz')}
            <div class="cam simge" data-eylem="yanitla" data-uzun="acilir" title="Basılı tut: Tümünü Yanıtla / İlet"><i class="sf" data-sf="arrowshape.turn.up.left"></i></div>
            {tus('archivebox')}
            <div class="cam genis" data-eylem="tasi"><i class="sf" data-sf="folder"></i><span>Şuraya Taşı…</span></div>
            {tus('xmark.bin')}
            {tus('flag.fill', '', 'simge turuncu')}
          </div>
          <div class="panel gizli" data-panel="uygulama" data-app="mailyaz">
            {uyg('com.apple.mail')}
            {tus('paperplane.fill', 'mail-gonder', 'simge ton')}
            {tus('paperclip')}
            {tus('face.smiling', 'emoji')}
            <div class="oneri"><span>“Merhaba”</span><span>Teşekkürler</span><span>Tamam</span></div>
          </div>
          <div class="panel gizli" data-panel="uygulama" data-app="takvim">
            {uyg('com.apple.iCal')}
            {yazi('Bugün')}
            <div class="serit2">{''.join(yazi(a, '', 'yazi' + (' kirmizi cerceve' if a == 'Eki' else '')).replace('class="cam', 'style="width:84px;justify-content:center" class="cam') for a in aylar)}</div>
          </div>
          <div class="panel gizli" data-panel="uygulama" data-app="hesap">
            {uyg('com.apple.calculator')}
            <div class="cam" style="flex:1" data-eylem=""><i class="sf" data-sf="plus.forwardslash.minus"></i></div>
            <div class="cam" style="flex:1" data-eylem=""><i class="sf" data-sf="percent"></i></div>
            <div class="cam" style="flex:1" data-eylem=""><span>,</span></div>
            <div style="flex:1.2"></div>
            {''.join(f'<div class="cam turuncu" style="flex:1" data-eylem=""><i class="sf" data-sf="{s}"></i></div>' for s in ['divide', 'multiply', 'minus', 'plus', 'equal'])}
          </div>
          <div class="panel gizli" data-panel="uygulama" data-app="muzik">
            {uyg('com.apple.Music')}
            <div class="grup">{tus('backward.fill', '', '')}{tus('playpause.fill', '', '')}{tus('forward.fill', '', '')}</div>
            <div class="sarma"><span>1:24</span><div class="ray2"></div><span>−2:16</span></div>
            {tus('text.line.first.and.arrowtriangle.forward', 'sira')}
          </div>
          <div class="panel gizli" data-panel="uygulama" data-app="finder">
            {uyg('com.apple.finder')}
            <div class="grup">{tus('chevron.left', '', '')}{tus('chevron.right', '', '')}</div>
            {tus('square.grid.2x2', 'gorunum')}
            {tus('eye')}
            {tus('square.and.arrow.up')}
            {tus('tag')}
            <div class="bosluk"></div>
          </div>

          <!-- Safari sekmeleri -->
          <div class="panel gizli" data-panel="sekmeler">
            {tus('xmark', 'kapat')}
            <div class="serit2">{''.join(yazi(t, '', 'yazi' + (' secili' if i == 3 else '')) for i, t in enumerate(['Başlangıç Sayfası', 'Apple', 'Wikipedia', 'GitHub', 'Swift Programming Language', 'Python.org', 'MDN Web Docs']))}</div>
            {tus('square.grid.2x2')}
            {tus('plus')}
          </div>

          <!-- Hızlı Eylemler (Touch Bar gösterir: Hızlı Eylemler) -->
          <div class="panel gizli" data-panel="hizli">
            {tus('gearshape.2')}
            <div class="serit2">{''.join(yazi(t) for t in ['Fotoğraf Döndür', 'PDF Oluştur', 'Metni Sese Dönüştür', 'Yeni Terminal', 'Görüntüyü Dönüştür', 'Arka Planı Kaldır'])}</div>
          </div>

          <!-- Control Strip'i Özelleştir -->
          <div class="panel gizli" data-panel="duzenle">
            <div class="cam ton" style="width:64px" data-eylem="kapat"><span>Bitti</span></div>
            <div class="duzen" id="duzen">{''.join(f'<div class="cam simge" data-eylem="cikar" data-sf-ad="{s}"><i class="sf" data-sf="{s}"></i><i class="rozet-eksi"></i></div>' for s in ['sun.max.fill', 'speaker.wave.2.fill', 'speaker.slash.fill'])}</div>
            <span class="etiket" id="duzenEtiket">Ekle:</span>
            <div class="serit2" id="ekle">{''.join(f'<div class="cam simge" data-eylem="ekle" data-sf-ad="{s}"><i class="sf" data-sf="{s}"></i></div>' for s in ['playpause.fill', 'rectangle.3.group', 'square.grid.3x3.fill', 'magnifyingglass', 'moon.stars.fill', 'camera.viewfinder', 'globe', 'lock.fill', 'powersleep', 'keyboard', 'mic.fill', 'gearshape.2'])}</div>
          </div>

          <!-- ⇧⌘5 ekran resmi -->
          <div class="panel gizli" data-panel="ekranresmi">
            {tus('xmark', 'kapat')}
            <div class="grup">{tus('rectangle.inset.filled', '', '')}{tus('macwindow', '', 'secili')}{tus('rectangle.dashed', '', '')}</div>
            <div class="grup">{tus('record.circle', '', '')}{tus('rectangle.dashed', '', '')}</div>
            <div class="bosluk"></div>
            <span class="soluk">Şuraya kaydet:</span>
            <div class="cam yazi" data-eylem=""><span>Masaüstü</span></div>
            <div class="cam yazi ton" data-eylem=""><span>Yakala</span></div>
          </div>

          <!-- açılır çubuk: Mail Yanıtla basılı tutulunca; parmağı kaydırıp bırakınca seçilir -->
          <div class="panel gizli" data-panel="acilir">
            {tus('xmark', 'kapat')}
            <span class="etiket">Yanıtla</span>
            {yazi('Yanıtla', 'kapat')}{yazi('Tümünü Yanıtla', 'kapat', 'yazi secili')}{yazi('İlet', 'kapat')}
            <div class="bosluk"></div>
          </div>
'''
html = html.replace('          <!-- F tuşları -->', paneller + '\n          <!-- F tuşları -->', 1)
# Safari panelinin başına uygulama simgesi ve data-app
html = html.replace('<div class="panel" data-panel="uygulama">', '<div class="panel" data-panel="uygulama" data-app="safari">\n            ' + uyg('com.apple.Safari'), 1)
# Safari'de sekme şeridi düğmesi
html = html.replace('<div class="cam simge ton" data-eylem="yeni"', tus('square.grid.2x2', 'sekmeler') + '\n            <div class="cam simge ton" data-eylem="yeni"', 1)
# renk sıcaklığı katmanı
html = html.replace('<div class="hap gizli" id="hap"', '<div class="sicak"></div>\n        <div class="hap gizli" id="hap"', 1)

# 4) denetimler
html = html.replace('''        <button aria-pressed="false" data-deger="siri">Siri</button>
      </div>''', '''        <button aria-pressed="false" data-deger="siri">Siri</button>
        <button aria-pressed="false" data-deger="sekmeler">Safari sekmeleri</button>
        <button aria-pressed="false" data-deger="hizli">Hızlı Eylemler</button>
        <button aria-pressed="false" data-deger="duzenle">Control Strip'i Özelleştir</button>
        <button aria-pressed="false" data-deger="ekranresmi">⇧⌘5</button>
        <button aria-pressed="false" data-deger="acilir">Açılır çubuk</button>
      </div>''', 1)
html = html.replace('''    <div class="secim">
      <span>Cam varyantı</span>''', '''    <div class="secim">
      <span>Görünüm</span>
      <div class="dilim" data-secim="tema">
        <button aria-pressed="false" data-deger="klasik">Klasik</button>
        <button aria-pressed="true" data-deger="sade">Sade Liquid Glass</button>
      </div>
      <p class="ipucu">Uygulamadaki "Tema" seçeneği. Klasik: belirgin cam, parlak şerit, ışık halkası. Sade: macOS 26'ya yakın; kenarda kırılan ışık, halka yok.</p>
    </div>
    <div class="secim">
      <span>Uygulama</span>
      <div class="dilim" data-secim="app">
        <button aria-pressed="true" data-deger="safari">Safari</button>
        <button aria-pressed="false" data-deger="mail">Mail</button>
        <button aria-pressed="false" data-deger="mailyaz">Mail · yazarken</button>
        <button aria-pressed="false" data-deger="takvim">Takvim</button>
        <button aria-pressed="false" data-deger="hesap">Hesap Makinesi</button>
        <button aria-pressed="false" data-deger="muzik">Müzik</button>
        <button aria-pressed="false" data-deger="finder">Finder</button>
      </div>
      <p class="ipucu">Öndeki uygulamaya göre değişen uygulama alanı. Mail'de Yanıtla'yı basılı tut: açılır çubuk. Safari'de ⊞: sekme şeridi.</p>
    </div>
    <div class="secim">
      <span>Arka plan ve renk</span>
      <div class="dilim" data-secim="arka">
        <button aria-pressed="true" data-deger="kapali">Kapalı</button>
        <button aria-pressed="false" data-deger="isik">Işık</button>
        <button aria-pressed="false" data-deger="duvar">Duvar kağıdı</button>
      </div>
      <div class="dilim" data-secim="sicak">
        <button aria-pressed="true" data-deger="0">Renk: normal</button>
        <button aria-pressed="false" data-deger=".5">Ilık</button>
        <button aria-pressed="false" data-deger="1">Sıcak</button>
      </div>
    </div>
    <div class="secim">
      <span>Cam varyantı</span>''', 1)

# 5) betik
js_eski = "paneller.forEach(p => p.classList.toggle('gizli', p.dataset.panel !== yeni));"
assert js_eski in html
html = html.replace(js_eski, "paneller.forEach(p => p.classList.toggle('gizli', p.dataset.panel !== yeni || (p.dataset.app && p.dataset.app !== uygulama)));", 1)
html = html.replace("darSerit.style.display = (yeni === 'uygulama') ? 'flex' : 'none';",
                    "darSerit.style.display = (yeni === 'uygulama' || yeni === 'sekmeler' || yeni === 'hizli') ? 'flex' : 'none';", 1)
html = html.replace("  let kip = 'uygulama', oncekiKip = 'uygulama';", "  let kip = 'uygulama', oncekiKip = 'uygulama', uygulama = 'safari';", 1)
html = html.replace("durum.textContent = durumYazi[yeni];", "durum.textContent = durumYazi[yeni] || yeni;", 1)
html = html.replace("      case 'siri': siriDegistir(); break;", """      case 'siri': siriDegistir(); break;
      case 'sekmeler': kipSec('sekmeler'); break;
      case 'mail-yaz': uygulamaSec('mailyaz'); break;
      case 'mail-gonder': uygulamaSec('mail'); break;
      case 'emoji': if (kip !== 'emoji') kipSec('emoji'); break;""", 1)
ek_js = '''
  // ---------- tam önizleme: uygulamalar, düzenleyici, açılır çubuk ----------
  const uygAd = { safari: 'Safari', mail: 'Mail', mailyaz: 'Mail · ileti yazılıyor (Gönder, Dosya Ekle, öneriler)', takvim: 'Takvim · ay şeridi (gün/hafta görünümünde günler/haftalar)', hesap: 'Hesap Makinesi', muzik: 'Müzik · Sıradakine Ekle', finder: 'Finder' };
  Object.assign(durumYazi, { sekmeler: 'Safari sekmeleri · seçili sekmeye kayar', hizli: 'Touch Bar gösterir: Hızlı Eylemler (Servisler menüsü)', duzenle: "Control Strip'i Özelleştir · dokununca çıkar / ekle (en çok 5)", ekranresmi: '⇧⌘5 ekran resmi araç çubuğu', acilir: 'Açılır çubuk · parmağı kaydırıp bırakınca seçilir' });
  function uygulamaSec(a) {
    uygulama = a;
    durumYazi.uygulama = 'Uygulama: ' + uygAd[a] + ' · Control Strip daraltılmış';
    document.querySelectorAll('[data-secim="app"] button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.deger === a)));
    kipSec('uygulama');
  }
  document.querySelector('[data-secim="app"]').addEventListener('click', e => { const b = e.target.closest('button'); if (b) uygulamaSec(b.dataset.deger); }, true);
  // basılı tutma: data-uzun'daki panel açılır
  let uzunZaman;
  cubuk.addEventListener('pointerdown', e => { const t = e.target.closest('[data-uzun]'); if (t) uzunZaman = setTimeout(() => kipSec(t.dataset.uzun, true), 450); });
  ['pointerup', 'pointercancel', 'pointerleave'].forEach(o => cubuk.addEventListener(o, () => clearTimeout(uzunZaman)));
  // Control Strip düzenleyici
  const duzen = document.getElementById('duzen'), ekle = document.getElementById('ekle'), duzenEtiket = document.getElementById('duzenEtiket');
  function duzenYenile() { const dolu = duzen.children.length >= 5; duzenEtiket.textContent = dolu ? 'Şerit dolu' : 'Ekle:'; ekle.style.opacity = dolu ? .45 : 1; }
  cubuk.addEventListener('click', e => {
    const t = e.target.closest('[data-eylem="cikar"], [data-eylem="ekle"]'); if (!t) return;
    if (t.dataset.eylem === 'cikar') { t.dataset.eylem = 'ekle'; t.querySelector('.rozet-eksi').remove(); ekle.prepend(t); }
    else if (duzen.children.length < 5) { t.dataset.eylem = 'cikar'; t.insertAdjacentHTML('beforeend', '<i class="rozet-eksi"></i>'); duzen.append(t); }
    duzenYenile();
  });
  duzenYenile();
'''
html = html.replace("  cubuk.dataset.varyant = 'regular';", ek_js + "  cubuk.dataset.varyant = 'regular';\n  cubuk.dataset.tema = 'sade';", 1)
# genel dilim işleyicisi: tema/arka/sicak cubuk.dataset'e yazılır; arka "isik" ortam ışığını açar, sıcaklık --g
html = html.replace("    else { cubuk.dataset[d.dataset.secim] = b.dataset.deger;", """    else if (d.dataset.secim === 'app') return;
    else if (d.dataset.secim === 'sicak') { const g = +b.dataset.deger; if (g) { cubuk.dataset.sicak = '1'; cubuk.style.setProperty('--g', g); } else delete cubuk.dataset.sicak; d.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', String(x === b))); }
    else { cubuk.dataset[d.dataset.secim] = b.dataset.deger; if (d.dataset.secim === 'arka') { ortamAcik = b.dataset.deger === 'isik'; document.getElementById('aOrtam').checked = ortamAcik; }""", 1)
html = html.replace('<title>TouchBar2 Liquid Glass', '<title>TouchBar2 Önizleme', 1)
html = html.replace('<h1>TouchBar2 Liquid Glass</h1>', '<h1>TouchBar2 Önizleme</h1>', 1)

open(os.path.join(kok, 'touchbar2-onizleme.html'), 'w', encoding='utf-8').write(html)
print(len(html))
