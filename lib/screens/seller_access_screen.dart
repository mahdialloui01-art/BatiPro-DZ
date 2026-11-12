import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app/app_theme.dart';
import 'sales_screen.dart';

/// Android seller access. The first account is provisioned on this device,
/// then credentials are kept in Android Keystore via flutter_secure_storage.
class SellerAccessScreen extends StatefulWidget {
  const SellerAccessScreen({super.key});

  @override
  State<SellerAccessScreen> createState() => _SellerAccessScreenState();
}

class _SellerAccessScreenState extends State<SellerAccessScreen> {
  static const _storage = FlutterSecureStorage();
  static const _userKey = 'batipro_seller_username';
  static const _passKey = 'batipro_seller_password';
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = true;
  bool _configured = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _sellerName;

  @override
  void initState() {
    super.initState();
    _checkAccount();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _checkAccount() async {
    final user = await _storage.read(key: _userKey);
    if (!mounted) return;
    setState(() {
      _configured = user != null && user.isNotEmpty;
      _loading = false;
    });
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim();
    final password = _password.text;
    if (username.length < 3) {
      setState(() => _error = 'اسم المستخدم يجب أن يحتوي على 3 أحرف على الأقل.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'كلمة المرور يجب أن تحتوي على 6 أحرف على الأقل.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (!_configured) {
        if (password != _confirm.text) {
          setState(() => _error = 'تأكيد كلمة المرور غير مطابق.');
          return;
        }
        await _storage.write(key: _userKey, value: username);
        await _storage.write(key: _passKey, value: password);
        if (!mounted) return;
        setState(() { _configured = true; _sellerName = username; });
        _message('تم إنشاء حساب البائع على هذا الجهاز. احتفظ ببيانات الدخول.');
      } else {
        final savedUser = await _storage.read(key: _userKey);
        final savedPass = await _storage.read(key: _passKey);
        if (username != savedUser || password != savedPass) {
          setState(() => _error = 'اسم المستخدم أو كلمة المرور غير صحيحة.');
          return;
        }
        setState(() => _sellerName = username);
      }
    } catch (_) {
      setState(() => _error = 'تعذر الوصول إلى التخزين الآمن على هذا الجهاز.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sellerName != null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                color: BatiProTheme.ink,
                child: Row(children: [
                  const Icon(Icons.point_of_sale_rounded, color: BatiProTheme.gold),
                  const SizedBox(width: 9),
                  Expanded(child: Text('واجهة البائع • $_sellerName',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                  TextButton.icon(
                    onPressed: () => setState(() => _sellerName = null),
                    icon: const Icon(Icons.logout, color: Colors.white, size: 17),
                    label: const Text('خروج', style: TextStyle(color: Colors.white)),
                  ),
                ]),
              ),
              const Expanded(child: SalesScreen()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Container(
                            height: 62, width: 62,
                            decoration: BoxDecoration(color: BatiProTheme.ink, borderRadius: BorderRadius.circular(18)),
                            child: const Icon(Icons.storefront_rounded, color: BatiProTheme.gold, size: 31),
                          ),
                          const SizedBox(height: 17),
                          Text(_configured ? 'دخول حساب البائع' : 'إنشاء حساب البائع',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
                          const SizedBox(height: 6),
                          Text(_configured
                              ? 'أدخل بيانات الحساب للانتقال إلى شاشة البيع.'
                              : 'أنشئ بيانات حساب البائع لأول مرة على هذا الجهاز. قم بهذه الخطوة بصفتك المدير.',
                            style: const TextStyle(fontSize: 12, color: BatiProTheme.muted, height: 1.5)),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_outline)),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _password,
                            obscureText: !_showPassword,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                              ),
                            ),
                          ),
                          if (!_configured) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _confirm,
                              obscureText: !_showPassword,
                              decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور', prefixIcon: Icon(Icons.lock_reset)),
                            ),
                          ],
                          if (_error != null) Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: _busy
                                  ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.login_rounded),
                              label: Text(_configured ? 'دخول إلى البيع' : 'إنشاء الحساب والمتابعة'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text('بيانات الدخول تُحفظ في التخزين الآمن لنظام Android على هذا الجهاز.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: BatiProTheme.muted)),
                        ]),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
