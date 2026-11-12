import 'package:flutter_test/flutter_test.dart';
import 'package:batipro_dz/app/app_language.dart';

void main() {
  tearDown(() => AppLanguage.set('ar'));

  test('Arabic remains unchanged in Arabic mode', () {
    AppLanguage.set('ar');
    expect(AppLanguage.translate('لوحة القيادة'), 'لوحة القيادة');
  });

  test('translates core navigation and dashboard labels into French', () {
    AppLanguage.set('fr');
    expect(AppLanguage.translate('لوحة القيادة'), 'Tableau de bord');
    expect(AppLanguage.translate('المنتجات والمخزون'), 'Produits et stock');
    expect(AppLanguage.translate('مبيعات اليوم'), 'Ventes du jour');
  });

  test('translates dynamic centime amounts without losing the value', () {
    AppLanguage.set('fr');
    expect(AppLanguage.translate('1250 سنتيم'), '1250 centimes');
  });

  test('switches language labels without changing Arabic source values', () {
    AppLanguage.set('ar');
    expect(AppLanguage.text('البيع والشراء', 'Ventes et achats'), 'البيع والشراء');
    AppLanguage.set('fr');
    expect(AppLanguage.text('البيع والشراء', 'Ventes et achats'), 'Ventes et achats');
    expect(AppLanguage.text('وضع العمل دون إنترنت', 'Mode hors ligne'), 'Mode hors ligne');
  });

  test('keeps language selection limited to supported locales', () {
    AppLanguage.set('fr');
    expect(AppLanguage.current.value, 'fr');
    AppLanguage.set('en');
    expect(AppLanguage.current.value, 'ar');
  });

  test('translates construction material names', () {
    AppLanguage.set('fr');
    expect(AppLanguage.translate('حديد تسليح T12'), 'Acier d’armature T12');
    expect(AppLanguage.translate('آجر 8 ثقوب'), 'Brique à 8 alvéoles');
  });
}
