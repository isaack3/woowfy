import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/backend.dart';
import 'models.dart';

class Repository {
  Repository._();
  static final instance = Repository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _bags => _db.collection('bags');
  CollectionReference<Map<String, dynamic>> get _stores => _db.collection('stores');

  /// Bolsas activas cuyo horario de retiro aún no termina.
  Stream<List<Bag>> watchAvailableBags({String? comuna}) {
    Query<Map<String, dynamic>> q = _bags.where('active', isEqualTo: true);
    if (comuna != null) q = q.where('comuna', isEqualTo: comuna);
    q = q.where('pickupEnd', isGreaterThan: Timestamp.now()).orderBy('pickupEnd');
    return q.snapshots().map((s) => s.docs.map(Bag.fromDoc).toList());
  }

  Stream<Bag?> watchBag(String id) =>
      _bags.doc(id).snapshots().map((d) => d.exists ? Bag.fromDoc(d) : null);

  Stream<Store?> watchMyStore(String uid) => _stores
      .where('ownerUid', isEqualTo: uid)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : Store.fromDoc(s.docs.first));

  Stream<List<Bag>> watchStoreBags(String storeId) => _bags
      .where('storeId', isEqualTo: storeId)
      .orderBy('pickupEnd', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(Bag.fromDoc).toList());

  Future<void> requestStore({
    required String uid,
    required String? email,
    required String name,
    required String comuna,
    required String address,
    required String phone,
  }) {
    return _stores.add({
      'ownerUid': uid,
      'ownerEmail': email,
      'name': name,
      'comuna': comuna,
      'address': address,
      'phone': phone,
      'status': StoreStatus.pending.value,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Un comercio rechazado corrige sus datos y vuelve a quedar pendiente.
  Future<void> resubmitStore(String storeId) => _stores.doc(storeId).update({
        'status': StoreStatus.pending.value,
        'statusReason': FieldValue.delete(),
      });

  // --- Admin -------------------------------------------------------------------

  Stream<String?> watchRole(String uid) =>
      _db.doc('users/$uid').snapshots().map((d) => d.data()?['role'] as String?);

  Stream<List<Store>> watchStoresByStatus(StoreStatus status) => _stores
      .where('status', isEqualTo: status.value)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Store.fromDoc).toList());

  /// Aprueba, rechaza, suspende o reactiva un comercio. Al suspender se pausan sus bolsas activas.
  Future<void> setStoreStatus(String storeId, StoreStatus status, {String? reason}) async {
    final batch = _db.batch();
    batch.update(_stores.doc(storeId), {
      'status': status.value,
      'statusReason': reason ?? FieldValue.delete(),
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    if (status == StoreStatus.suspended) {
      final active = await _bags.where('storeId', isEqualTo: storeId).where('active', isEqualTo: true).get();
      for (final b in active.docs) {
        batch.update(b.reference, {'active': false});
      }
    }
    await batch.commit();
  }

  /// Todos los pedidos creados desde [since] (para las métricas del panel admin).
  Stream<List<BagOrder>> watchOrdersSince(DateTime since) => _db
      .collection('orders')
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map(BagOrder.fromDoc).toList());

  Future<void> publishBag({
    required Store store,
    required String title,
    required String description,
    required int originalPrice,
    required int price,
    required int quantity,
    required DateTime pickupStart,
    required DateTime pickupEnd,
  }) {
    return _bags.add({
      'storeId': store.id,
      'storeName': store.name,
      'comuna': store.comuna,
      'address': store.address,
      'title': title,
      'description': description,
      'originalPrice': originalPrice,
      'price': price,
      'quantityAvailable': quantity,
      'pickupStart': Timestamp.fromDate(pickupStart),
      'pickupEnd': Timestamp.fromDate(pickupEnd),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setBagActive(String bagId, bool active) =>
      _bags.doc(bagId).update({'active': active});

  // --- Pedidos ---------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('orders');

  /// Reserva la bolsa y devuelve la URL de pago (interna en modo mock, Mercado Pago después).
  Future<({String orderId, String checkoutUrl})> createOrder(String bagId) async {
    final res = await functions.httpsCallable('createOrder').call<Map<String, dynamic>>({'bagId': bagId});
    return (orderId: res.data['orderId'] as String, checkoutUrl: res.data['checkoutUrl'] as String);
  }

  Future<void> confirmMockPayment(String orderId, {required bool approved}) =>
      functions.httpsCallable('confirmMockPayment').call({'orderId': orderId, 'approved': approved});

  /// El comercio valida el código/QR del cliente. Devuelve el nombre de la bolsa retirada.
  Future<String> redeemOrder(String code) async {
    final res = await functions.httpsCallable('redeemOrder').call<Map<String, dynamic>>({'code': code});
    return res.data['bagTitle'] as String;
  }

  Stream<BagOrder?> watchOrder(String id) =>
      _orders.doc(id).snapshots().map((d) => d.exists ? BagOrder.fromDoc(d) : null);

  Stream<List<BagOrder>> watchMyOrders(String uid) => _orders
      .where('userUid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(BagOrder.fromDoc).toList());

  /// Pedidos pagados que el comercio aún debe entregar.
  Stream<List<BagOrder>> watchStoreOrdersToPickUp(String storeId) => _orders
      .where('storeId', isEqualTo: storeId)
      .where('status', isEqualTo: OrderStatus.paid.value)
      .orderBy('pickupEnd')
      .snapshots()
      .map((s) => s.docs.map(BagOrder.fromDoc).toList());
}
