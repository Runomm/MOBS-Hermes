# LAB 4 — Wireframe ve Ekran Akışı

**Proje Adı:** Hermes — Çevrimdışı Akıllı Çeviri ve Not Asistanı  
**Öğrenci Adı:** Mehmet Onur Boyraz  
**Öğrenci No:** 245541023

---

## 1. EKRAN: Ana Ekran
*(Yönergedeki "Liste / Ana Ekran" zorunluluğunu karşılar)*

**Ekran Adı:** Ana Ekran / Mod Seçimi

```
┌─────────────────────────────────┐
│  ☰                 HERMES   ⚙  │
│─────────────────────────────────│
│                                 │
│  Mod Seçin:                     │
│  ┌─────────────┐ ┌─────────────┐│
│  │  DERS MODU  │ │  KONUŞMA   ││
│  │             │ │    MODU    ││
│  │ (Tek yönlü) │ │(Çift yönlü)││
│  └─────────────┘ └─────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │   +  YENİ OTURUM BAŞLAT    ││
│  └─────────────────────────────┘│
│                                 │
│  Geçmiş Oturumlar               │
│  ┌─────────────────────────────┐│
│  │ 📝  İspanyolca Dersi        ││
│  │     15.05.2025  ·  45 dk   ││
│  │                    [Aç >]  ││
│  └─────────────────────────────┘│
│  ┌─────────────────────────────┐│
│  │ 💬  Restoran Konuşması      ││
│  │     14.05.2025  ·   8 dk   ││
│  │                    [Aç >]  ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

**Temel Bileşenler:**
- Mod seçim kartları (Ders / Konuşma)
- Büyük eylem butonu: "Yeni Oturum Başlat"
- Geçmiş oturumlar listesi (tarih, süre, dil çifti, açma butonu)
- Ayarlar ikonu (dil seçimi, hız/doğruluk tercihi)

---

## 2. EKRAN: Aktif Çeviri Ekranı
*(Yönergedeki "Veri Ekleme Ekranı" zorunluluğunu karşılar — kullanıcı konuşarak veri girer)*

**Ekran Adı:** Aktif Çeviri / Oturum Ekranı

```
┌─────────────────────────────────┐
│  ← Geri       DERS MODU    ⚡🎯 │
│─────────────────────────────────│
│       Türkçe  ────────  İspanyolca     │
│─────────────────────────────────│
│                                 │
│  ┌─────────────────────────────┐│
│  │  Kaynak Metin               ││
│  │  "El examen será la         ││
│  │   próxima semana..."        ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │  Çeviri                     ││
│  │  "Sınav gelecek hafta       ││
│  │   olacak..."                ││
│  └─────────────────────────────┘│
│                                 │
│  ████████████████░░░░  (ses)    │
│─────────────────────────────────│
│  ┌──────────────┐ ┌───────────┐ │
│  │  ⏸ Duraklat  │ │ ■  Bitir  │ │
│  └──────────────┘ └───────────┘ │
└─────────────────────────────────┘
```

**Temel Bileşenler:**
- Aktif dil çifti göstergesi
- Hız/Doğruluk toggle'ı (⚡ = hızlı, 🎯 = doğru)
- Kaynak metin alanı (orijinal konuşma)
- Çeviri metin alanı
- Ses seviyesi göstergesi
- Duraklat ve Bitir butonları

---

## 3. EKRAN: Oturum Özeti ve Detay
*(Yönergedeki "Detay / Güncelleme Ekranı" zorunluluğunu karşılar)*

**Ekran Adı:** Oturum Özeti

```
┌─────────────────────────────────┐
│  ← Geri          OTURUM ÖZETİ  │
│─────────────────────────────────│
│  📅 15.05.2025  ·  45 dakika    │
│  🌐 İspanyolca → Türkçe         │
│─────────────────────────────────│
│  ┌─────────────────────────────┐│
│  │  ✨  ÖZET OLUŞTUR           ││
│  │     (İnternet gerektirir)   ││
│  └─────────────────────────────┘│
│                                 │
│  Özet:                          │
│  • Sınav gelecek hafta Salı     │
│  • Konu: diferansiyel denklemler│
│  • Ödev: sayfa 45–50            │
│                                 │
│  Yeni Kelimeler:                │
│  ┌─────────────────────────────┐│
│  │  ecuación  →  denklem       ││
│  │  derivada  →  türev         ││
│  └─────────────────────────────┘│
│─────────────────────────────────│
│  Tam Transkript:                │
│  ┌─────────────────────────────┐│
│  │  09:02  "El examen será..." ││
│  │  09:07  "También necesitan" ││
│  └─────────────────────────────┘│
│─────────────────────────────────│
│  ┌─────────────────────────────┐│
│  │     📄  PDF OLARAK KAYDET   ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

**Temel Bileşenler:**
- Oturum meta bilgisi (tarih, süre, dil çifti)
- Özet oluştur butonu (online özellik)
- Otomatik oluşturulan özet alanı
- Yeni kelimeler listesi
- Tam transkript listesi
- PDF kaydet butonu

---

## Ekran Akışları

**Akış 1 — Yeni Ders Oturumu** *(Senaryo 1 ile uyumlu)*
```
[Ana Ekran]
    → (Kullanıcı "Ders Modu" seçer, "Yeni Oturum Başlat" basar)
[Aktif Çeviri Ekranı — Ders Modu]
    → (Ders boyunca transkript birikir, kullanıcı "Bitir" basar)
[Oturum Özeti Ekranı]
    → (Kullanıcı "Geri" basar)
[Ana Ekran]
```

**Akış 2 — Konuşma Modu** *(Senaryo 2 ile uyumlu)*
```
[Ana Ekran]
    → (Kullanıcı "Konuşma Modu" seçer, "Yeni Oturum Başlat" basar)
[Aktif Çeviri Ekranı — Konuşma Modu]
    → (Çift yönlü çeviri tamamlanır, "Bitir" basar)
[Oturum Özeti Ekranı]
    → (Kullanıcı "Geri" basar)
[Ana Ekran]
```

**Akış 3 — Geçmiş Oturum İnceleme** *(Senaryo 3 ile uyumlu)*
```
[Ana Ekran]
    → (Kullanıcı listeden geçmiş oturuma "Aç" basar)
[Oturum Özeti Ekranı]
    → (Kullanıcı "Geri" basar)
[Ana Ekran]
```
