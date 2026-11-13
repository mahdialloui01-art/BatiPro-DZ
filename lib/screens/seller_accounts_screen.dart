import 'package:flutter/material.dart';
import '../app/app_language.dart';
import '../app/app_theme.dart';
import '../data/api_client.dart';

class SellerAccountsScreen extends StatefulWidget {
  const SellerAccountsScreen({super.key});
  @override
  State<SellerAccountsScreen> createState() => _SellerAccountsScreenState();
}

class _SellerAccountsScreenState extends State<SellerAccountsScreen> {
  List<Map<String, dynamic>> _sellers = [];
  bool _loading = true, _busy = false, _allowed = false;
  String? _error;
  String t(String ar, String fr) => AppLanguage.text(ar, fr);

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final me = await ApiClient.instance.me();
      if (!['owner', 'admin', 'manager'].contains(me['role']?.toString())) {
        throw StateError('هذه الصفحة مخصصة للمسؤول فقط.');
      }
      final sellers = await ApiClient.instance.sellers();
      if (!mounted) return;
      setState(() { _allowed = true; _sellers = sellers; });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addSeller() async {
    final name = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final confirm = TextEditingController();
    var obscure = true;
    final valid = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(t('إضافة حساب بائع جديد', 'Ajouter un vendeur')),
          content: SizedBox(width: 420, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: t('اسم البائع', 'Nom du vendeur'), prefixIcon: const Icon(Icons.badge_outlined))),
              const SizedBox(height: 10),
              TextField(controller: username, autocorrect: false, decoration: InputDecoration(labelText: t('اسم المستخدم', 'Nom d’utilisateur'), helperText: t('3 أحرف على الأقل، حروف وأرقام', '3 caractères minimum'), prefixIcon: const Icon(Icons.person_outline))),
              const SizedBox(height: 10),
              TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: t('الرقم السري', 'Mot de passe'), helperText: t('8 أحرف أو أرقام على الأقل', '8 caractères minimum'), prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => refresh(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)))),
              const SizedBox(height: 10),
              TextField(controller: confirm, obscureText: true, decoration: InputDecoration(labelText: t('تأكيد الرقم السري', 'Confirmer le mot de passe'), prefixIcon: const Icon(Icons.lock_reset_outlined))),
            ]),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t('إلغاء', 'Annuler'))),
            FilledButton.icon(onPressed: () {
              if (name.text.trim().length < 2 || username.text.trim().length < 3 ||
                  !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username.text.trim()) ||
                  password.text.length < 8 || password.text != confirm.text) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(t('تحقق من البيانات والرقم السري.', 'Vérifiez les informations et le mot de passe.'))));
                return;
              }
              Navigator.pop(dialogContext, true);
            }, icon: const Icon(Icons.person_add_alt_1), label: Text(t('إنشاء الحساب', 'Créer le compte'))),
          ],
        ),
      ),
    );
    if (valid != true || !mounted) {
      name.dispose(); username.dispose(); password.dispose(); confirm.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.instance.createSeller(username: username.text, displayName: name.text, password: password.text);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('تم إنشاء حساب البائع في قاعدة البيانات المشتركة.', 'Compte vendeur créé dans la base partagée.'))));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      name.dispose(); username.dispose(); password.dispose(); confirm.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate(Map<String, dynamic> seller) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('تعطيل حساب البائع؟', 'Désactiver ce compte ?')),
        content: Text(t('لن يستطيع \${seller['display_name']} الدخول بعد التعطيل، وتبقى فواتيره محفوظة.', 'Ce vendeur ne pourra plus se connecter. Ses factures seront conservées.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('إلغاء', 'Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('تعطيل', 'Désactiver'))),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      await ApiClient.instance.deactivateSeller(seller['id'].toString());
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('حسابات البيع', 'Comptes vendeurs'))),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : !_allowed ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? t('الدخول غير مسموح.', 'Accès refusé.'))))
      : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(color: BatiProTheme.ink, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            const Icon(Icons.groups_rounded, color: BatiProTheme.gold, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('إدارة حسابات البائعين', 'Gestion des vendeurs'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              Text(t('لكل بائع اسم مستخدم ورقم سري خاص به.', 'Chaque vendeur possède son identifiant et son mot de passe.'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ])),
          ]))),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _addSeller, icon: const Icon(Icons.person_add_alt_1), label: Text(t('إضافة حساب بيع جديد', 'Ajouter un compte vendeur'))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text(t('الحسابات المسجلة', 'Comptes enregistrés'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: BatiProTheme.ink))),
            Text('\${_sellers.where((s) => s['is_active'] == true).length}'),
          ]),
          const SizedBox(height: 8),
          if (_sellers.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(t('لم تضف أي حساب بيع بعد.', 'Aucun vendeur ajouté.'))))),
          for (final seller in _sellers) Card(child: ListTile(
            leading: CircleAvatar(backgroundColor: BatiProTheme.gold.withValues(alpha: .2), child: const Icon(Icons.point_of_sale, color: BatiProTheme.ink)),
            title: Text(seller['display_name']?.toString() ?? ''),
            subtitle: Text('@\${seller['username'] ?? ''} • \${seller['is_active'] == true ? t('نشط', 'Actif') : t('معطّل', 'Désactivé')}'),
            trailing: seller['is_active'] == true
              ? IconButton(tooltip: t('تعطيل الحساب', 'Désactiver'), onPressed: _busy ? null : () => _deactivate(seller), icon: const Icon(Icons.block_rounded, color: Colors.redAccent))
              : const Icon(Icons.lock_outline, color: BatiProTheme.muted),
          )),
          const SizedBox(height: 12),
          Text(t('الحسابات محفوظة في PostgreSQL ويمكن استخدامها على الأجهزة المتصلة بنفس الخادم. لا تشارك كلمة مرور قاعدة البيانات مع البائعين.', 'Les comptes sont stockés dans PostgreSQL et utilisables sur les appareils connectés au même serveur.'), style: const TextStyle(fontSize: 10, color: BatiProTheme.muted, height: 1.5)),
        ])),
  );
}
