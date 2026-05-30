# LAB 6 — Yazılım Mimarisi ve Veri Akışı

**Proje Adı:** Hermes — Çevrimdışı Akıllı Çeviri ve Not Asistanı  
**Öğrenci Adı:** Mehmet Onur Boyraz  
**Öğrenci No:** 245541023

---

## 1. Mimari Bileşenlerin Belirlenmesi

Hermes, tüm ağır işlemi kullanıcının kendi cihazında gerçekleştiren "cihaz-öncelikli" bir mimariyle tasarlanmıştır. Harici sunucuya bağımlılık yoktur; yalnızca özet özelliği isteğe bağlı olarak bulut servisini kullanır.

- **Kullanıcı Arayüzü (UI):** Flutter ile geliştirilen ekranlar — Ana Ekran, Aktif Çeviri, Oturum Özeti.
- **İş Mantığı:** Oturum Yöneticisi (kayıt başlatma/durdurma), Strateji Motoru (STT + Çeviri + TTS), Özet İstemcisi (Gemini API).
- **Veri Katmanı:** Yerel SQLite veritabanı (transkriptler, geçmiş) ve isteğe bağlı Gemini Flash API (özet).

---

## 2. Katmanlı Yapı ve Mimari Şema

```
┌──────────────────────────────────────────────────────────┐
│              A. SUNUM KATMANI (Flutter UI)               │
│                                                          │
│   [Ana Ekran]  [Aktif Çeviri Ekranı]  [Oturum Özeti]    │
└───────────────────────┬──────────────────────────────────┘
                        │ kullanıcı etkileşimi
┌───────────────────────▼──────────────────────────────────┐
│           B. İŞ MANTIĞI KATMANI (Cihaz İçi)             │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │              Oturum Yöneticisi                      │ │
│  │   (kayıt başlat / duraklat / bitir / kaydet)        │ │
│  └──────────────┬──────────────────────────────────────┘ │
│                 │                                         │
│  ┌──────────────▼──────────────────────────────────────┐ │
│  │           Strateji Motoru (Strategy Pattern)        │ │
│  │                                                     │ │
│  │  [STT Arayüzü]  [Çeviri Arayüzü]  [TTS Arayüzü]   │ │
│  │       ↓               ↓                ↓           │ │
│  │  whisper.cpp    Google ML Kit     Native OS TTS    │ │
│  │  (tiny/small)  (offline, 30MB/dil)  (built-in)    │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │           Özet İstemcisi (Opsiyonel)                │ │
│  │   → Internet varsa: Gemini Flash API çağrısı        │ │
│  │   → Internet yoksa: "Bağlantı gerektirir" uyarısı  │ │
│  └─────────────────────────────────────────────────────┘ │
└───────────────────────┬──────────────────────────────────┘
                        │ okuma / yazma
┌───────────────────────▼──────────────────────────────────┐
│                C. VERİ KATMANI                           │
│                                                          │
│   [SQLite — Yerel]          [Gemini API — Bulut]        │
│   Transkriptler              Özet metinleri              │
│   Oturum geçmişi             (yalnızca online)           │
│   Kullanıcı tercihleri                                   │
└──────────────────────────────────────────────────────────┘
```

---

## 3. Veri Akışı

### Akış A — Ders Modu (Senaryo 1)

```
1. [Sunum] Kullanıcı "Ders Modu" seçer, oturumu başlatır.

2. [İş Mantığı] Oturum Yöneticisi kaydı başlatır.
   Mikrofon sürekli dinlemeye geçer.

3. [İş Mantığı — Strateji Motoru]
   ┌─────────────────────────────────────────────┐
   │ Adım 1: whisper.cpp                         │
   │   5 saniyelik ses parçası → metin           │
   │                                             │
   │ Adım 2: Google ML Kit Translation           │
   │   Kaynak metin → Hedef dil metni            │
   │                                             │
   │ Adım 3: Native TTS                          │
   │   Çeviri metni → Sesli çıktı               │
   └─────────────────────────────────────────────┘
   (Bu döngü oturum bitene kadar tekrar eder)

4. [Veri] Transkript bellekte biriktirilir; her 6 chunk'ta (≈30 saniye) tek
   bir transaction ile SQLite'a yazılır. Oturum bitince kalan buffer boşaltılır.

5. [Sunum] Ekranda kaynak metin ve çeviri güncellenir.

6. [İş Mantığı] Kullanıcı "Bitir" basar → Oturum Yöneticisi kaydı kapatır.

7. [Sunum] Özet Ekranına yönlendirilir.

8. [İş Mantığı — Opsiyonel] Internet varsa:
   Transkript → Gemini Flash API → Özet metni → Ekranda gösterilir.
```

### Akış B — Konuşma Modu (Senaryo 2)

```
1. [Sunum] Kullanıcı "Konuşma Modu" seçer.

2. [İş Mantığı] Sıralı dinleme başlar:
   → Kişi A konuşur → whisper.cpp → ML Kit → TTS (Kişi B'nin dili)
   → Kişi B konuşur → whisper.cpp → ML Kit → TTS (Kişi A'nın dili)
   (Her konuşma sonunda mikrofon karşı tarafa geçer)

3. [Veri] Her konuşma SQLite'a kaydedilir.

4. [Sunum] Ekranda her iki tarafın metni görünür.

5. [İş Mantığı] "Bitir" → Oturum kaydedilir → Özet Ekranı açılır.
```

---

**Not:** Strateji Motoru'ndaki her bileşen (STT, Çeviri, TTS) bağımsız bir arayüz üzerinden çağrıldığından, ileride herhangi bir motor tek bir sınıf değişikliğiyle güncellenebilir. Bu yapı uygulamanın uzun vadeli sürdürülebilirliğini garanti eder.
