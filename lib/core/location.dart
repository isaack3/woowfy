import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Ubicación actual del usuario (la pide el navegador). Devuelve null si no la entrega.
Future<LatLng?> currentPosition() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
}

/// Distancia en metros entre el usuario y un punto.
double distanceMeters(LatLng from, double lat, double lng) =>
    Geolocator.distanceBetween(from.latitude, from.longitude, lat, lng);

/// "350 m", "1,2 km", "15 km".
String formatDistance(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1).replaceAll('.', ',')} km' : '${km.round()} km';
}

/// Centro aproximado de Chile continental (para el mapa cuando no hay bolsas ni ubicación).
const chileCenter = LatLng(-35.7, -71.5);

/// true si ya hay permiso de ubicación (no lo pide). Sirve para explicar antes de pedirlo.
Future<bool> locationGranted() async {
  try {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
}
