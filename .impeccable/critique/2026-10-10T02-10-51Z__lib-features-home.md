---
target: home de la app
total_score: 26
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:C:\\Users\\sebas\\Desktop\\desarrollos\\woowfy\\lib\\features\\home"
timestamp: 2026-10-10T02-10-51Z
slug: lib-features-home
---
Method: dual-agent (A: revisión de diseño Home · B: detector + navegador)

## Design Health Score — Home (/)
| # | Heurística | Nota | Problema clave |
|---|---|---|---|
| 1 | Estado del sistema | 3 | "Retiro ahora" se calcula solo al dibujar; bolsas vencidas no desaparecen |
| 2 | Mundo real | 3 | "Bolsas de hoy" incluye bolsas de mañana; "Pronto en tu zona · todo Chile" se contradice |
| 3 | Control | 3 | "Usar mi ubicación" borra la región y cambia el orden sin avisar |
| 4 | Consistencia | 2 | Fila 1 con tres componentes distintos; alto de tarjeta distinto en grilla y mapa |
| 5 | Prevención | 2 | Bolsas con ventana vencida siguen tocables (Timestamp.now() fijo) |
| 6 | Reconocer | 3 | Selectores muestran el valor activo |
| 7 | Eficiencia | 2 | Sin búsqueda; orden/filtros/vista no persisten |
| 8 | Estética | 3 | Dos filas de controles antes del contenido |
| 9 | Errores | 3 | ErrorRetry humano |
| 10 | Ayuda | 2 | Con bolsas, nada sobre 15 min ni reembolsos |
| Total | | 26/40 | Aceptable |

## Priority issues
- [P1] Estado vacío sin controles (región oculta con 0 bolsas) y "Avísame" saca de la app sin la región → onboard
- [P1] Tiempo: bolsas vencidas visibles, "Retiro ahora" congelado, "Bolsas de hoy" con bolsas de mañana → harden
- [P2] Barra de controles: tres lenguajes visuales, objetivos de ~34 px, no fija → layout
- [P2] "Usar mi ubicación" mezcla dónde con orden; borra región aunque falle el permiso → clarify
- [P2] Tarjeta sin foto con ícono de "imagen rota"; alto fijo 284 → polish
