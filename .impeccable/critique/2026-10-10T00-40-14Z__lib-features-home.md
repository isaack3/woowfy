---
target: home de la app
total_score: 22
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:C:\\Users\\sebas\\Desktop\\desarrollos\\woowfy\\lib\\features\\home"
timestamp: 2026-10-10T00-40-14Z
slug: lib-features-home
---
Method: dual-agent (A: revisión de diseño Home · B: detector + navegador)

## Design Health Score — Home (/)
| # | Heurística | Nota | Problema clave |
|---|---|---|---|
| 1 | Estado del sistema | 2 | Orden activo invisible (solo ícono); "Retiro ahora" no se refresca; contador incluye agotadas |
| 2 | Mundo real | 3 | "Retiro hoy" fijo aunque el retiro sea mañana (bag_card.dart:60) |
| 3 | Control | 3 | Sin ubicación, "Más cerca" no tiene alternativa |
| 4 | Consistencia | 3 | Doble logo en escritorio; agotada distinta en mapa y lista |
| 5 | Prevención | 2 | Permiso de ubicación sin aviso; tarjeta de alto fijo 284 |
| 6 | Reconocer | 2 | Mapa/orden solo íconos; "toca el corazón" no está en la tarjeta |
| 7 | Eficiencia | 2 | Sin búsqueda ni filtro por región |
| 8 | Estética | 3 | Tarjeta limpia; línea gris funde título·categoría·comuna |
| 9 | Errores | 1 | Error crudo de Firestore sin "Reintentar" (home_page.dart:173) |
| 10 | Ayuda | 1 | Ningún "cómo funciona" en la home |
| Total | | 22/40 | Aceptable |

## Priority issues
- [P1] Home vacía = callejón sin salida (home_page.dart:199-203) → onboard
- [P1] Error técnico crudo, sin reintentar (home_page.dart:170-174) → harden
- [P1] Sin forma de acotar por región si no hay ubicación; mapa cae en Santiago (bags_map.dart:23) → clarify
- [P2] Tarjeta no prioriza horario/lugar/escasez; "Retiro hoy" fijo; alto fijo → layout, typeset
- [P2] Vista y orden son íconos sin texto ni estado → clarify
- Transversal: botones y nav en Roboto, no Lato (theme.dart textStyle sin fontFamily) → typeset

## Detector
lib/ (.dart) no escaneable; app.woowfy.com timeout (Flutter canvas). Sin evidencia determinística para la Home.
