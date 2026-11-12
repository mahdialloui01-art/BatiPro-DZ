import 'package:flutter/material.dart' hide Text;
import 'localized_text.dart';
import 'app_theme.dart';
import 'app_language.dart';
import '../screens/dashboard_screen.dart';
import '../screens/section_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/sales_screen.dart';

class BatiProApp extends StatelessWidget {
  const BatiProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BatiPro DZ',
      debugShowCheckedModeBanner: false,
      theme: BatiProTheme.light,
      home: ValueListenableBuilder<String>(
        valueListenable: AppLanguage.current,
        builder: (context, language, child) => Directionality(
          textDirection: language == 'fr' ? TextDirection.ltr : TextDirection.rtl,
          child: const AppShell(),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selected = 0;

  static final sections = [
    _NavItem(AppLanguage.isFrench ? 'Tableau de bord' : 'لوحة القيادة', Icons.grid_view_rounded),
    _NavItem(AppLanguage.isFrench ? 'Produits et stock' : 'المنتجات والمخزون', Icons.inventory_2_outlined),
    _NavItem(AppLanguage.isFrench ? 'Ventes et factures' : 'المبيعات والفواتير', Icons.point_of_sale_rounded),
    _NavItem(AppLanguage.isFrench ? 'Achats fournisseurs' : 'الشراء من المورد', Icons.shopping_cart_checkout_rounded),
    _NavItem(AppLanguage.isFrench ? 'Clients' : 'الزبائن', Icons.groups_2_outlined),
    _NavItem(AppLanguage.isFrench ? 'Fournisseurs' : 'الموردون', Icons.local_shipping_outlined),
    _NavItem(AppLanguage.isFrench ? 'Entrepôts' : 'المستودعات', Icons.warehouse_outlined),
    _NavItem(AppLanguage.isFrench ? 'Dépenses' : 'المصاريف', Icons.receipt_long_outlined),
    _NavItem(AppLanguage.isFrench ? 'Rapports' : 'التقارير', Icons.bar_chart_rounded),
    _NavItem(AppLanguage.isFrench ? 'Paramètres' : 'الإعدادات', Icons.settings_outlined),
  ];

  Widget _page() {
    if (selected == 0) return const DashboardScreen();
    if (selected == 1) return const InventoryScreen();
    if (selected == 2) return const SalesScreen();
    return SectionScreen(title: sections[selected].label, icon: sections[selected].icon);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      return Scaffold(
        body: Row(
          children: [
            if (wide) _Sidebar(
              items: sections,
              selected: selected,
              onSelect: (i) => setState(() => selected = i),
            ),
            Expanded(child: _page()),
          ],
        ),
        bottomNavigationBar: wide ? null : NavigationBar(
          selectedIndex: selected > 3 ? 4 : selected,
          onDestinationSelected: (i) {
            if (i == 4) {
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                backgroundColor: Colors.white,
                builder: (sheetContext) => _MoreSectionsSheet(
                  items: sections,
                  onSelect: (index) {
                    Navigator.pop(sheetContext);
                    setState(() => selected = index);
                  },
                ),
              );
            } else {
              setState(() => selected = i);
            }
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: AppLanguage.isFrench ? 'Accueil' : 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: AppLanguage.isFrench ? 'Stock' : 'المخزون'),
            NavigationDestination(icon: Icon(Icons.point_of_sale_rounded), label: AppLanguage.isFrench ? 'Ventes' : 'المبيعات'),
            NavigationDestination(icon: Icon(Icons.shopping_cart_checkout_rounded), label: AppLanguage.isFrench ? 'Achats' : 'المشتريات'),
            NavigationDestination(icon: Icon(Icons.menu_rounded), label: AppLanguage.isFrench ? 'Plus' : 'المزيد'),
          ],
        ),
      );
    });
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.items, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF142B3B), Color(0xFF203F53)]),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 25, 22, 28),
              child: Row(children: [
                Container(
                  width: 47, height: 47,
                  decoration: BoxDecoration(color: BatiProTheme.gold, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: BatiProTheme.gold.withValues(alpha: .18), blurRadius: 18, offset: Offset(0, 6))]),
                  child: const Icon(Icons.construction_rounded, color: BatiProTheme.ink, size: 27),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('BatiPro DZ', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  SizedBox(height: 3),
                  Text('GESTION • BÂTIMENT', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Color(0xFFB8C6D0), fontSize: 9, letterSpacing: 1.2)),
                ])),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: Text('القائمة الرئيسية', style: TextStyle(color: Color(0xFF91A5B4), fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final active = selected == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => onSelect(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: active ? const Color(0xFF34566A) : Colors.transparent,
                          borderRadius: BorderRadius.circular(13),
                          border: active ? Border.all(color: BatiProTheme.gold.withValues(alpha: .24)) : null,
                        ),
                        child: Row(children: [
                          Icon(items[i].icon, size: 19, color: active ? BatiProTheme.gold : const Color(0xFFB8C6D0)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(items[i].label, style: TextStyle(color: active ? Colors.white : const Color(0xFFD0DAE1), fontSize: 12.5, letterSpacing: .1, fontWeight: active ? FontWeight.w800 : FontWeight.w500))),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.all(15),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF233F52), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withValues(alpha: .08))),
              child: const Row(children: [
                Icon(Icons.cloud_off_outlined, color: BatiProTheme.gold, size: 19),
                SizedBox(width: 9),
                Expanded(child: Text('وضع العمل دون إنترنت', style: TextStyle(color: Colors.white, fontSize: 11))),
                Icon(Icons.circle, color: Color(0xFF48B58B), size: 8),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}


class _MoreSectionsSheet extends StatelessWidget {
  final List<_NavItem> items;
  final ValueChanged<int> onSelect;
  const _MoreSectionsSheet({required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final groups = <({String title, String subtitle, List<int> indexes})>[
      (title: 'البيع والشراء', subtitle: 'فواتير البيع وشراء السلع من الموردين', indexes: [3, 7]),
      (title: 'العلاقات التجارية', subtitle: 'إدارة الأشخاص المتعاملين معك', indexes: [4, 5]),
      (title: 'التنظيم والتحليل', subtitle: 'رتّب العمل وراقب النتائج', indexes: [6, 8, 9]),
    ];
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .86),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Column(
                children: [
                  Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD5DCE2), borderRadius: BorderRadius.circular(8))),
                  const SizedBox(height: 19),
                  Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: BatiProTheme.ink, borderRadius: BorderRadius.circular(15)),
                        child: const Icon(Icons.apps_rounded, color: BatiProTheme.gold, size: 25),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المزيد من BatiPro', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
                          SizedBox(height: 4),
                          Text('جميع أدوات إدارة محل مواد البناء', style: TextStyle(fontSize: 11, color: BatiProTheme.muted)),
                        ],
                      )),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: BatiProTheme.muted),
                        style: IconButton.styleFrom(backgroundColor: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                children: [
                  for (final group in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 13, 4, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(group.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: BatiProTheme.ink)),
                        const SizedBox(height: 3),
                        Text(group.subtitle, style: const TextStyle(fontSize: 10, color: BatiProTheme.muted)),
                      ]),
                    ),
                    for (final index in group.indexes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => onSelect(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                              child: Row(children: [
                                Container(
                                  width: 43, height: 43,
                                  decoration: BoxDecoration(
                                    color: BatiProTheme.gold.withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(items[index].icon, color: BatiProTheme.ink, size: 21),
                                ),
                                const SizedBox(width: 13),
                                Expanded(child: Text(items[index].label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: BatiProTheme.ink))),
                                const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: BatiProTheme.muted),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: BatiProTheme.ink,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(children: [
                      Icon(Icons.cloud_off_rounded, color: BatiProTheme.gold, size: 19),
                      SizedBox(width: 10),
                      Expanded(child: Text('تقدر تخدم على بياناتك حتى بدون إنترنت', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600))),
                      Icon(Icons.check_circle_rounded, color: Color(0xFF58C99B), size: 16),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
