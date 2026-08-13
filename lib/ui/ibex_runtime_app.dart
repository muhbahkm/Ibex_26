import 'package:flutter/material.dart';

import '../presentation/sale_chat_controller.dart';
import 'ibex_operational_shell_v2.dart';

class IbexRuntimeApp extends StatelessWidget {
  const IbexRuntimeApp({super.key, required this.controller});

  final SaleChatController controller;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0D6B57);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      title: 'IBEX 2.0',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          surface: const Color(0xFFF7F8F6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        fontFamilyFallback: const ['Noto Sans Arabic', 'Noto Sans'],
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: IbexOperationalShellV2(controller: controller),
      ),
    );
  }
}

class IbexRuntimeFailureApp extends StatelessWidget {
  const IbexRuntimeFailureApp({super.key, required this.errorCode});

  final String errorCode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 48),
                      const SizedBox(height: 18),
                      const Text(
                        'تعذر فتح مساحة IBEX المحلية بأمان',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'لم يتم إنشاء قاعدة غير مشفرة كبديل. أغلق التطبيق وأعد المحاولة، وإذا استمرت المشكلة استخدم مسار الاستعادة الآمن.',
                        textAlign: TextAlign.center,
                        style: TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'رمز التشخيص: $errorCode',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 12),
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
