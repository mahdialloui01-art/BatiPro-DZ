# BatiPro DZ

برنامج تسيير محل مواد البناء، بواجهة Flutter عربية RTL. التطوير الحالي موجّه إلى **Windows + PostgreSQL**، وتطوير Android مؤجّل.

## البنية الحالية

- **Windows:** تطبيق Flutter Desktop، تخزين محلي SQLite عبر `AppStorage` للعمل المحلي.
- **API:** FastAPI / Python 3.12.
- **Database:** PostgreSQL 16.
- **Authentication:** كلمات مرور PBKDF2-HMAC-SHA256، ورموز وصول HMAC موقّعة صالحة 12 ساعة.
- **Windows secure storage:** عنوان الخادم ورمز الدخول محفوظان عبر مخزن بيانات الاعتماد الآمن في Windows.
- **Transactions:** فواتير الشراء والبيع وحركات المخزون تُسجّل ضمن معاملات PostgreSQL ذرّية.

## تشغيل خادم PostgreSQL محلياً أو على Windows Server / Linux Server

1. انسخ `.env.example` إلى `.env`.
2. غيّر كلمة مرور PostgreSQL ومفتاح توقيع الرموز ومفتاح تأسيس أول حساب إلى قيم عشوائية قوية. لا ترفع ملف `.env` إلى Git ولا تشارك هذه المفاتيح.
3. شغّل Docker Compose:

```bash
docker compose up -d --build
```

4. افحص صحة الخدمة:
   - `http://localhost:8000/health/live`
   - `http://localhost:8000/health/ready`
5. افتح `http://localhost:8000/docs` على جهاز الخادم، واستعمل `POST /auth/register` لإنشاء المؤسسة والحساب الأول. يجب إرسال قيمة `BATIPRO_BOOTSTRAP_SECRET` الموجودة في ملف الخادم السري. هذا المفتاح للتأسيس الأول فقط، ولا يُدخل في تطبيق Windows.
6. في BatiPro DZ على Windows افتح **الإعدادات ← الاتصال بخادم PostgreSQL**، أدخل عنوان API ثم البريد وكلمة المرور اللذين أنشأتهما.

> **تنبيه أمني:** لا تعرّض منفذ API العام عبر HTTP غير المشفّر. عند الاتصال عبر الإنترنت استعمل HTTPS خلف reverse proxy مع شهادة TLS وجدار ناري ونسخ احتياطي دوري لقاعدة البيانات. ملف Compose يفتح المنفذ 8000 للشبكة المضيفة فقط؛ إعداد TLS والنشر العام مسؤولية بيئة الاستضافة.

## واجهات API المنفذة

- `GET /health/live` و`GET /health/ready`
- `POST /auth/register` و`POST /auth/login` و`GET /me`
- `GET /warehouses`
- `GET /products` و`POST /products`
- `GET /stock` و`POST /stock/adjustments`
- `GET/POST /suppliers` و`GET/POST /customers`
- `POST /purchases` و`POST /sales`

تتحقق الخدمة من عضوية المستخدم في المؤسسة في كل طلب، وتمنع الحسابات ذات دور `viewer` من الكتابة. حركات المخزون تستخدم مفاتيح idempotency لمنع تكرار التسجيل. فواتير البيع تتحقق من الرصيد المتاح قبل الخصم. شراء حديد التسليح بالوزن يحوّل الوزن إلى عدد القضبان من وزن القطعة المسجل على المنتج.

## حالة الربط بين تطبيق Windows والخادم

تمت إضافة عميل API إلى Flutter وواجهة إعداد عنوان الخادم وتسجيل الدخول. أضيفت أيضاً عملية **استيراد أولي لمرة واحدة** من SQLite إلى PostgreSQL: المنتجات والمخزون الحالي والموردون والزبائن وفواتير الشراء والبيع التاريخية. يُسجّل المخزون الحالي كرصد افتتاحي، وتُحفظ الفواتير التاريخية دون إعادة حركات مخزونها حتى لا تتضاعف الكميات. العملية محمية بمفتاح idempotency وبصمة الحمولة، وتبقى بيانات SQLite كما هي على الجهاز. **هذا ليس بعدُ مزامنة مستمرة ثنائية الاتجاه**: التعديلات الجديدة بعد الاستيراد، والعمل دون إنترنت مع طابور إرسال، ومعالجة التعارضات، واسترجاع النسخ الاحتياطية ما زالت مطلوبة.

لا توجد قاعدة PostgreSQL مستضافة أو بيانات دخول جاهزة ضمن المستودع؛ يجب نشر الخادم وضبط أسراره أولاً.

## التطوير والاختبارات

### Windows

```powershell
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build windows --release
```

### Backend / PostgreSQL

```bash
pip install -r backend/requirements.txt
python backend/scripts/migrate.py
cd backend
PYTHONPATH=. pytest -q
```

GitHub Actions يشغّل بناء Windows واختبار تشغيل EXE، ويختبر Backend على PostgreSQL 16.

## بيانات مهمة

- ملفات SQLite المحلية تبقى على جهاز Windows حتى يتم تنفيذ مزامنة موثوقة.
- لا تحذف بيانات SharedPreferences القديمة يدوياً؛ عملية الترحيل القديمة تنقل مفاتيح `batipro_` إلى SQLite وتحتفظ بالأصل.
- لا توجد حالياً مزامنة Offline/Online مكتملة، ولا استعادة تلقائية من النسخ الاحتياطي.
