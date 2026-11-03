# Maxfiylik siyosati

**Oxirgi yangilanish: 2026-yil 6-avgust**

PolyDev ilovasi (bundan keyin — «Ilova») mustaqil dasturchi xApi Devs («biz») tomonidan ishlab chiqilgan. Ushbu siyosat qanday ma'lumotlarni to'plashimiz, ulardan qanday foydalanishimiz va ularni qanday saqlashimizni tavsiflaydi.

## 1. Qanday ma'lumotlarni to'playmiz

### 1.1. Hisob ma'lumotlari
Google/Firebase Authentication orqali tizimga kirganingizda, biz serverda (Firestore) quyidagilarni saqlaymiz: elektron pochta manzilingiz, profil nomi, avatar havolasi, ro'yxatdan o'tgan va oxirgi kirgan sana, hamda qurilmangizning noyob identifikatori — bu faqat bitta tarifda bir vaqtning o'zida faol qurilmalar sonini cheklash uchun ishlatiladi.

### 1.2. Obuna ma'lumotlari
Xaridlar va obunalarni qayta ishlash uchun biz RevenueCat xizmatidan foydalanamiz, u o'z navbatida App Store/Google Play bilan bog'lanadi. Ilovadagi tegishli funksiyalarni ochish uchun obunangiz holatini (tarif, faol huquqlar, yangilanish sanasi) o'z bazamizda saqlaymiz. Bank kartangiz ma'lumotlarini hech qachon olmaymiz va saqlamaymiz — to'lovni to'liq Apple/Google amalga oshiradi.

### 1.3. Faqat qurilmangizda qoladigan ma'lumotlar
Loyihalaringiz mazmuni, kod, AI-agent bilan yozishmalar tarixi, uchinchi tomon AI-provayderlarning API-kalitlari va kirish tokenlari, shuningdek GitHub, Vercel va Cloudflare Pages kirish tokenlari **faqat qurilmangizda** (shifrlangan lokal xotirada) saqlanadi va **hech qachon bizning serverlarimizga uzatilmaydi**. Bizda bu ma'lumotlarga texnik kirish imkoniyati yo'q.

### 1.4. Uchinchi tomon AI-provayderlarga yuboriladigan ma'lumotlar
Agar o'z API-kalitingizdan (OpenAI, Anthropic, Google va boshqalar) foydalansangiz, so'rovlaringiz mazmuni (xabarlar, kod) tanlagan provayderingizga to'g'ridan-to'g'ri yuboriladi va ularning o'z maxfiylik siyosatiga muvofiq qayta ishlanadi — biz vositachi bo'lmaymiz va bu so'rovlar mazmunini hech qachon ko'rmaymiz. Agar ilovaning o'rnatilgan AI-provayderidan foydalansangiz, so'rovlar bizning proksi-serverimiz (OpenRouter) orqali yo'naltiriladi — bunday so'rovlar mazmunini qayta ishlash uchun zarur bo'lgandan ortiq saqlamaymiz.

### 1.5. GitHub, Vercel, Cloudflare Pages
GitHub, Vercel yoki Cloudflare Pages hisobingizni ulasangiz, tegishli kirish tokeni faqat qurilmangizda saqlanadi va faqat siz o'zingiz boshlagan amallar (kodni push qilish, deploy qilish) uchun ishlatiladi. Bu tokenning nusxasini hech qachon o'z serverlarimizda olmaymiz.

### 1.6. Push-bildirishnomalar va yangiliklarga yoqtirish
Agar push-bildirishnomalarga ruxsat bersangiz, biz Firebase Cloud Messaging qurilma tokenini olamiz va uni yangiliklar mavzusiga obuna qilamiz — bu faqat yangiliklar bo'limidagi yangi materiallar haqida bildirishnoma yuborish uchun ishlatiladi. Agar yangilikni yoqtirsangiz, biz bu faktni (qaysi yangiliklarni yoqtirganingizni) hisobingizga bog'langan holda o'z bazamizda saqlaymiz.

### 1.7. Foydalanish statistikasi
Ilova funksiyalaridan qaysilari ishlatilishini tushunish uchun Firebase Analytics (Google) dan foydalanamiz: ilovani ochish, loyiha yaratish, agentga xabar yuborish, deploy va tanlangan AI-provayder turi. Anonim hodisalar, ilova o'rnatilishi identifikatori va qurilmaning umumiy ma'lumotlari (model, OT versiyasi, til, mamlakat) yig'iladi. Xabar matnlari, kod, fayl nomlari, kalitlar va tokenlar u yerga **yuborilmaydi**. Reklama identifikatoridan foydalanilmaydi. Statistikani Sozlamalar → «Foydalanish statistikasi» orqali o'chirish mumkin.

## 2. Ma'lumotlardan qanday foydalanamiz

To'plangan ma'lumotlardan quyidagi maqsadlarda foydalanamiz:
- Sizni autentifikatsiya qilish va obuna holatini qurilmalaringiz orasida sinxronlashtirish;
- To'langan tarifingizga muvofiq funksiyalarni ochish;
- Bitta obunada bir vaqtning o'zida faol qurilmalar sonini cheklash;
- Ilova ichidagi yangiliklar bo'limini ko'rsatish;
- Qo'llab-quvvatlash so'rovlaringizga javob berish.

Biz reklama ko'rsatmaymiz va shaxsiy ma'lumotlaringizni marketing maqsadlarida uchinchi shaxslarga sotmaymiz yoki ulashmaymiz.

## 3. Ma'lumotlarni saqlash va o'chirish

Hisob ma'lumotlari (1.1–1.2-bandlar) hisobingiz faol bo'lgan davrda saqlanadi. Hisobingizni va u bilan bog'liq server ma'lumotlarini to'liq o'chirishni support@polydev.app manziliga yozib so'rashingiz mumkin. Lokal ma'lumotlar (loyihalar, chat tarixi, API-kalitlari) ilovani qurilmadan o'chirganingizda yoki ilova sozlamalaridan qo'lda tozalanganda darhol o'chiriladi.

## 4. Bolalar

Ilova 13 yoshgacha bo'lgan bolalarga mo'ljallanmagan va biz ularning ma'lumotlarini bilib turib to'plamaymiz.

## 5. Xavfsizlik

Biz sanoat standartlariga mos himoya choralarini (uzatishda shifrlash, sirlar uchun xavfsiz lokal xotira) qo'llaymiz, ammo barcha mumkin bo'lgan tahdidlardan mutlaq himoyani kafolatlay olmaymiz.

## 6. Ushbu siyosatdagi o'zgarishlar

Biz ushbu siyosatni vaqti-vaqti bilan yangilashimiz mumkin. Muhim o'zgarishlar sahifa boshidagi yangilangan sana bilan ushbu hujjatda aks ettiriladi.

## 7. Aloqa

Ushbu siyosat bo'yicha savollar uchun: support@polydev.app
