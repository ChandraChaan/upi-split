import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';

import 'pages/auth_pages.dart';
import 'pages/bills_page.dart';
import 'pages/customer_detail_page.dart';
import 'pages/customers_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/expenses_page.dart';
import 'pages/import_page.dart';
import 'pages/product_detail_page.dart';
import 'pages/products_page.dart';
import 'pages/reports_page.dart';
import 'pages/settings_page.dart';
import 'pages/staff_page.dart';
import 'pages/stores_page.dart';
import 'pages/supplier_detail_page.dart';
import 'pages/suppliers_page.dart';
import 'shell/admin_shell.dart';

const _signedOutPaths = {'/sign-in', '/forgot-password'};
const _gatePaths = {'/sign-in', '/forgot-password', '/onboarding', '/deactivated', '/cashier'};

/// Where a session at [stage] with [role] must go instead of [path], or null.
String? adminRedirect({
  required SessionStage stage,
  required MemberRole? role,
  required String path,
}) {
  String? onlyAt(String target) => path == target ? null : target;
  switch (stage) {
    case SessionStage.loading:
      // Hold the URL so a reload lands back on the same page.
      return null;
    case SessionStage.signedOut:
      return _signedOutPaths.contains(path) ? null : '/sign-in';
    case SessionStage.needsOnboarding:
      return onlyAt('/onboarding');
    case SessionStage.deactivated:
      return onlyAt('/deactivated');
    case SessionStage.ready:
      if (role == MemberRole.cashier) return onlyAt('/cashier');
      if (_gatePaths.contains(path) || path == '/') return '/dashboard';
      if (path.startsWith('/stores') && role != MemberRole.owner) return '/dashboard';
      return null;
  }
}

GoRouter createRouter(SessionController session) {
  Page<void> plain(Widget child) => NoTransitionPage<void>(child: child);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: session,
    redirect: (context, state) => adminRedirect(
      stage: session.stage,
      role: session.member?.role,
      path: state.uri.path,
    ),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/dashboard'),
      GoRoute(path: '/sign-in', builder: (c, s) => const SignInPage()),
      GoRoute(path: '/forgot-password', builder: (c, s) => const ForgotPasswordPage()),
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingPage()),
      GoRoute(path: '/deactivated', builder: (c, s) => const DeactivatedPage()),
      GoRoute(path: '/cashier', builder: (c, s) => const CashierPage()),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (c, s) => plain(const DashboardPage()),
          ),
          GoRoute(
            path: '/customers',
            pageBuilder: (c, s) => plain(const CustomersPage()),
            routes: [
              GoRoute(
                path: ':storeId/:customerId',
                pageBuilder: (c, s) => plain(CustomerDetailPage(
                  storeId: s.pathParameters['storeId']!,
                  customerId: s.pathParameters['customerId']!,
                )),
              ),
            ],
          ),
          GoRoute(
            path: '/products',
            pageBuilder: (c, s) => plain(const ProductsPage()),
            routes: [
              GoRoute(path: 'import', pageBuilder: (c, s) => plain(const ImportPage())),
              GoRoute(
                path: ':storeId/:productId',
                pageBuilder: (c, s) => plain(ProductDetailPage(
                  storeId: s.pathParameters['storeId']!,
                  productId: s.pathParameters['productId']!,
                )),
              ),
            ],
          ),
          GoRoute(
            path: '/bills',
            pageBuilder: (c, s) => plain(const BillsPage()),
            routes: [
              GoRoute(
                path: ':storeId/:billId',
                pageBuilder: (c, s) => plain(BillDetailPage(
                  storeId: s.pathParameters['storeId']!,
                  billId: s.pathParameters['billId']!,
                )),
              ),
            ],
          ),
          GoRoute(
            path: '/suppliers',
            pageBuilder: (c, s) => plain(const SuppliersPage()),
            routes: [
              GoRoute(
                path: ':storeId/:supplierId',
                pageBuilder: (c, s) => plain(SupplierDetailPage(
                  storeId: s.pathParameters['storeId']!,
                  supplierId: s.pathParameters['supplierId']!,
                )),
              ),
            ],
          ),
          GoRoute(path: '/expenses', pageBuilder: (c, s) => plain(const ExpensesPage())),
          GoRoute(path: '/reports', pageBuilder: (c, s) => plain(const ReportsPage())),
          GoRoute(path: '/staff', pageBuilder: (c, s) => plain(const StaffPage())),
          GoRoute(path: '/stores', pageBuilder: (c, s) => plain(const StoresPage())),
          GoRoute(path: '/settings', pageBuilder: (c, s) => plain(const SettingsPage())),
        ],
      ),
    ],
  );
}
