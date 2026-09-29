import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_page.dart';
import '../features/admin/admin_page.dart';
import '../features/auth/login_page.dart';
import '../features/bags/bag_detail_page.dart';
import '../features/home/home_page.dart';
import '../features/merchant/merchant_page.dart';
import '../features/merchant/merchant_sales_page.dart';
import '../features/orders/mock_checkout_page.dart';
import '../features/orders/my_orders_page.dart';
import '../features/orders/order_page.dart';
import '../features/shell/app_shell.dart';
import 'auth_refresh.dart';

const _protectedPrefixes = ['/admin', '/merchant', '/order', '/mock-checkout'];

final appRouter = GoRouter(
  refreshListenable: AuthRefresh(FirebaseAuth.instance.authStateChanges()),
  redirect: (context, state) {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    final path = state.matchedLocation;
    if (!loggedIn && _protectedPrefixes.any(path.startsWith)) {
      return '/login?from=${Uri.encodeComponent(state.uri.toString())}';
    }
    // Con sesión, el login no tiene sentido: sigue a donde ibas.
    if (loggedIn && path == '/login') return state.uri.queryParameters['from'] ?? '/';
    return null;
  },
  routes: [
    // Pantallas principales con barra de navegación (Bolsas / Mis pedidos / Cuenta).
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
      routes: [
        GoRoute(path: '/', pageBuilder: (context, state) => const NoTransitionPage(child: HomePage())),
        GoRoute(path: '/orders', pageBuilder: (context, state) => const NoTransitionPage(child: MyOrdersPage())),
        GoRoute(path: '/account', pageBuilder: (context, state) => const NoTransitionPage(child: AccountPage())),
      ],
    ),
    GoRoute(
      path: '/bag/:id',
      builder: (context, state) => BagDetailPage(bagId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => LoginPage(redirectTo: state.uri.queryParameters['from'] ?? '/'),
    ),
    GoRoute(path: '/merchant', builder: (context, state) => const MerchantPage()),
    GoRoute(path: '/merchant/sales', builder: (context, state) => const MerchantSalesPage()),
    GoRoute(path: '/admin', builder: (context, state) => const AdminPage()),
    GoRoute(
      path: '/order/:id',
      builder: (context, state) => OrderPage(orderId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/mock-checkout/:id',
      builder: (context, state) => MockCheckoutPage(orderId: state.pathParameters['id']!),
    ),
  ],
);
