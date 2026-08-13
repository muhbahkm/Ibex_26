import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/core/errors/domain_error.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/runtime/local_business_bootstrap_service.dart';

void main() {
  late SpikeDatabase db;
  late LocalBusinessBootstrapService service;

  setUp(() {
    db = SpikeDatabase.inMemory();
    service = LocalBusinessBootstrapService(db);
  });

  tearDown(() => db.close());

  test('bootstrap creates business owner permissions and warehouse but no demo truth', () async {
    await service.execute(const LocalBusinessBootstrapRequest(
      businessId: 'B-PROD',
      ownerUserId: 'U-OWNER',
      businessName: 'باحكم للعسل',
      baseCurrencyCode: 'YER',
      utcOffsetMinutes: 180,
      defaultWarehouseId: 'WH-MAIN',
      defaultWarehouseName: 'المستودع الرئيسي',
    ));

    final settings = await db.select(db.businessSettings).getSingle();
    expect(settings.businessId, 'B-PROD');
    expect(settings.baseCurrencyCode, 'YER');
    expect(settings.utcOffsetMinutes, 180);
    expect(settings.onboardingComplete, isTrue);

    expect((await db.select(db.appUsers).get()).length, 1);
    expect((await db.select(db.roles).get()).length, 1);
    expect((await db.select(db.rolePermissions).get()).length, 9);
    expect((await db.select(db.warehouses).get()).length, 1);

    expect(await db.select(db.customers).get(), isEmpty);
    expect(await db.select(db.suppliers).get(), isEmpty);
    expect(await db.select(db.products).get(), isEmpty);
    expect(await db.select(db.fxRates).get(), isEmpty);
    expect(await db.select(db.inventoryBalances).get(), isEmpty);
  });

  test('bootstrap cannot silently replace an already completed business', () async {
    const request = LocalBusinessBootstrapRequest(
      businessId: 'B-PROD',
      ownerUserId: 'U-OWNER',
      businessName: 'باحكم للعسل',
      baseCurrencyCode: 'YER',
      utcOffsetMinutes: 180,
      defaultWarehouseId: 'WH-MAIN',
      defaultWarehouseName: 'الرئيسي',
    );
    await service.execute(request);

    expect(
      () => service.execute(request),
      throwsA(isA<DomainError>().having((e) => e.code, 'code', 'BUSINESS_ALREADY_BOOTSTRAPPED')),
    );
  });

  test('invalid timezone fails before writing partial bootstrap state', () async {
    expect(
      () => service.execute(const LocalBusinessBootstrapRequest(
        businessId: 'B-PROD',
        ownerUserId: 'U-OWNER',
        businessName: 'باحكم',
        baseCurrencyCode: 'YER',
        utcOffsetMinutes: 900,
        defaultWarehouseId: 'WH-MAIN',
        defaultWarehouseName: 'الرئيسي',
      )),
      throwsA(isA<DomainError>()),
    );
    expect(await db.select(db.businessSettings).get(), isEmpty);
    expect(await db.select(db.appUsers).get(), isEmpty);
  });
}
