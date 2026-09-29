import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/backend.dart';
import 'models.dart';

class Repository {
  Repository._();
  static final instance = Repository._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _bags => _db.collection('bags');
  CollectionReference<Map<String, dynamic>> get _stores => _db.collection('stores');

  /// Bolsas activas de todo Chile cuyo horario de retiro aún no termina.
  Stream<List<Bag>> watchAvailableBags() => _bags
      .where('active', isEqualTo: true)
      .where('pickupEnd', isGreaterThan: Timestamp.now())
      .orderBy('pickupEnd')
      .snapshots()
      .map((s) => s.docs.map(Bag.fromDoc).toList());

  // --- Cancelaciones, calificaciones y liquidaciones -----------------------------

  /// El cliente cancela su pedido. Devuelve true si hubo reembolso.
  Future<bool> cancelOrder(String orderId) async {
    final res = await functions.httpsCallable('cancelOrder').call<Map<String, dynamic>>({'orderId': orderId});
    return res.data['refunded'] as bool? ?? false;
  }

  /// Pide al servidor verificar con Mercado Pago si el pedido ya se pagó. Devuelve true si quedó pagado.
  Future<bool> syncOrderPayment(String orderId) async {
    final res = await functions.httpsCallable('syncOrderPayment').call<Map<String, dynamic>>({'orderId': orderId});
    return res.data['status'] == 'paid';
  }

  /// El comercio cancela la bolsa del día (reembolsa y avisa a quienes la compraron).
  Future<int> cancelBag(String bagId, String reason) async {
    final res = await functions.httpsCallable('cancelBag').call<Map<String, dynamic>>({'bagId': bagId, 'reason': reason});
    return (res.data['cancelledOrders'] as num?)?.toInt() ?? 0;
  }

  Future<void> rateOrder(String orderId, int rating, String comment) =>
      functions.httpsCallable('rateOrder').call({'orderId': orderId, 'rating': rating, 'comment': comment});

  Stream<List<Review>> watchStoreReviews(String storeId, {int limit = 20}) => _db
      .collection('reviews')
      .where('storeId', isEqualTo: storeId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(Review.fromDoc).toList());

  /// Pedidos de un local desde una fecha (panel de ventas del comercio y admin).
  Stream<List<BagOrder>> watchStoreOrdersSince(String storeId, DateTime since) => _db
      .collection('orders')
      .where('storeId', isEqualTo: storeId)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
      .orderBy('createdAt', descending: true)
      .limit(1000)
      .snapshots()
      .map((s) => s.docs.map(BagOrder.fromDoc).toList());

  /// Ventas cerradas (retiradas o no retiradas) que aún no se le pagan al comercio.
  Stream<List<BagOrder>> watchUnpaidOrders(String storeId) => _db
      .collection('orders')
      .where('storeId', isEqualTo: storeId)
      .where('status', whereIn: OrderStatus.payableValues)
      .snapshots()
      .map((s) => s.docs.map(BagOrder.fromDoc).where((o) => o.payoutId == null).toList());

  /// Admin: ventas por liquidar de todos los locales.
  Stream<List<BagOrder>> watchAllUnpaidOrders() => _db
      .collection('orders')
      .where('status', whereIn: OrderStatus.payableValues)
      .snapshots()
      .map((s) => s.docs.map(BagOrder.fromDoc).where((o) => o.payoutId == null).toList());

  /// Admin: liquida a todos los locales con ventas pendientes. Devuelve lo registrado por local.
  Future<List<Map<String, dynamic>>> createAllPayouts(String note) async {
    final res = await functions.httpsCallable('createAllPayouts').call<Map<String, dynamic>>({'note': note});
    return (res.data['payouts'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  DocumentReference<Map<String, dynamic>> _bankDoc(String storeId) => _stores.doc(storeId).collection('private').doc('bank');

  Stream<BankAccount?> watchBankAccount(String storeId) =>
      _bankDoc(storeId).snapshots().map((d) => d.exists ? BankAccount.fromMap(d.data()!) : null);

  Future<BankAccount?> getBankAccount(String storeId) async {
    final d = await _bankDoc(storeId).get();
    return d.exists ? BankAccount.fromMap(d.data()!) : null;
  }

  Future<void> saveBankAccount(String storeId, BankAccount account) =>
      _bankDoc(storeId).set({...account.toMap(), 'updatedAt': FieldValue.serverTimestamp()});

  Stream<List<Payout>> watchPayouts(String storeId) => _db
      .collection('payouts')
      .where('storeId', isEqualTo: storeId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(Payout.fromDoc).toList());

  /// Admin: registra el pago de las ventas pendientes de un local.
  Future<int> createPayout(String storeId, String note) async {
    final res = await functions.httpsCallable('createPayout').call<Map<String, dynamic>>({'storeId': storeId, 'note': note});
    return (res.data['storeAmount'] as num).toInt();
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
    required String name,
    required String region,
    required String comuna,
    required String address,
    required String phone,
    String? category,
  }) {
    return _stores.add({
      'category': category,
      'ownerUid': uid,
      'name': name,
      'region': region,
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

  /// El usuario cambia su nombre (las reglas no le dejan tocar su rol).
  Future<void> updateMyName(String uid, String name) =>
      _db.doc('users/$uid').set({'name': name}, SetOptions(merge: true));

  // --- Favoritos y notificaciones ---------------------------------------------------

  /// Ids de los locales favoritos del usuario.
  Stream<Set<String>> watchFavoriteStoreIds(String uid) => _db
      .collection('users/$uid/favorites')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());

  Future<void> setFavorite(String uid, {required String storeId, required String storeName, required bool favorite}) {
    final ref = _db.doc('users/$uid/favorites/$storeId');
    return favorite
        ? ref.set({'storeId': storeId, 'storeName': storeName, 'createdAt': FieldValue.serverTimestamp()})
        : ref.delete();
  }

  /// Guarda el token de notificaciones push de este navegador/dispositivo.
  Future<void> addPushToken(String uid, String token) =>
      _db.doc('users/$uid').set({'fcmTokens': FieldValue.arrayUnion([token])}, SetOptions(merge: true));

  Future<void> removePushToken(String uid, String token) =>
      _db.doc('users/$uid').set({'fcmTokens': FieldValue.arrayRemove([token])}, SetOptions(merge: true));

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

  Stream<EmailSettings> watchEmailSettings() =>
      _db.doc('config/email').snapshots().map((d) => EmailSettings.fromMap(d.data()));

  /// Modo de la landing: false = "en construcción", true = lanzada (config/site, lectura pública).
  Stream<bool> watchSiteLaunched() =>
      _db.doc('config/site').snapshots().map((d) => d.data()?['launched'] == true);

  Future<void> setSiteLaunched(bool launched) => _db.doc('config/site').set({
        'launched': launched,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> saveEmailSettings(EmailSettings s) => _db.doc('config/email').set({
        ...s.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Envía el correo de bienvenida de prueba al admin conectado. Devuelve el destinatario.
  Future<String> sendTestEmail() async {
    final res = await functions.httpsCallable('sendTestEmail').call<Map<String, dynamic>>();
    return res.data['to'] as String;
  }

  Stream<List<WaitlistEntry>> watchWaitlist() => _db
      .collection('waitlist')
      .orderBy('createdAt', descending: true)
      .limit(1000)
      .snapshots()
      .map((s) => s.docs.map(WaitlistEntry.fromDoc).toList());

  /// Admin: contadores de visitas por día desde [since].
  Stream<List<DayStats>> watchStatsSince(DateTime since) {
    String two(int n) => n.toString().padLeft(2, '0');
    final from = '${since.year}-${two(since.month)}-${two(since.day)}';
    return _db
        .collection('stats')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: from)
        .snapshots()
        .map((s) => s.docs.map(DayStats.fromDoc).toList()..sort((a, b) => a.day.compareTo(b.day)));
  }

  /// Admin: cuántos documentos de [collection] se crearon desde [since] (lista de espera, cuentas).
  Future<int> countCreatedSince(String collection, DateTime since) async {
    final agg = await _db
        .collection(collection)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .count()
        .get();
    return agg.count ?? 0;
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
    String? imageUrl,
  }) {
    return _bags.add({
      'storeId': store.id,
      'storeName': store.name,
      'comuna': store.comuna,
      'region': store.region,
      'category': store.category,
      'storeLogoUrl': store.logoUrl,
      'lat': store.lat,
      'lng': store.lng,
      'address': store.address,
      'title': title,
      'description': description,
      'originalPrice': originalPrice,
      'price': price,
      'quantityAvailable': quantity,
      'pickupStart': Timestamp.fromDate(pickupStart),
      'pickupEnd': Timestamp.fromDate(pickupEnd),
      'active': true,
      'imageUrl': ?imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sube la foto de una bolsa a Storage (uploads/{uid}/bags/...) y devuelve su URL pública.
  Future<String> uploadBagImage(String uid, Uint8List bytes, String contentType) =>
      _upload('uploads/$uid/bags', bytes, contentType);

  /// Sube el logo del local (uploads/{uid}/store/...).
  Future<String> uploadStoreLogo(String uid, Uint8List bytes, String contentType) =>
      _upload('uploads/$uid/store', bytes, contentType);

  Future<String> _upload(String folder, Uint8List bytes, String contentType) async {
    final ext = contentType.split('/').last.replaceAll('jpeg', 'jpg');
    final ref = FirebaseStorage.instance.ref('$folder/${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: contentType, cacheControl: 'public, max-age=31536000'));
    return ref.getDownloadURL();
  }

  /// El comercio actualiza su perfil (no puede cambiar su estado ni su dueño: lo impiden las reglas).
  Future<void> updateStoreProfile(String storeId, Map<String, Object?> data) =>
      _stores.doc(storeId).update({...data, 'updatedAt': FieldValue.serverTimestamp()});

  // --- Bolsas recurrentes ---------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _templates => _db.collection('bagTemplates');

  Stream<List<BagTemplate>> watchTemplates(String storeId) => _templates
      .where('storeId', isEqualTo: storeId)
      .snapshots()
      .map((s) => s.docs.map(BagTemplate.fromDoc).toList());

  Future<void> saveTemplate({
    required String storeId,
    required String title,
    required String description,
    required int originalPrice,
    required int price,
    required int quantity,
    required String pickupStart,
    required String pickupEnd,
    required List<int> days,
    String? imageUrl,
  }) {
    return _templates.add({
      'storeId': storeId,
      'title': title,
      'description': description,
      'originalPrice': originalPrice,
      'price': price,
      'quantity': quantity,
      'pickupStart': pickupStart,
      'pickupEnd': pickupEnd,
      'days': days,
      'active': true,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setTemplateActive(String id, bool active) => _templates.doc(id).update({'active': active});

  Future<void> deleteTemplate(String id) => _templates.doc(id).delete();

  // --- Usuarios (admin) -------------------------------------------------------------

  Stream<List<AppUser>> watchUsers() => _db
      .collection('users')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList());

  Future<void> setUserRole(String uid, String role) => _db.doc('users/$uid').update({'role': role});

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

  /// Código de retiro del pedido: está en un documento que solo puede leer el cliente.
  Stream<String?> watchPickupCode(String orderId) => _orders
      .doc(orderId)
      .collection('private')
      .doc('pickup')
      .snapshots()
      .map((d) => d.data()?['code'] as String?);

  /// Correo de una cuenta (lo usa el admin para contactar al dueño de un local).
  Future<String?> userEmail(String uid) async =>
      (await _db.doc('users/$uid').get()).data()?['email'] as String?;

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
