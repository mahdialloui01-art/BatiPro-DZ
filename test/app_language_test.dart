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

  test('translates construction material names', () {
    AppLanguage.set('fr');
    expect(AppLanguage.translate('حديد تسليح T12'), 'Acier d’armature T12');
    expect(AppLanguage.translate('آجر 8 ثقوب'), 'Brique à 8 alvéoles');
  });
}
