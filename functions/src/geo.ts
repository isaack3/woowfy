import { logger } from "firebase-functions/v2";

/**
 * Geocodifica una dirección chilena con Nominatim (OpenStreetMap): gratis y sin clave.
 * Política de uso: máx. 1 solicitud por segundo e identificarse con User-Agent. Solo se llama cuando un
 * comercio crea o cambia su dirección, así que el volumen es mínimo.
 */
export async function geocode(address: string, comuna: string, region: string): Promise<{ lat: number; lng: number } | null> {
  const queries = [
    [address, comuna, region, "Chile"],
    [address, comuna, "Chile"],
    [comuna, region, "Chile"], // si la calle no se encuentra, al menos el centro de la comuna
  ].map((p) => p.filter(Boolean).join(", "));

  for (const q of queries) {
    const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=cl&q=${encodeURIComponent(q)}`;
    try {
      const res = await fetch(url, { headers: { "User-Agent": "Woowfy/1.0 (hola@woowfy.com)", "Accept-Language": "es" } });
      if (!res.ok) continue;
      const [hit] = (await res.json()) as { lat: string; lon: string }[];
      if (hit) return { lat: Number(hit.lat), lng: Number(hit.lon) };
    } catch (e) {
      logger.warn("Geocodificación falló", q, e);
    }
    await new Promise((r) => setTimeout(r, 1100));
  }
  return null;
}
