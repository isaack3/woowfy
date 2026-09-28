import 'package:cloud_firestore/cloud_firestore.dart';

/// Bolsa sorpresa publicada por un comercio (colección `bags`).
class Bag {
  const Bag({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.comuna,
    required this.address,
    required this.title,
    required this.description,
    required this.originalPrice,
    required this.price,
    required this.quantityAvailable,
    required this.pickupStart,
    required this.pickupEnd,
    required this.active,
    this.imageUrl,
  });

  final String id;
  final String storeId;
  final String storeName;
  final String comuna;
  final String address;
  final String title;
  final String description;
  final int originalPrice;
  final int price;
  final int quantityAvailable;
  final DateTime pickupStart;
  final DateTime pickupEnd;
  final bool active;
  final String? imageUrl;

  bool get soldOut => quantityAvailable <= 0;
  int get discountPercent => ((1 - price / originalPrice) * 100).round();

  factory Bag.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Bag(
      id: doc.id,
      storeId: d['storeId'] as String,
      storeName: d['storeName'] as String? ?? '',
      comuna: d['comuna'] as String? ?? '',
      address: d['address'] as String? ?? '',
      title: d['title'] as String? ?? 'Bolsa sorpresa',
      description: d['description'] as String? ?? '',
      originalPrice: (d['originalPrice'] as num).toInt(),
      price: (d['price'] as num).toInt(),
      quantityAvailable: (d['quantityAvailable'] as num?)?.toInt() ?? 0,
      pickupStart: (d['pickupStart'] as Timestamp).toDate(),
      pickupEnd: (d['pickupEnd'] as Timestamp).toDate(),
      active: d['active'] as bool? ?? false,
      imageUrl: d['imageUrl'] as String?,
    );
  }
}

enum StoreStatus {
  pending('pending', 'Pendiente'),
  approved('approved', 'Activo'),
  rejected('rejected', 'Rechazado'),
  suspended('suspended', 'Suspendido');

  const StoreStatus(this.value, this.label);
  final String value;
  final String label;

  static StoreStatus parse(String? v) =>
      values.firstWhere((s) => s.value == v, orElse: () => StoreStatus.pending);
}

/// Comercio (colección `stores`). Solo publica bolsas si `status == approved`.
class Store {
  const Store({
    required this.id,
    required this.name,
    required this.comuna,
    required this.address,
    required this.ownerUid,
    required this.status,
    this.ownerEmail,
    this.phone,
    this.statusReason,
    this.createdAt,
  });

  final String id;
  final String name;
  final String comuna;
  final String address;
  final String ownerUid;
  final StoreStatus status;
  final String? ownerEmail;
  final String? phone;
  /// Motivo del rechazo o suspensión, visible para el comercio.
  final String? statusReason;
  final DateTime? createdAt;

  bool get approved => status == StoreStatus.approved;

  factory Store.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Store(
      id: doc.id,
      name: d['name'] as String? ?? '',
      comuna: d['comuna'] as String? ?? '',
      address: d['address'] as String? ?? '',
      ownerUid: d['ownerUid'] as String,
      status: StoreStatus.parse(d['status'] as String?),
      ownerEmail: d['ownerEmail'] as String?,
      phone: d['phone'] as String?,
      statusReason: d['statusReason'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

enum OrderStatus {
  pendingPayment('pending_payment', 'Esperando pago'),
  paid('paid', 'Listo para retirar'),
  pickedUp('picked_up', 'Retirado'),
  cancelled('cancelled', 'Cancelado');

  const OrderStatus(this.value, this.label);
  final String value;
  final String label;

  static OrderStatus parse(String? v) =>
      values.firstWhere((s) => s.value == v, orElse: () => OrderStatus.cancelled);
}

/// Compra de una bolsa (colección `orders`). Solo la escriben las Cloud Functions.
class BagOrder {
  const BagOrder({
    required this.id,
    required this.bagId,
    required this.storeName,
    required this.address,
    required this.comuna,
    required this.bagTitle,
    required this.amount,
    required this.pickupStart,
    required this.pickupEnd,
    required this.pickupCode,
    required this.status,
    this.checkoutUrl,
    this.platformFee = 0,
    this.createdAt,
  });

  final String id;
  final String bagId;
  final String storeName;
  /// Comisión de Woowfy incluida en [amount].
  final int platformFee;
  final DateTime? createdAt;
  final String address;
  final String comuna;
  final String bagTitle;
  final int amount;
  final DateTime pickupStart;
  final DateTime pickupEnd;
  final String pickupCode;
  final OrderStatus status;
  final String? checkoutUrl;

  factory BagOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return BagOrder(
      id: doc.id,
      bagId: d['bagId'] as String,
      storeName: d['storeName'] as String? ?? '',
      address: d['address'] as String? ?? '',
      comuna: d['comuna'] as String? ?? '',
      bagTitle: d['bagTitle'] as String? ?? '',
      amount: (d['amount'] as num).toInt(),
      pickupStart: (d['pickupStart'] as Timestamp).toDate(),
      pickupEnd: (d['pickupEnd'] as Timestamp).toDate(),
      pickupCode: d['pickupCode'] as String? ?? '',
      status: OrderStatus.parse(d['status'] as String?),
      checkoutUrl: (d['payment'] as Map<String, dynamic>?)?['checkoutUrl'] as String?,
      platformFee: (d['platformFee'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Comunas del piloto. Ampliar a medida que se sumen comercios.
const pilotComunas = ['Providencia', 'Ñuñoa', 'Santiago', 'Las Condes', 'Vitacura'];
