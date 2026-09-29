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
    this.region = '',
    required this.description,
    required this.originalPrice,
    required this.price,
    required this.quantityAvailable,
    required this.pickupStart,
    required this.pickupEnd,
    required this.active,
    this.imageUrl,
    this.category,
    this.storeLogoUrl,
    this.templateId,
    this.lat,
    this.lng,
    this.storeRatingAvg,
    this.storeRatingCount = 0,
  });

  final String id;
  final String storeId;
  final String storeName;
  final String comuna;
  final String region;
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
  final String? category;
  final String? storeLogoUrl;
  /// Si la publicó una bolsa recurrente, el id de la plantilla.
  final String? templateId;
  final double? lat;
  final double? lng;
  final double? storeRatingAvg;
  final int storeRatingCount;

  bool get hasLocation => lat != null && lng != null;

  bool get soldOut => quantityAvailable <= 0;
  int get discountPercent => ((1 - price / originalPrice) * 100).round();

  /// El horario de retiro ya empezó y aún no termina.
  bool get pickupNow {
    final now = DateTime.now();
    return !now.isBefore(pickupStart) && now.isBefore(pickupEnd);
  }

  factory Bag.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Bag(
      id: doc.id,
      storeId: d['storeId'] as String,
      storeName: d['storeName'] as String? ?? '',
      comuna: d['comuna'] as String? ?? '',
      region: d['region'] as String? ?? '',
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
      category: d['category'] as String?,
      storeLogoUrl: d['storeLogoUrl'] as String?,
      templateId: d['templateId'] as String?,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      storeRatingAvg: (d['storeRatingAvg'] as num?)?.toDouble(),
      storeRatingCount: (d['storeRatingCount'] as num?)?.toInt() ?? 0,
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
    this.region = '',
    this.ownerEmail,
    this.phone,
    this.statusReason,
    this.createdAt,
    this.category,
    this.description = '',
    this.hours = '',
    this.logoUrl,
    this.lat,
    this.lng,
    this.ratingAvg,
    this.ratingCount = 0,
  });

  final String id;
  final String name;
  final String comuna;
  final String address;
  final String ownerUid;
  final StoreStatus status;
  final String region;
  final String? ownerEmail;
  final String? phone;
  /// Motivo del rechazo o suspensión, visible para el comercio.
  final String? statusReason;
  final DateTime? createdAt;
  /// Perfil público del local.
  final String? category;
  final String description;
  final String hours;
  final String? logoUrl;
  final double? lat;
  final double? lng;
  final double? ratingAvg;
  final int ratingCount;

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
      region: d['region'] as String? ?? '',
      ownerEmail: d['ownerEmail'] as String?,
      phone: d['phone'] as String?,
      statusReason: d['statusReason'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      category: d['category'] as String?,
      description: d['description'] as String? ?? '',
      hours: d['hours'] as String? ?? '',
      logoUrl: d['logoUrl'] as String?,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      ratingAvg: (d['ratingAvg'] as num?)?.toDouble(),
      ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
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
    this.imageUrl,
    this.originalPrice,
    this.platformFee = 0,
    this.storeAmount = 0,
    this.cancelReason,
    this.storeMessage,
    this.refundStatus,
    this.rating,
    this.payoutId,
    this.createdAt,
  });

  final String id;
  final String bagId;
  final String storeName;
  final String? imageUrl;
  /// Valor normal de la bolsa (pedidos creados desde el sprint 2).
  final int? originalPrice;
  /// Comisión de Woowfy incluida en [amount].
  final int platformFee;
  /// Lo que recibe el comercio ([amount] − [platformFee]).
  final int storeAmount;
  /// customer | store | payment_timeout | payment_rejected
  final String? cancelReason;
  /// Mensaje del local cuando cancela la bolsa.
  final String? storeMessage;
  /// pending | done | error (si hubo reembolso).
  final String? refundStatus;
  /// Calificación que dio el cliente (1–5), si ya calificó.
  final int? rating;
  /// Liquidación en la que se le pagó este pedido al comercio.
  final String? payoutId;
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
      imageUrl: d['imageUrl'] as String?,
      originalPrice: (d['originalPrice'] as num?)?.toInt(),
      platformFee: (d['platformFee'] as num?)?.toInt() ?? 0,
      storeAmount: (d['storeAmount'] as num?)?.toInt() ?? 0,
      cancelReason: d['cancelReason'] as String?,
      storeMessage: d['storeMessage'] as String?,
      refundStatus: (d['refund'] as Map<String, dynamic>?)?['status'] as String?,
      rating: (d['rating'] as num?)?.toInt(),
      payoutId: d['payoutId'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Remitente de los correos (documento `config/email`, editable en Admin → Correo).
class EmailSettings {
  const EmailSettings({
    this.enabled = false,
    this.fromName = 'Woowfy',
    this.fromEmail = 'hola@woowfy.com',
    this.replyTo,
  });

  final bool enabled;
  final String fromName;
  final String fromEmail;
  final String? replyTo;

  factory EmailSettings.fromMap(Map<String, dynamic>? d) {
    const def = EmailSettings();
    if (d == null) return def;
    return EmailSettings(
      enabled: d['enabled'] as bool? ?? def.enabled,
      fromName: d['fromName'] as String? ?? def.fromName,
      fromEmail: d['fromEmail'] as String? ?? def.fromEmail,
      replyTo: d['replyTo'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'fromName': fromName,
        'fromEmail': fromEmail,
        'replyTo': replyTo,
      };
}

/// Inscripción en la lista de espera de la landing (colección `waitlist`, solo admin).
class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.email,
    this.name = '',
    this.emailStatus,
    required this.isMerchant,
    this.region,
    this.comuna,
    this.businessName,
    this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  /// Estado del correo de bienvenida: sent | error | skipped (null si aún no se procesa).
  final String? emailStatus;
  final String? region;
  final bool isMerchant;
  final String? comuna;
  final String? businessName;
  final DateTime? createdAt;

  factory WaitlistEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return WaitlistEntry(
      id: doc.id,
      email: d['email'] as String? ?? '',
      name: d['name'] as String? ?? '',
      emailStatus: (d['welcomeEmail'] as Map<String, dynamic>?)?['status'] as String?,
      isMerchant: d['type'] == 'comercio',
      region: d['region'] as String?,
      comuna: d['comuna'] as String?,
      businessName: d['businessName'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}


/// Categorías de locales (filtros del inicio y perfil del comercio).
const storeCategories = [
  'Panadería',
  'Pastelería',
  'Café',
  'Restaurante',
  'Sushi',
  'Verdulería',
  'Minimarket',
  'Otro',
];

/// Días de la semana para bolsas recurrentes (1 = lunes … 7 = domingo).
const weekdayShort = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Bolsa recurrente (colección `bagTemplates`): se publica sola los días elegidos.
class BagTemplate {
  const BagTemplate({
    required this.id,
    required this.storeId,
    required this.title,
    required this.description,
    required this.originalPrice,
    required this.price,
    required this.quantity,
    required this.pickupStart,
    required this.pickupEnd,
    required this.days,
    required this.active,
    this.imageUrl,
  });

  final String id;
  final String storeId;
  final String title;
  final String description;
  final int originalPrice;
  final int price;
  final int quantity;
  /// Hora local "HH:mm".
  final String pickupStart;
  final String pickupEnd;
  final List<int> days;
  final bool active;
  final String? imageUrl;

  String get daysLabel => days.length == 7 ? 'Todos los días' : ([...days]..sort()).map((d) => weekdayShort[d - 1]).join(' ');

  factory BagTemplate.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return BagTemplate(
      id: doc.id,
      storeId: d['storeId'] as String,
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      originalPrice: (d['originalPrice'] as num).toInt(),
      price: (d['price'] as num).toInt(),
      quantity: (d['quantity'] as num).toInt(),
      pickupStart: d['pickupStart'] as String,
      pickupEnd: d['pickupEnd'] as String,
      days: [for (final x in (d['days'] as List? ?? [])) (x as num).toInt()],
      active: d['active'] as bool? ?? false,
      imageUrl: d['imageUrl'] as String?,
    );
  }
}

/// Usuario (colección `users`), para Admin → Usuarios.
class AppUser {
  const AppUser({required this.id, required this.email, required this.name, required this.role, this.createdAt});

  final String id;
  final String email;
  final String name;
  final String role;
  final DateTime? createdAt;

  bool get isAdmin => role == 'admin';

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return AppUser(
      id: doc.id,
      email: d['email'] as String? ?? '',
      name: d['name'] as String? ?? '',
      role: d['role'] as String? ?? 'customer',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Horas antes del inicio del retiro hasta las que el cliente puede cancelar (igual que en /terms y en el servidor).
const cancelHoursBefore = 2;

/// "4,6" para mostrar notas.
String formatRating(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// Calificación de un pedido retirado (colección `reviews`, id = id del pedido).
class Review {
  const Review({required this.id, required this.userName, required this.rating, required this.comment, required this.bagTitle, this.createdAt});

  final String id;
  final String userName;
  final int rating;
  final String comment;
  final String bagTitle;
  final DateTime? createdAt;

  factory Review.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Review(
      id: doc.id,
      userName: d['userName'] as String? ?? 'Cliente',
      rating: (d['rating'] as num).toInt(),
      comment: d['comment'] as String? ?? '',
      bagTitle: d['bagTitle'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Pago de Woowfy a un comercio (colección `payouts`).
class Payout {
  const Payout({
    required this.id,
    required this.orderCount,
    required this.grossAmount,
    required this.platformFee,
    required this.storeAmount,
    required this.note,
    this.createdAt,
  });

  final String id;
  final int orderCount;
  final int grossAmount;
  final int platformFee;
  final int storeAmount;
  final String note;
  final DateTime? createdAt;

  factory Payout.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Payout(
      id: doc.id,
      orderCount: (d['orderCount'] as num).toInt(),
      grossAmount: (d['grossAmount'] as num).toInt(),
      platformFee: (d['platformFee'] as num).toInt(),
      storeAmount: (d['storeAmount'] as num).toInt(),
      note: d['note'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
