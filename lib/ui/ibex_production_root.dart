import 'package:flutter/material.dart';

import '../core/errors/domain_error.dart';
import '../runtime/ibex_runtime_session.dart';
import '../runtime/local_business_bootstrap_service.dart';
import '../runtime/production_bootstrap_gateway.dart';
import '../runtime/spike_runtime_config.dart';
import '../security/local_installation_identity_store.dart';
import 'ibex_runtime_app.dart';

class IbexProductionRoot extends StatefulWidget {
  const IbexProductionRoot({super.key});

  @override
  State<IbexProductionRoot> createState() => _IbexProductionRootState();
}

class _IbexProductionRootState extends State<IbexProductionRoot> {
  IbexRuntimeSession? _session;
  LocalInstallationIdentity? _identity;
  SpikeRuntimeConfig? _config;
  bool _loading = true;
  bool _needsOnboarding = false;
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorCode = null;
      });
    }
    try {
      final identity = await LocalInstallationIdentityStore().loadOrCreate();
      final config = _productionConfig(identity);
      final session = await IbexRuntimeSession.open(config: config);
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _identity = identity;
        _config = config;
        _session = session;
        _needsOnboarding = false;
        _loading = false;
      });
    } on DomainError catch (error) {
      if (!mounted) return;
      if (error.code == 'BUSINESS_ONBOARDING_REQUIRED') {
        final identity = await LocalInstallationIdentityStore().loadOrCreate();
        setState(() {
          _identity = identity;
          _config = _productionConfig(identity);
          _needsOnboarding = true;
          _loading = false;
        });
      } else {
        setState(() {
          _errorCode = error.code;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorCode = error.runtimeType.toString();
        _loading = false;
      });
    }
  }

  SpikeRuntimeConfig _productionConfig(LocalInstallationIdentity identity) =>
      SpikeRuntimeConfig.production(
        businessId: identity.businessId,
        userId: identity.ownerUserId,
        defaultWarehouseId: 'WH-MAIN',
        // Persisted BusinessSettings is the runtime source of truth. This
        // constructor value is retained only for compatibility with the spike
        // config object and is never used to seed production data.
        baseCurrencyCode: 'YER',
        cashAccountId: 'CASH-MAIN',
        cashLedgerAccountId: 'ACC-CASH',
        salesRevenueAccountId: 'ACC-SALES',
        inventoryLedgerAccountId: 'ACC-INVENTORY',
        cogsLedgerAccountId: 'ACC-COGS',
        accountsReceivableLedgerAccountId: 'ACC-AR',
      );

  Future<void> _completeOnboarding({
    required String businessName,
    required String currency,
    required int utcOffsetMinutes,
    required String warehouseName,
  }) async {
    final identity = _identity;
    final config = _config;
    if (identity == null || config == null) return;
    await const ProductionBootstrapGateway().bootstrap(
      LocalBusinessBootstrapRequest(
        businessId: identity.businessId,
        ownerUserId: identity.ownerUserId,
        businessName: businessName,
        baseCurrencyCode: currency,
        utcOffsetMinutes: utcOffsetMinutes,
        defaultWarehouseId: config.defaultWarehouseId,
        defaultWarehouseName: warehouseName,
      ),
    );
    await _initialize();
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) {
      session.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return IbexRuntimeApp(controller: session.controller);
    }
    if (_loading) return const _LoadingApp();
    if (_needsOnboarding) {
      return _OnboardingApp(onComplete: _completeOnboarding);
    }
    return IbexRuntimeFailureApp(errorCode: _errorCode ?? 'STARTUP_FAILED');
  }
}

class _LoadingApp extends StatelessWidget {
  const _LoadingApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
}

class _OnboardingApp extends StatefulWidget {
  const _OnboardingApp({required this.onComplete});

  final Future<void> Function({
    required String businessName,
    required String currency,
    required int utcOffsetMinutes,
    required String warehouseName,
  }) onComplete;

  @override
  State<_OnboardingApp> createState() => _OnboardingAppState();
}

class _OnboardingAppState extends State<_OnboardingApp> {
  final _business = TextEditingController();
  final _currency = TextEditingController(text: 'YER');
  final _warehouse = TextEditingController(text: 'المستودع الرئيسي');
  int _utcOffsetMinutes = 180;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _business.dispose();
    _currency.dispose();
    _warehouse.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onComplete(
        businessName: _business.text,
        currency: _currency.text,
        utcOffsetMinutes: _utcOffsetMinutes,
        warehouseName: _warehouse.text,
      );
    } on DomainError catch (error) {
      if (mounted) setState(() => _error = error.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'ONBOARDING_FAILED');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0D6B57)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.storefront_outlined, size: 52),
                      const SizedBox(height: 16),
                      const Text(
                        'تهيئة IBEX على هذا الجهاز',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'لا يلزم إنشاء حساب. هذه البيانات تبقى محليًا داخل قاعدة IBEX المشفرة.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _business,
                        decoration: const InputDecoration(
                          labelText: 'اسم النشاط',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _currency,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 3,
                        decoration: const InputDecoration(
                          labelText: 'العملة الأساسية (مثل YER)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<int>(
                        value: _utcOffsetMinutes,
                        decoration: const InputDecoration(
                          labelText: 'التوقيت المحلي',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('UTC')),
                          DropdownMenuItem(value: 120, child: Text('UTC+02:00')),
                          DropdownMenuItem(value: 180, child: Text('UTC+03:00')),
                          DropdownMenuItem(value: 240, child: Text('UTC+04:00')),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _utcOffsetMinutes = value);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _warehouse,
                        decoration: const InputDecoration(
                          labelText: 'اسم المستودع الأساسي',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text('تعذر الحفظ: $_error'),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(_busy ? 'جارٍ التهيئة…' : 'بدء استخدام IBEX'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
