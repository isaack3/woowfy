---
target: home de la app
total_score: 25
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:C:\\Users\\sebas\\Desktop\\desarrollos\\woowfy\\lib\\features\\home"
timestamp: 2026-10-10T21-38-44Z
slug: lib-features-home
---
Method: dual-agent (A: revisión de diseño Home · B: detector + navegador)

## Design Health Score — Home (/)
Total 25/40 (Aceptable). Bajos: consistencia (2), eficiencia (2), estética (2), ayuda (2).

## Priority issues
- [P1] La tarjeta no dice la región/comuna de forma visible en "Todo Chile" → clarify
- [P1] El CTA del estado vacío saca a woowfy.com; header "Bolsas disponibles" vs "Aún sin bolsas" → onboard
- [P1] Carga en frío: pantalla blanca 3–5 s sin splash (web/index.html) → harden
- [P2] Escritorio: tres bordes izquierdos distintos y logo duplicado → layout
- [P2] Semántica de Flutter apagada por defecto; marcadores del mapa sin semántica; tiles OSM sin clave → audit
