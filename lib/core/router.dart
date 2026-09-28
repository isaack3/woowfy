import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_page.dart';
import '../features/auth/login_page.dart';
import '../features/bags/bag_detail_page.dart';
import '../features/home/home_page.dart';
import '../features/merchant/merchant_page.dart';
import '../features/orders/mock_checkout_page.dart';
import '../features/orders/my_orders_page.dart';
import '../features/orders/order_page.dart';
import 'auth_refresh.dart';

const _protectedPrefixes = ['/admin', '/comercio', '/pedido', '/pago-simulado'];

final appRouter = GoRouter(
  refreshListenable: AuthRefresh(FirebaseAuth.instance.authStateChanges()),
  redirect: (context, state) {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    final path = state.matchedLocation;
    if (!loggedIn && _protectedPrefixes.any(path.startsWith)) {
      return '/ingresar?desde=${Uri.encodeComponent(state.uri.toString())}';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    GoRoute(
      path: '/bolsa/:id',
      builder: (context, state) => BagDetailPage(bagId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/ingresar',
      builder: (context, state) => LoginPage(redirectTo: state.uri.queryParameters['desde'] ?? '/'),
    ),
    GoRoute(path: '/comercio', builder: (context, state) => const MerchantPage()),
    GoRoute(path: '/admin', builder: (context, state) => const AdminPage()),
    GoRoute(path: '/pedidos', builder: (context, state) => const MyOrdersPage()),
    GoRoute(
      path: '/pedido/:id',
      builder: (context, state) => OrderPage(orderId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/pago-simulado/:id',
      builder: (context, state) => MockCheckoutPage(orderId: state.pathParameters['id']!),
    ),
  ],
);
