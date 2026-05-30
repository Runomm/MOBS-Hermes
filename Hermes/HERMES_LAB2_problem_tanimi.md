# LAB 2 — Problem Tanımı ve Gereksinim Analizi

**Proje Adı:** Hermes — Çevrimdışı Akıllı Çeviri ve Not Asistanı  
**Öğrenci Adı:** Mehmet Onur Boyraz  
**Öğrenci No:** 245541023

---

## 3.1 Problem Tanımı

Yurt dışında eğitim gören öğrenciler, yabancı dilde verilen dersleri gerçek zamanlı olarak takip etmekte ve eş zamanlı not tutmakta ciddi güçlük çekmektedir. Turistler ise yabancı bir ülkede yerel halkla anlık iletişim kurabilmek için internet bağlantısına muhtaç araçlara bağımlı kalmaktadır. Mevcut çeviri uygulamaları internet olmadan çalışamamakta; roaming sorunu, yavaş bağlantı veya erişim kesintileri yaşandığında kullanıcılar tamamen çaresiz kalmaktadır.

Çözülmeye çalışılan temel problem: dil engelinin, internet bağımlısı mevcut araçlar nedeniyle ihtiyaç duyulan her an ve her ortamda aşılamamasıdır.

---

## 3.2 Hedef Kullanıcı

- **Birincil:** Yurt dışında üniversite eğitimi gören öğrenciler (Erasmus, değişim programları, uluslararası yüksek lisans)
- **İkincil:** Yabancı ülkelerde seyahat eden turistler

---

## 3.3 Problemin Önemi ve Etkisi

Avrupa'da her yıl 300.000'den fazla Erasmus öğrencisi yabancı dilde eğitim almaktadır. Bu öğrencilerin büyük çoğunluğu dersleri tam anlamıyla takip edemediği için akademik performansları olumsuz etkilenmektedir. Yurt dışı veri paketleri hem pahalı hem de sınırlıdır; internet bağlantısına bağımlı çeviri araçları bu ortamda güvenilir değildir.

Turistler için de benzer bir sorun söz konusudur: yerel halkla iletişim kurmak, yol sormak, restoranı anlamak gibi günlük ihtiyaçlar internet bağlantısı kesildiğinde çözümsüz kalmaktadır. Bu durum hem stres hem de zaman kaybı yaratmaktadır.

---

## 3.4 Uygulamanın Kapsamı

### İçereceği İşlevler

- Kullanıcının mikrofon aracılığıyla konuşmayı uygulamaya iletebilmesi
- Konuşmanın seçilen dile **tamamen internet bağlantısı olmadan** çevrilmesi
- Çevrilen metnin hem ekranda gösterilmesi hem de sesli olarak okunması
- **Ders Modu:** Tek yönlü sürekli çeviri; profesörün konuşması takip edilerek transkript biriktirilmesi
- **Konuşma Modu:** İki kişi arasında sıralı çift yönlü çeviri
- İnternet bağlantısı mevcut olduğunda biriken konuşmanın otomatik özetinin oluşturulması
- Geçmiş oturumların cihazda saklanması ve tekrar erişilebilmesi
- Oturum içeriğinin PDF belgesi olarak dışa aktarılması
- Derste öğrenilen yeni kelimelerin otomatik olarak ayrı bir listeye eklenmesi

### İçermeyeceği İşlevler

- Gerçek zamanlı video çevirisi
- Kamera ile fotoğraftan veya belgeden metin çevirisi *(ileri fazlar için planlanmıştır)*
- Sosyal medya entegrasyonu veya başkalarıyla oturum paylaşımı
- Ses kalitesi iyileştirme ve arka plan gürültüsü engelleme *(ileri fazlar için planlanmıştır)*
- Çeviri doğruluğunun tıbbi, hukuki veya resmi belgelerde garanti edilmesi
