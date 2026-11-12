import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app/app_theme.dart';
import '../app/app_language.dart';
import '../app/batipro_app.dart';
import 'sales_screen.dart';

/// Separates manager and seller sessions at the application entry point.
class AccountGate extends StatefulWidget {
  const AccountGate({super.key});

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  static const _storage = FlutterSecureStorage();
  static const _managerPinKey = 'batipro_manager_pin_v1';
  static const _sellerPinKey = 'batipro_seller_pin_v1';

  final _pin = TextEditingController();
  final _managerPin = TextEditingController();
  final _sellerPin = TextEditingController();
  final _confirmManager = TextEditingController();
  final _confirmSeller = TextEditingController();

  bool _loading = true;
  bool _setupRequired = false;
  bool _busy = false;
  String? _role;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pin.dispose();
    _managerPin.dispose();
    _sellerPin.dispose();
    _confirmManager.dispose();
    _confirmSeller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final manager = await _storage.read(key: _managerPinKey);
      final seller = await _storage.read(key: _sellerPinKey);
      if (!mounted) return;
      setState(() {
        _setupRequired = manager == null || seller == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر فتح التخزين الآمن على هذا الجهاز.';
        _loading = false;
      });
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  bool _validPin(String value) => RegExp(r'^\\d{4,8}$').hasMatch(value);

  Future<void> _savePins() async {
    if (_busy) return;
    final manager = _managerPin.text;
    final seller = _sellerPin.text;
    if (!_validPin(manager) || !_validPin(seller)) {
      setState(() => _error = 'كل رمز لازم يكون من 4 إلى 8 أرقام.');
      return;
    }
    if (manager != _confirmManager.text || seller != _confirmSeller.text) {
      setState(() => _error = 'تأكيد الرموز غير مطابق.');
      return;
    }
    if (manager == seller) {
      setState(() => _error = 'اختار رمزاً مختلفاً لكل حساب.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _storage.write(key: _managerPinKey, value: manager);
      await _storage.write(key: _sellerPinKey, value: seller);
      if (!mounted) return;
      setState(() {
        _setupRequired = false;
        _role = null;
        _pin.clear();
      });
      _message('تم إعداد رمزي المسؤول والبائع. احتفظ بهما في مكان آمن.');
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر حفظ الرموز في التخزين الآمن.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (_role == null || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final key = _role == 'manager' ? _managerPinKey : _sellerPinKey;
      final saved = await _storage.read(key: key);
      if (saved == null || _pin.text != saved) {
        setState(() => _error = 'الرمز السري غير صحيح.');
        return;
      }
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر التحقق من الرمز السري.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _logout() {
    setState(() {
      _role = null;
      _pin.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_setupRequired) return _setupPage();

    return _activePage();
  }

  Widget _activePage() {
    if (_authenticatedRole == 'manager') {
      return AppShell(onLogout: () {
        setState(() {
          _authenticatedRole = null;
          _role = null;
          _pin.clear();
        });
      });
    }
    if (_authenticatedRole == 'seller') {
      return Scaffold(
        body: SafeArea(
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF173B68), Color(0xFF245A9A)]),
              ),
              child: Row(children: [
                const Icon(Icons.point_of_sale_rounded, color: BatiProTheme.gold),
                const SizedBox(width: 8),
                Expanded(child: Text(AppLanguage.text('حساب البائع', 'Compte vendeur'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, color: Colors.white, size: 17),
                  label: Text(AppLanguage.text('خروج', 'Quitter'), style: const TextStyle(color: Colors.white)),
                ),
              ]),
            ),
            const Expanded(child: SalesScreen(sellerName: 'البائع')),
          ]),
        ),
      );
    }
    return _loginPage();
  }

  String? _authenticatedRole;

  Widget _setupPage() {
    final french = AppLanguage.isFrench;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.admin_panel_settings_rounded, size: 48, color: BatiProTheme.ink),
                    const SizedBox(height: 12),
                    Text(french ? 'Sécuriser les deux comptes' : 'إعداد رموز الحسابات',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(french ? 'Créez un code distinct pour le responsable et le vendeur.' : 'أنشئ رمزاً خاصاً بالمسؤول ورمزاً مختلفاً بالبائع. هذه الخطوة تتم مرة واحدة.',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: BatiProTheme.muted)),
                    const SizedBox(height: 18),
                    _pinField(_managerPin, french ? 'Code du responsable (4 à 8 chiffres)' : 'كود المسؤول (4 إلى 8 أرقام)'),
                    const SizedBox(height: 9),
                    _pinField(_confirmManager, french ? 'Confirmer le code du responsable' : 'تأكيد كود المسؤول'),
                    const SizedBox(height: 14),
                    _pinField(_sellerPin, french ? 'Code du vendeur (4 à 8 chiffres)' : 'كود البائع (4 إلى 8 أرقام)'),
                    const SizedBox(height: 9),
                    _pinField(_confirmSeller, french ? 'Confirmer le code du vendeur' : 'تأكيد كود البائع'),
                    if (_error != null) _errorText(),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _savePins,
                      child: Text(french ? 'Enregistrer les codes' : 'حفظ الرموز والمتابعة'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginPage() {
    final french = AppLanguage.isFrench;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.storefront_rounded, size: 48, color: BatiProTheme.ink),
                    const SizedBox(height: 10),
                    const Text('BatiPro DZ', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
                    const SizedBox(height: 5),
                    Text(french ? 'Choisissez le compte à ouvrir' : 'اختار الحساب الذي تريد الدخول إليه',
                      textAlign: TextAlign.center, style: const TextStyle(color: BatiProTheme.muted, fontSize: 12)),
                    const SizedBox(height: 20),
                    _roleTile('manager', Icons.admin_panel_settings_outlined,
                      french ? 'Responsable' : 'حساب المسؤول',
                      french ? 'Gestion complète du magasin' : 'إدارة كاملة للمحل'),
                    const SizedBox(height: 9),
                    _roleTile('seller', Icons.point_of_sale_rounded,
                      french ? 'Vendeur' : 'حساب البائع',
                      french ? 'Écran de vente uniquement' : 'واجهة البيع فقط'),
                    if (_role != null) ...[
                      const SizedBox(height: 16),
                      _pinField(_pin, french ? 'Code secret' : 'الكود السري'),
                      if (_error != null) _errorText(),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : () async {
                          final selectedRole = _role!;
                          await _login();
                          if (!mounted || _error != null) return;
                          setState(() => _authenticatedRole = selectedRole);
                        },
                        icon: const Icon(Icons.lock_open_rounded),
                        label: Text(french ? 'Entrer' : 'دخول'),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleTile(String role, IconData icon, String title, String subtitle) {
    final selected = _role == role;
    return InkWell(
      onTap: () => setState(() { _role = role; _pin.clear(); _error = null; }),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF1F8) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? BatiProTheme.ink : const Color(0xFFDCE4EC), width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, size: 28, color: BatiProTheme.ink),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: BatiProTheme.muted)),
          ])),
          if (selected) const Icon(Icons.check_circle, color: BatiProTheme.ink),
        ]),
      ),
    );
  }

  Widget _pinField(TextEditingController controller, String label) => TextField(
    controller: controller,
    obscureText: true,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
    decoration: InputDecoration(isDense: true, labelText: label, prefixIcon: const Icon(Icons.pin_outlined)),
  );

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(top: 9),
    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
  );
}
