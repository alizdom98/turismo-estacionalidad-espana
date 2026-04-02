-- ============================================================
-- PROYECTO: Destinos Turísticos Alternativos en España
-- Archivo: 04_analisis.sql
-- Descripción: Queries de análisis sobre los datos turísticos
-- Autor: Andrés Liz Domínguez
-- Fecha: Febrero 2026
-- ============================================================
-- Estructura narrativa:
--   Q1-Q2: CUÁNDO VIENEN → Estacionalidad (tema central del proyecto)
--   Q3-Q5: POR QUÉ VIENEN → Motivaciones (nacional y extranjero)
--   Q6-Q8: CÓMO VIAJAN → Alojamiento, gasto, duración
--   Q9-Q11: CONTEXTO → Evolución temporal, destinos emergentes e infraestructura


-- ============================================================
-- QUERY 1: Perfil mensual del turismo extranjero - ¿Dónde está la temporada baja?
-- Habilidades: EXTRACT, porcentaje mensual, comparativa entre destinos
-- Objetivo: Identificar meses de baja afluencia para potenciar
-- ============================================================
-- Muestra qué % del turismo anual cae en cada mes.
-- Un destino con meses por debajo del 5% tiene una "ventana de oportunidad"
-- clara para promoción en temporada baja.
-- Destinos seleccionados:
--   Alternativos: Navarra, País Vasco, Aragón
--   Intermedios con potencial: Galicia, Asturias, Castilla-La Mancha
--   Masivos (referencia): Baleares, Canarias, Andalucía

WITH mensual AS (
    SELECT
        destino,
        EXTRACT(MONTH FROM fecha) AS mes,
        SUM(turistas) AS turistas_mes
    FROM turismo_extranjeros_motivos
    WHERE EXTRACT(YEAR FROM fecha) BETWEEN 2022 AND 2024
    GROUP BY destino, EXTRACT(MONTH FROM fecha)
),
anual AS (
    SELECT destino, SUM(turistas_mes) AS turistas_anual
    FROM mensual
    GROUP BY destino
)
SELECT
    m.destino,
    m.mes,
    m.turistas_mes,
    ROUND(m.turistas_mes::NUMERIC / NULLIF(a.turistas_anual, 0) * 100, 1) AS pct_del_anual
FROM mensual m
JOIN anual a ON m.destino = a.destino
WHERE m.destino IN (
    'Navarra, Comunidad Foral de', 'País Vasco', 'Aragón',
    'Galicia', 'Asturias, Principado de', 'Castilla - La Mancha',
    'Balears, Illes', 'Canarias', 'Andalucía'
)
ORDER BY m.destino, m.mes;

-- RESULTADO (media 2022-2024):
-- Referencia: reparto uniforme = 8.3% por mes.
--
-- CANARIAS: perfil casi plano (6.9%-9.7%) → destino desestacionalizado por excelencia.
--   Incluso ligeramente más turismo en invierno (nov-dic-mar: 9.6-9.7%).
-- PAÍS VASCO: bastante equilibrado (4.3%-12.8%) → pico moderado jul-ago, base todo el año.
-- ANDALUCÍA: moderado (4.4%-12.2%) → pico en verano pero turismo significativo todo el año.
-- GALICIA: moderado (3.7%-17.4%) → pico en agosto, pero diciembre fuerte (9.4%).
-- ARAGÓN: estacional (2.0%-16.3%) → pico ago-sep, valle fuerte en noviembre.
-- BALEARES: extremo (0.8%-16.8%) → casi sin turismo en invierno, todo en may-oct.
--
-- DATOS INCOMPLETOS (INE sin muestra suficiente → meses eliminados como NULL):
--   Asturias: solo 7 meses (faltan feb-abr, nov-dic), concentrado en jul-ago (27+27%).
--   CLM: solo 5 meses, datos poco fiables.
--   Navarra: solo 2 meses (julio 88.7%, agosto 11.3%) → inutilizable para este análisis.
--
-- CONCLUSIÓN: Para perfil mensual extranjero, solo son fiables los destinos con 12 meses
-- de datos: País Vasco, Aragón, Galicia, Andalucía, Canarias, Baleares.


-- ============================================================
-- QUERY 2: Perfil completo - Destinos alternativos vs tradicionales
-- Habilidades: CTEs múltiples, JOINs entre tablas, CASE, STDDEV/AVG, síntesis
-- Objetivo: Medir estacionalidad y clasificar cada CC.AA.
-- ============================================================
-- Construye un "scorecard" por CC.AA. combinando todas las métricas clave.
-- Incluye dos medidas de estacionalidad:
--   - CV trimestral (turismo nacional, datos de ETR)
--   - CV mensual (turismo extranjero, datos de Frontur) → más preciso
-- Y el mix nacional/extranjero para identificar oportunidades.

WITH cv_trimestral_nac AS (
    -- Estacionalidad del turismo NACIONAL (trimestral, única disponible)
    SELECT
        id_ccaa,
        ROUND(STDDEV(viajes_trim) / NULLIF(AVG(viajes_trim), 0) * 100, 1) AS cv_nac_trimestral
    FROM (
        SELECT id_ccaa, anio, trimestre, SUM(valor) AS viajes_trim
        FROM gasto_trimestral_nacional
        WHERE metrica = 'Viajes'
            AND anio BETWEEN 2021 AND 2024
        GROUP BY id_ccaa, anio, trimestre
    ) sub
    GROUP BY id_ccaa
),
cv_mensual_ext AS (
    -- Estacionalidad del turismo EXTRANJERO (mensual, más precisa)
    SELECT
        id_ccaa,
        ROUND(STDDEV(turistas_mes) / NULLIF(AVG(turistas_mes), 0) * 100, 1) AS cv_ext_mensual
    FROM (
        SELECT id_ccaa, fecha, SUM(turistas) AS turistas_mes
        FROM turismo_extranjeros_motivos
        WHERE EXTRACT(YEAR FROM fecha) BETWEEN 2021 AND 2024
        GROUP BY id_ccaa, fecha
    ) sub
    GROUP BY id_ccaa
),
volumen_nac AS (
    SELECT
        id_ccaa,
        destino,
        SUM(valor) AS viajes_nac_2024
    FROM gasto_trimestral_nacional
    WHERE metrica = 'Viajes' AND anio = 2024
    GROUP BY id_ccaa, destino
),
volumen_ext AS (
    SELECT
        id_ccaa,
        SUM(turistas) AS turistas_ext_2024
    FROM turismo_extranjeros_motivos
    WHERE EXTRACT(YEAR FROM fecha) = 2024
    GROUP BY id_ccaa
),
gasto_ext AS (
    SELECT
        id_ccaa,
        MAX(CASE WHEN metrica = 'Gasto medio por persona' THEN valor END) AS gasto_medio_ext,
        MAX(CASE WHEN metrica LIKE 'Duraci%' THEN valor END) AS duracion_media_ext
    FROM gasto_turistas_extranjeros
    WHERE anio = 2024
    GROUP BY id_ccaa
),
pct_ocio_nac AS (
    SELECT
        id_ccaa,
        ROUND(
            SUM(CASE WHEN motivo = 'Ocio, recreo y vacaciones' THEN viajes END)::NUMERIC
            / NULLIF(SUM(CASE WHEN motivo IN (
                'Ocio, recreo y vacaciones',
                'Negocios y otros motivos profesionales',
                'Visitas a familiares o amigos',
                'Otros motivos'
            ) THEN viajes END), 0) * 100, 1
        ) AS pct_ocio
    FROM turismo_residentes
    WHERE alojamiento_nivel1 = 'Total' AND anio = 2024
    GROUP BY id_ccaa
)
SELECT
    n.destino,
    -- Volumen y mix de turistas
    n.viajes_nac_2024,
    e.turistas_ext_2024,
    ROUND(
        n.viajes_nac_2024::NUMERIC
        / NULLIF(n.viajes_nac_2024 + e.turistas_ext_2024, 0) * 100, 1
    ) AS pct_nacionales,
    ROUND(
        e.turistas_ext_2024::NUMERIC
        / NULLIF(n.viajes_nac_2024 + e.turistas_ext_2024, 0) * 100, 1
    ) AS pct_extranjeros,
    -- Doble medida de estacionalidad
    cn.cv_nac_trimestral,
    ce.cv_ext_mensual,
    -- Características del destino
    g.gasto_medio_ext AS gasto_ext_persona,
    g.duracion_media_ext AS noches_ext,
    o.pct_ocio AS pct_ocio_nacional,
    -- Clasificación
    CASE
        WHEN cn.cv_nac_trimestral < 25
            AND (ce.cv_ext_mensual < 50 OR ce.cv_ext_mensual IS NULL) THEN 'Baja'
        WHEN cn.cv_nac_trimestral < 40
            AND (ce.cv_ext_mensual < 80 OR ce.cv_ext_mensual IS NULL) THEN 'Media'
        ELSE 'Alta'
    END AS nivel_estacionalidad,
    CASE
        -- Masivo: gran volumen (nac+ext > 20M) o estacionalidad muy alta (ambos CV altos)
        WHEN (n.viajes_nac_2024 + COALESCE(e.turistas_ext_2024, 0)) >= 20000000
            OR (cn.cv_nac_trimestral >= 40 AND COALESCE(ce.cv_ext_mensual, 0) >= 60)
        THEN 'Tradicional masivo'
        -- Alternativo: umbral CV < 30 (vs < 25 en nivel_estacionalidad = 'Baja') porque
        -- la clasificación combina estacionalidad con volumen y diversificación de motivos.
        -- Un destino puede ser "Alternativo" sin alcanzar el nivel más estricto de "Baja".
        WHEN cn.cv_nac_trimestral < 30
            AND (n.viajes_nac_2024 + COALESCE(e.turistas_ext_2024, 0)) < 10000000
            AND o.pct_ocio < 70
        THEN 'Alternativo'
        ELSE 'Intermedio'
    END AS clasificacion
FROM volumen_nac n
LEFT JOIN volumen_ext e ON n.id_ccaa = e.id_ccaa
LEFT JOIN cv_trimestral_nac cn ON n.id_ccaa = cn.id_ccaa
LEFT JOIN cv_mensual_ext ce ON n.id_ccaa = ce.id_ccaa
LEFT JOIN gasto_ext g ON n.id_ccaa = g.id_ccaa
LEFT JOIN pct_ocio_nac o ON n.id_ccaa = o.id_ccaa
ORDER BY cn.cv_nac_trimestral;

-- RESULTADO:
-- Cada CC.AA. tiene ahora un perfil completo para evaluar oportunidades de negocio:
--
-- ESTACIONALIDAD:
--   cv_nac_trimestral = estacionalidad del turismo nacional (datos trimestrales ETR)
--   cv_ext_mensual = estacionalidad del turismo extranjero (datos mensuales Frontur)
--   Un destino "Alternativo" ideal tiene AMBOS CV bajos.
--
-- MIX DE TURISTAS (pct_nacionales / pct_extranjeros):
--   Los destinos muy dependientes de extranjeros (>50%) son más vulnerables a crisis
--   internacionales pero tienen mayor gasto por persona.
--   Los destinos con mayoría nacional son más resilientes pero con menor gasto.
--   La oportunidad está en destinos nacionales con potencial de captar extranjeros.
--
-- OPORTUNIDAD DE NEGOCIO:
--   Buscar destinos clasificados como "Alternativo" o "Intermedio" con:
--   - Estacionalidad baja → turismo todo el año (menos riesgo)
--   - Alto % nacional → mercado estable, potencial de internacionalización
--   - Gasto extranjero competitivo → el turista que llega, gasta bien
--   - % ocio bajo → espacio para diversificar la oferta turística


-- ============================================================
-- QUERY 3: Motivos del turismo nacional por CC.AA.
-- Habilidades: CASE dentro de SUM (pivot manual), porcentajes
-- Objetivo: Entender motivaciones turísticas
-- ============================================================
-- Agrupamos los 21 motivos del INE en 4 categorías principales
-- para facilitar la comparación entre CC.AA.

WITH totales AS (
    SELECT
        destino,
        SUM(CASE WHEN motivo IN (
            'Ocio, recreo y vacaciones',
            'Negocios y otros motivos profesionales',
            'Visitas a familiares o amigos',
            'Otros motivos'
        ) THEN viajes END)                                                    AS total_viajes,
        SUM(CASE WHEN motivo = 'Ocio, recreo y vacaciones'                THEN viajes END) AS ocio,
        SUM(CASE WHEN motivo = 'Negocios y otros motivos profesionales'   THEN viajes END) AS negocios,
        SUM(CASE WHEN motivo = 'Visitas a familiares o amigos'            THEN viajes END) AS familia,
        SUM(CASE WHEN motivo = 'Otros motivos'                            THEN viajes END) AS otros
    FROM turismo_residentes
    WHERE alojamiento_nivel1 = 'Total'  -- Solo filas de motivos (no de alojamiento)
        AND anio = 2024
    GROUP BY destino
)
SELECT
    destino,
    total_viajes,
    ROUND(ocio::NUMERIC      / NULLIF(total_viajes, 0) * 100, 1) AS pct_ocio,
    ROUND(negocios::NUMERIC  / NULLIF(total_viajes, 0) * 100, 1) AS pct_negocios,
    ROUND(familia::NUMERIC   / NULLIF(total_viajes, 0) * 100, 1) AS pct_familia,
    ROUND(otros::NUMERIC     / NULLIF(total_viajes, 0) * 100, 1) AS pct_otros
FROM totales
ORDER BY pct_ocio DESC;

-- RESULTADO (2024):
-- Cantabria lidera en ocio (66.1%), seguida de Baleares (64.1%) y C. Valenciana (60.2%).
-- Madrid tiene el mayor % de negocios (18.2%) y Navarra destaca (14.2%).
-- Extremadura es la CC.AA. más orientada a visitas familiares (49.7%).
-- Los destinos alternativos tienen perfil diversificado:
--   País Vasco: 42.6% ocio, 13.7% negocios, 37.4% familia
--   Navarra: 43.0% ocio, 14.2% negocios, 38.7% familia
--   Galicia: 46.0% ocio, 7.8% negocios, 38.2% familia
-- Los masivos son más dependientes del ocio:
--   Andalucía: 55.2%, Canarias: 57.2%, Baleares: 64.1%


-- ============================================================
-- QUERY 4: Desglose del turismo de ocio nacional por subcategoría
-- Habilidades: CASE dentro de SUM, porcentajes sobre subtotal
-- Objetivo: Entender QUÉ TIPO de ocio domina en cada CC.AA.
-- ============================================================
-- El INE desglosa "Ocio, recreo y vacaciones" en 7 subcategorías.
-- Este desglose solo existe para turistas NACIONALES (ETR), no para extranjeros (Frontur).
-- Es clave para la oportunidad de negocio: turismo cultural y de naturaleza
-- son más desestacionalizados que sol y playa.

WITH ocio AS (
    SELECT
        destino,
        SUM(CASE WHEN motivo = 'Ocio, recreo y vacaciones'        THEN viajes END) AS total_ocio,
        SUM(CASE WHEN motivo = 'Turismo de sol y playa'           THEN viajes END) AS sol_playa,
        SUM(CASE WHEN motivo = 'Turismo cultural'                 THEN viajes END) AS cultural,
        SUM(CASE WHEN motivo = 'Turismo de naturaleza'            THEN viajes END) AS naturaleza,
        SUM(CASE WHEN motivo = 'Turismo deportivo'                THEN viajes END) AS deportivo,
        SUM(CASE WHEN motivo = 'Turismo termal y de bienestar'    THEN viajes END) AS termal,
        SUM(CASE WHEN motivo = 'Turismo de compras'               THEN viajes END) AS compras,
        SUM(CASE WHEN motivo = 'Otro tipo de turismo de ocio'     THEN viajes END) AS otro_ocio
    FROM turismo_residentes
    WHERE alojamiento_nivel1 = 'Total'
        AND anio = 2024
    GROUP BY destino
)
SELECT
    destino,
    total_ocio,
    ROUND(sol_playa::NUMERIC  / NULLIF(total_ocio, 0) * 100, 1) AS pct_sol_playa,
    ROUND(cultural::NUMERIC   / NULLIF(total_ocio, 0) * 100, 1) AS pct_cultural,
    ROUND(naturaleza::NUMERIC / NULLIF(total_ocio, 0) * 100, 1) AS pct_naturaleza,
    ROUND(deportivo::NUMERIC  / NULLIF(total_ocio, 0) * 100, 1) AS pct_deportivo,
    ROUND(termal::NUMERIC     / NULLIF(total_ocio, 0) * 100, 1) AS pct_termal,
    ROUND(compras::NUMERIC    / NULLIF(total_ocio, 0) * 100, 1) AS pct_compras,
    ROUND(otro_ocio::NUMERIC  / NULLIF(total_ocio, 0) * 100, 1) AS pct_otro_ocio
FROM ocio
ORDER BY pct_sol_playa DESC;

-- RESULTADO (2024):
-- El denominador es "Ocio, recreo y vacaciones" (el agregado del INE).
-- "Otro tipo de turismo de ocio" absorbe un 27-65% (cajón de sastre del INE),
-- por lo que las subcategorías específicas no suman 100%.
--
-- Destinos de SOL Y PLAYA (generalmente estacionales):
--   Baleares 55.9%, C. Valenciana 49.8%, Canarias 43.0%, Andalucía 40.3%
--   Sol y playa suele implicar estacionalidad alta (pico en verano).
--   Excepción: Canarias (43% sol y playa, CV 6.9-9.7%) → su clima subtropical
--   permite playa todo el año, atrayendo turismo europeo en invierno.
-- Destinos de NATURALEZA (desestacionalizados):
--   Aragón 32.0%, Asturias 25.8%, Navarra 21.5%, Cataluña 17.9%, Cantabria 17.6%
-- Destinos CULTURALES:
--   Madrid 37.1%, País Vasco 27.5%, Navarra 15.3%, Galicia 15.5%
-- Destinos DEPORTIVOS (nicho):
--   Aragón 16.1% (Pirineos), País Vasco 7.4%, Cantabria/Canarias ~4-5%
-- Destinos TERMALES (nicho):
--   Galicia 3.3%, Cataluña 0.8%
--
-- Interior sin playa (Navarra, Madrid, Castilla y León, La Rioja, CLM, Extremadura):
--   pct_sol_playa = NULL → su ocio es cultural, naturaleza y "otro".
-- NOTA: Solo disponible para turismo nacional (ETR). Frontur no desglosa el ocio.


-- ============================================================
-- QUERY 5: Motivos del turismo extranjero por CC.AA. (solo 3 categorías)
-- Habilidades: CTE, CASE dentro de SUM, porcentajes, comparativa
-- Objetivo: Entender motivaciones turísticas
-- ============================================================

WITH extranjeros_anual AS (
    SELECT
        destino,
        motivo,
        SUM(turistas) AS total_turistas
    FROM turismo_extranjeros_motivos
    WHERE EXTRACT(YEAR FROM fecha) = 2024
    GROUP BY destino, motivo
)
SELECT
    destino,
    SUM(total_turistas) AS turistas_total,
    ROUND(
        SUM(CASE WHEN motivo LIKE 'Ocio%' THEN total_turistas END)::NUMERIC
        / NULLIF(SUM(total_turistas), 0) * 100, 1
    ) AS pct_ocio,
    ROUND(
        SUM(CASE WHEN motivo LIKE 'Negocios%' THEN total_turistas END)::NUMERIC
        / NULLIF(SUM(total_turistas), 0) * 100, 1
    ) AS pct_negocios,
    ROUND(
        SUM(CASE WHEN motivo LIKE 'Otros%' THEN total_turistas END)::NUMERIC
        / NULLIF(SUM(total_turistas), 0) * 100, 1
    ) AS pct_otros
FROM extranjeros_anual
GROUP BY destino
ORDER BY pct_ocio DESC;

-- RESULTADO (2024):
-- Frontur solo desglosa 3 motivos (Ocio, Negocios, Otros), mucho menos detalle que la ETR.
-- Navarra, Aragón, Asturias y CLM muestran 100% ocio → no es que todo sea ocio,
--   sino que el INE solo tiene muestra para esa categoría (las demás eran "." → NULL).
-- Baleares 95.3% ocio, Canarias 98.3% → turismo extranjero casi exclusivamente vacacional.
-- Madrid: 12.7% negocios (hub empresarial) y 75.6% ocio.
-- País Vasco: 79.9% ocio, 4.0% negocios, 16.0% otros → perfil más diversificado.
-- Castilla y León: solo 60.3% ocio y 37.7% otros → perfil atípico.
-- NOTA: Los destinos con pocos turistas extranjeros (Navarra 75K, CLM 17K, Asturias 147K)
--   tienen datos poco fiables por insuficiencia de muestra.


-- ============================================================
-- QUERY 6: Tipo de alojamiento por CC.AA. (¿hotel o alternativo?)
-- Habilidades: Pivot con CASE, porcentajes, jerarquías
-- Objetivo: Entender las preferencias de alojamiento
-- ============================================================

WITH base AS (
    SELECT
        destino,
        -- Denominador: subtotales de nivel 1 (sin nivel 2 = filas agregadas)
        SUM(CASE WHEN alojamiento_nivel2 IS NULL                                    THEN viajes END) AS total,
        SUM(CASE WHEN alojamiento_nivel1 = 'De mercado'    AND alojamiento_nivel2 IS NULL THEN viajes END) AS total_mercado,
        SUM(CASE WHEN alojamiento_nivel1 = 'No de mercado' AND alojamiento_nivel2 IS NULL THEN viajes END) AS total_no_mercado,
        -- Desglose de los 7 tipos de alojamiento (nivel 2)
        SUM(CASE WHEN alojamiento_nivel2 = 'Hotelero'                        THEN viajes END) AS hotel,
        SUM(CASE WHEN alojamiento_nivel2 = 'Vivienda en alquiler'            THEN viajes END) AS alquiler,
        SUM(CASE WHEN alojamiento_nivel2 = 'Casa rural'                      THEN viajes END) AS rural,
        SUM(CASE WHEN alojamiento_nivel2 = 'Camping'                         THEN viajes END) AS camping,
        SUM(CASE WHEN alojamiento_nivel2 = 'Vivienda en propiedad'           THEN viajes END) AS propiedad,
        SUM(CASE WHEN alojamiento_nivel2 = 'Vivienda de familiares o amigos' THEN viajes END) AS familiares,
        SUM(CASE WHEN alojamiento_nivel2 = 'Resto de no mercado'             THEN viajes END) AS resto_no_mercado
    FROM turismo_residentes
    WHERE motivo = 'Total'  -- Solo filas de alojamiento (no de motivos)
        AND anio = 2024
    GROUP BY destino
)
SELECT
    destino,
    total_mercado,
    total_no_mercado,
    ROUND(hotel::NUMERIC           / NULLIF(total, 0) * 100, 1) AS pct_hotel,
    ROUND(alquiler::NUMERIC        / NULLIF(total, 0) * 100, 1) AS pct_alquiler,
    ROUND(rural::NUMERIC           / NULLIF(total, 0) * 100, 1) AS pct_rural,
    ROUND(camping::NUMERIC         / NULLIF(total, 0) * 100, 1) AS pct_camping,
    ROUND(propiedad::NUMERIC       / NULLIF(total, 0) * 100, 1) AS pct_propiedad,
    ROUND(familiares::NUMERIC      / NULLIF(total, 0) * 100, 1) AS pct_familiares,
    ROUND(resto_no_mercado::NUMERIC / NULLIF(total, 0) * 100, 1) AS pct_resto_no_mercado
FROM base
ORDER BY pct_hotel DESC;

-- RESULTADO (2024):
-- Se muestran los 7 tipos de alojamiento (nivel 2). Los porcentajes suman ~95-100%
-- sobre el denominador (De mercado + No de mercado, subtotales nivel 1).
--
-- DE MERCADO:
--   Hotel: Baleares 37.9%, Madrid 34.4%, País Vasco 29.6%, Canarias 27.2%
--   Alquiler: Canarias 15.8%, Baleares/Andalucía 14.3%, Cantabria 11.9%
--   Rural: Asturias 5.6%, Navarra 5.3%, Aragón 4.5%, CLM 4.2%, Extremadura 4.1%
--   Camping: Cataluña 7.1%, Navarra 4.1%, Asturias/Cantabria ~3%
-- NO DE MERCADO (la gran mayoría del alojamiento en muchas CC.AA.):
--   Familiares: Extremadura 51.2%, La Rioja 47.1%, CyL 45.4%, CLM 44.2%, Madrid 43.0%
--     → Es la categoría MÁS GRANDE en casi todas las CC.AA.
--   Propiedad: CLM 27.7%, CyL 25.2%, Cantabria 25.0%, Asturias 23.3%, C. Valenciana 22.0%
--   Juntos (familiares + propiedad) dominan en interior: CLM 71.9%, Extremadura 71.8%,
--     CyL 70.6%, La Rioja 66.5% → turismo de raíz familiar, no comercial.
--   En destinos masivos es menor: Baleares 39.1%, Canarias 47.1%.
--
-- CONCLUSIÓN para oportunidad de negocio:
--   Los destinos con alto "no mercado" tienen menos infraestructura turística comercial.
--   Esto puede significar potencial de desarrollo (más casas rurales, hoteles boutique),
--   pero también que el turista tipo no busca alojamiento comercial (visita a la familia).
--   Los destinos alternativos con MÁS mercado comercial (País Vasco 29.6% hotel,
--   Asturias 21.4%, Aragón 22.4%) son más interesantes para inversión turística.


-- ============================================================
-- QUERY 7: Gasto medio por turista - Nacional vs Extranjero
-- Habilidades: FULL OUTER JOIN, múltiples CTEs, comparativa
-- Objetivo: Comparar características económicas
-- ============================================================

WITH gasto_nacional AS (
    SELECT
        id_ccaa,
        destino,
        SUM(CASE WHEN metrica = 'Gasto total' THEN valor END) AS gasto_total_nac,
        SUM(CASE WHEN metrica = 'Viajes' THEN valor END) AS viajes_nac,
        ROUND(
            SUM(CASE WHEN metrica = 'Gasto total' THEN valor END)
            / NULLIF(SUM(CASE WHEN metrica = 'Viajes' THEN valor END), 0) * 1000,
            2
        ) AS gasto_medio_nac  -- Gasto total está en miles de €, viajes en unidades
    FROM gasto_trimestral_nacional
    WHERE anio = 2024
    GROUP BY id_ccaa, destino
),
gasto_extranjero AS (
    SELECT
        id_ccaa,
        MAX(CASE WHEN metrica = 'Gasto medio por persona' THEN valor END) AS gasto_medio_ext
    FROM gasto_turistas_extranjeros
    WHERE anio = 2024
    GROUP BY id_ccaa
)
SELECT
    COALESCE(n.destino, 'CC.AA. ' || e.id_ccaa) AS destino,
    n.gasto_medio_nac AS gasto_medio_nacional_eur,
    e.gasto_medio_ext AS gasto_medio_extranjero_eur,
    ROUND(
        (e.gasto_medio_ext - n.gasto_medio_nac) / NULLIF(n.gasto_medio_nac, 0) * 100,
        1
    ) AS diferencia_pct
FROM gasto_nacional n
FULL OUTER JOIN gasto_extranjero e ON n.id_ccaa = e.id_ccaa
ORDER BY diferencia_pct DESC NULLS LAST;

-- RESULTADO (2024):
-- Los turistas extranjeros gastan entre 5x y 10x más que los nacionales.
-- Esto es esperable: los viajes nacionales son cortos y baratos (escapadas),
-- los internacionales incluyen vuelo, hotel y estancias largas.
--
-- Mayor gasto extranjero por persona:
--   Canarias 1502€, Galicia 1455€, Andalucía 1360€, CLM 1360€, Asturias 1310€
-- Menor gasto extranjero:
--   Navarra 780€, Castilla y León 616€ → estancias más cortas
-- Gasto nacional (gasto total / viajes × 1000):
--   Canarias ~255€, Baleares ~209€, Andalucía ~155€ (más modesto)
-- CC.AA. 18 y 19 (Ceuta/Melilla) aparecen por el FULL OUTER JOIN.


-- ============================================================
-- QUERY 8: Duración media de la estancia - Nacional vs Extranjero
-- Habilidades: JOIN entre tablas, ROUND, comparativa
-- Objetivo: Comparar características de los viajes
-- ============================================================

WITH duracion_nacional AS (
    SELECT
        id_ccaa,
        destino,
        ROUND(AVG(valor), 2) AS duracion_media_nac
    FROM gasto_trimestral_nacional
    WHERE metrica LIKE 'Duraci%'  -- 'Duración media de los viajes'
        AND anio BETWEEN 2022 AND 2024
    GROUP BY id_ccaa, destino
),
duracion_extranjero AS (
    SELECT
        id_ccaa,
        ROUND(AVG(valor), 2) AS duracion_media_ext
    FROM gasto_turistas_extranjeros
    WHERE metrica LIKE 'Duraci%'  -- 'Duración media de los viajes'
        AND anio BETWEEN 2022 AND 2024
    GROUP BY id_ccaa
)
SELECT
    COALESCE(n.destino, 'CC.AA. ' || e.id_ccaa) AS destino,
    n.duracion_media_nac AS noches_nacional,
    e.duracion_media_ext AS noches_extranjero,
    ROUND(e.duracion_media_ext - n.duracion_media_nac, 2) AS diferencia_noches
FROM duracion_nacional n
FULL OUTER JOIN duracion_extranjero e ON n.id_ccaa = e.id_ccaa
ORDER BY noches_nacional DESC NULLS LAST;

-- RESULTADO (media 2022-2024):
-- Estancias nacionales: rango estrecho (3.0-4.3 noches), son escapadas cortas.
-- Estancias extranjeras: rango amplio (4.4-12.3 noches), depende mucho del destino.
--
-- Mayor duración nacional: Extremadura 4.31, C. Valenciana 4.17, Galicia 4.10
-- Menor duración nacional: Madrid 3.03, Navarra 3.07, CLM 3.15
-- Mayor duración extranjera: Murcia 12.27 (largo estancia), Asturias 10.25,
--   C. Valenciana 9.64, CLM 9.57, Cantabria 9.09, Galicia 9.02
-- Menor duración extranjera: País Vasco 4.40, Castilla y León 4.56, Navarra 4.84
--   → Extranjeros hacen city breaks cortos en estos destinos.
-- País Vasco tiene la menor diferencia nac/ext (0.97 noches) → perfil similar.
-- Murcia tiene la mayor diferencia (8.50 noches) → residentes europeos de larga estancia.
-- CC.AA. 18 y 19 (Ceuta/Melilla) aparecen por FULL OUTER JOIN (solo dato extranjero).


-- ============================================================
-- QUERY 9: Evolución temporal de las características turísticas (2016-2024)
-- Habilidades: CTEs múltiples, FULL OUTER JOIN, LAG, tendencias
-- Objetivo: Ver si las características de los destinos están cambiando
-- ============================================================
-- Compara cómo han evolucionado los viajes nacionales, turistas extranjeros,
-- el % de ocio y el gasto extranjero por persona a lo largo de los años.
-- Permite detectar destinos que están cambiando de perfil.

WITH viajes_nac AS (
    SELECT
        destino,
        anio,
        SUM(valor) AS viajes_nacionales
    FROM gasto_trimestral_nacional
    WHERE metrica = 'Viajes'
        AND anio BETWEEN 2016 AND 2024
    GROUP BY destino, anio
),
turistas_ext AS (
    SELECT
        destino,
        EXTRACT(YEAR FROM fecha)::INTEGER AS anio,
        SUM(turistas) AS turistas_extranjeros
    FROM turismo_extranjeros_motivos
    WHERE EXTRACT(YEAR FROM fecha) BETWEEN 2016 AND 2024
    GROUP BY destino, EXTRACT(YEAR FROM fecha)
),
pct_ocio AS (
    SELECT
        destino,
        anio,
        ROUND(
            SUM(CASE WHEN motivo = 'Ocio, recreo y vacaciones' THEN viajes END)::NUMERIC
            / NULLIF(SUM(CASE WHEN motivo IN (
                'Ocio, recreo y vacaciones',
                'Negocios y otros motivos profesionales',
                'Visitas a familiares o amigos',
                'Otros motivos'
            ) THEN viajes END), 0) * 100, 1
        ) AS pct_ocio
    FROM turismo_residentes
    WHERE alojamiento_nivel1 = 'Total'
    GROUP BY destino, anio
),
gasto_ext AS (
    SELECT
        destino,
        anio,
        MAX(CASE WHEN metrica = 'Gasto medio por persona' THEN valor END) AS gasto_medio_ext
    FROM gasto_turistas_extranjeros
    GROUP BY destino, anio
)
SELECT
    v.destino,
    v.anio,
    v.viajes_nacionales,
    LAG(v.viajes_nacionales) OVER (PARTITION BY v.destino ORDER BY v.anio) AS viajes_nac_anterior,
    ROUND(
        (v.viajes_nacionales - LAG(v.viajes_nacionales) OVER (PARTITION BY v.destino ORDER BY v.anio))::NUMERIC
        / NULLIF(LAG(v.viajes_nacionales) OVER (PARTITION BY v.destino ORDER BY v.anio), 0) * 100, 1
    ) AS crecimiento_nac_pct,
    t.turistas_extranjeros,
    o.pct_ocio,
    g.gasto_medio_ext
FROM viajes_nac v
LEFT JOIN turistas_ext t ON v.destino = t.destino AND v.anio = t.anio
LEFT JOIN pct_ocio o ON v.destino = o.destino AND v.anio = o.anio
LEFT JOIN gasto_ext g ON v.destino = g.destino AND v.anio = g.anio
WHERE v.destino IN (
    'Navarra, Comunidad Foral de', 'País Vasco', 'Aragón',
    'Galicia', 'Asturias, Principado de', 'Castilla - La Mancha',
    'Balears, Illes', 'Canarias', 'Andalucía'
)
ORDER BY v.destino, v.anio;

-- RESULTADO (2016-2024):
-- GALICIA - Estrella emergente:
--   Turistas extranjeros casi duplicados: 891K (2016) → 1.66M (2024).
--   Gasto ext +48%: 982€ → 1455€. Nacional estable (~10M, recuperado post-COVID).
--   pct_ocio subiendo pero aún moderado: 36.3% → 46.0%.
--
-- PAÍS VASCO - Crecimiento sostenible:
--   Extranjeros +47%: 1.4M → 2.0M. pct_ocio bajo y estable (~42%).
--   Gasto ext subiendo: 895€ → 958€. Nacional ligeramente a la baja.
--
-- ARAGÓN - En declive nacional:
--   Nacional: 8.0M → 6.7M (no ha recuperado pre-COVID, -8.2% en 2024).
--   Pocos extranjeros (~282K) aunque gasto ext sube: 742€ → 960€.
--
-- BALEARES - Se especializa y arriesga:
--   Nacional cayendo: 3.2M → 3.1M (-13.5% en 2024).
--   Cada vez más dependiente de extranjeros: 13M → 15.3M.
--   pct_ocio subiendo a 64.1% → concentración peligrosa.
--
-- CANARIAS - Estable y diversificado:
--   Nacional y extranjero ambos creciendo. Gasto ext el más alto: 1502€ (2024).
--
-- DATO TRANSVERSAL: El gasto medio extranjero sube en TODOS los destinos post-COVID
--   (efecto inflación + turista de mayor poder adquisitivo).
-- COVID: Todas las CC.AA. cayeron 35-46% en 2020. Recuperación variable.
-- Navarra: datos extranjeros con huecos (NULL en 2020-2021), poco fiable.


-- ============================================================
-- QUERY 10: Destinos emergentes - ¿Quién crece y por qué? (2016 → 2019 → 2024)
-- Habilidades: CTEs con CASE-pivot temporal, crecimiento porcentual, síntesis multifuente
-- Objetivo: Identificar destinos que crecen por encima de la media y caracterizar su crecimiento
-- ============================================================
-- Usa 3 puntos de referencia para separar la tendencia de fondo del efecto COVID:
--   2016: inicio de la serie (primer año completo con datos de Egatur)
--   2019: último año pre-COVID (línea base natural)
--   2024: último año completo
-- Dos tramos de crecimiento:
--   2016→2019: tendencia pre-COVID (¿ya crecía antes de la pandemia?)
--   2019→2024: recuperación + crecimiento post-COVID
-- Si un destino crece en AMBOS tramos, es una tendencia estructural.
-- Si solo crece en 2019→2024, puede ser un rebote post-COVID.

WITH viajes_nac AS (
    SELECT
        id_ccaa,
        destino,
        SUM(CASE WHEN anio = 2016 THEN valor END) AS nac_2016,
        SUM(CASE WHEN anio = 2019 THEN valor END) AS nac_2019,
        SUM(CASE WHEN anio = 2024 THEN valor END) AS nac_2024
    FROM gasto_trimestral_nacional
    WHERE metrica = 'Viajes' AND anio IN (2016, 2019, 2024)
    GROUP BY id_ccaa, destino
),
turistas_ext AS (
    SELECT
        id_ccaa,
        SUM(CASE WHEN EXTRACT(YEAR FROM fecha) = 2016 THEN turistas END) AS ext_2016,
        SUM(CASE WHEN EXTRACT(YEAR FROM fecha) = 2019 THEN turistas END) AS ext_2019,
        SUM(CASE WHEN EXTRACT(YEAR FROM fecha) = 2024 THEN turistas END) AS ext_2024
    FROM turismo_extranjeros_motivos
    WHERE EXTRACT(YEAR FROM fecha) IN (2016, 2019, 2024)
    GROUP BY id_ccaa
),
gasto_ext AS (
    SELECT
        id_ccaa,
        MAX(CASE WHEN anio = 2016 THEN valor END) AS gasto_2016,
        MAX(CASE WHEN anio = 2019 THEN valor END) AS gasto_2019,
        MAX(CASE WHEN anio = 2024 THEN valor END) AS gasto_2024
    FROM gasto_turistas_extranjeros
    WHERE metrica = 'Gasto medio por persona' AND anio IN (2016, 2019, 2024)
    GROUP BY id_ccaa
),
ocio_nac AS (
    -- Numeradores y denominadores por año separados; % calculados en el SELECT final
    SELECT
        id_ccaa,
        SUM(CASE WHEN anio = 2016 AND motivo = 'Ocio, recreo y vacaciones' THEN viajes END) AS ocio_2016,
        SUM(CASE WHEN anio = 2019 AND motivo = 'Ocio, recreo y vacaciones' THEN viajes END) AS ocio_2019,
        SUM(CASE WHEN anio = 2024 AND motivo = 'Ocio, recreo y vacaciones' THEN viajes END) AS ocio_2024,
        SUM(CASE WHEN anio = 2016 AND motivo IN (
            'Ocio, recreo y vacaciones', 'Negocios y otros motivos profesionales',
            'Visitas a familiares o amigos', 'Otros motivos'
        ) THEN viajes END) AS total_2016,
        SUM(CASE WHEN anio = 2019 AND motivo IN (
            'Ocio, recreo y vacaciones', 'Negocios y otros motivos profesionales',
            'Visitas a familiares o amigos', 'Otros motivos'
        ) THEN viajes END) AS total_2019,
        SUM(CASE WHEN anio = 2024 AND motivo IN (
            'Ocio, recreo y vacaciones', 'Negocios y otros motivos profesionales',
            'Visitas a familiares o amigos', 'Otros motivos'
        ) THEN viajes END) AS total_2024
    FROM turismo_residentes
    WHERE alojamiento_nivel1 = 'Total' AND anio IN (2016, 2019, 2024)
    GROUP BY id_ccaa
)
SELECT
    n.destino,
    -- Turismo nacional: volumen y crecimiento en 2 tramos
    n.nac_2016,
    n.nac_2019,
    n.nac_2024,
    ROUND((n.nac_2019 - n.nac_2016)::NUMERIC / NULLIF(n.nac_2016, 0) * 100, 1) AS crec_nac_16_19,
    ROUND((n.nac_2024 - n.nac_2019)::NUMERIC / NULLIF(n.nac_2019, 0) * 100, 1) AS crec_nac_19_24,
    -- Turismo extranjero: volumen y crecimiento en 2 tramos
    e.ext_2016,
    e.ext_2019,
    e.ext_2024,
    ROUND((e.ext_2019 - e.ext_2016)::NUMERIC / NULLIF(e.ext_2016, 0) * 100, 1) AS crec_ext_16_19,
    ROUND((e.ext_2024 - e.ext_2019)::NUMERIC / NULLIF(e.ext_2019, 0) * 100, 1) AS crec_ext_19_24,
    -- Gasto medio extranjero
    g.gasto_2016,
    g.gasto_2024,
    ROUND((g.gasto_2024 - g.gasto_2016)::NUMERIC / NULLIF(g.gasto_2016, 0) * 100, 1) AS crec_gasto_total_pct,
    -- Diversificación (cambio en % ocio en los 3 puntos)
    ROUND(o.ocio_2016::NUMERIC / NULLIF(o.total_2016, 0) * 100, 1) AS pct_ocio_2016,
    ROUND(o.ocio_2019::NUMERIC / NULLIF(o.total_2019, 0) * 100, 1) AS pct_ocio_2019,
    ROUND(o.ocio_2024::NUMERIC / NULLIF(o.total_2024, 0) * 100, 1) AS pct_ocio_2024
FROM viajes_nac n
LEFT JOIN turistas_ext e ON n.id_ccaa = e.id_ccaa
LEFT JOIN gasto_ext g ON n.id_ccaa = g.id_ccaa
LEFT JOIN ocio_nac o ON n.id_ccaa = o.id_ccaa
ORDER BY crec_ext_19_24 DESC NULLS LAST;

-- RESULTADO (2016 → 2019 → 2024):
-- Dos tramos de crecimiento permiten separar tendencia de fondo del efecto COVID.
-- crec_ext_16_19 = tendencia pre-COVID (3 años) / crec_ext_19_24 = post-COVID (5 años)
--
-- EMERGENTES ESTRUCTURALES (crec_ext positivo en AMBOS tramos):
--   País Vasco: ext +13.7% (16→19) + +29.2% (19→24) = líder post-COVID.
--     1.37M → 2.01M extranjeros. Ocio estable (37→43%) = diversificado.
--     Nacional baja -15.8% → se internacionaliza sin perder identidad.
--   Galicia: ext +65.9% + +12.0% = la gran estrella del primer tramo.
--     891K → 1.66M ext. Gasto +48.2% (mayor crecimiento de gasto de todas las CC.AA.).
--     Nacional estable (+1.1%, la única grande que recupera 2019).
--   Madrid: ext +32.1% + +15.5% = hub consolidado. Mayor gasto absoluto (1825€, +38.9%).
--     Ocio bajo y estable (34.6→35.4%) → perfil business/cultural, no vacacional.
--   C. Valenciana: ext +23.5% + +24.8% = crecimiento sostenido fuerte.
--     9.5M → 11.9M ext. Pero ocio sube (54.6→60.2%) → se está "balerizando".
--   Andalucía: ext +13.7% + +12.9% = crecimiento sólido y constante.
--     10.6M → 13.6M ext. Ocio subiendo (48.6→55.2%).
--   Baleares: ext +5.2% + +11.7%. Ocio 56.4→64.1% → concentración peligrosa.
--
-- REBOTE POST-COVID (crec_ext_16_19 negativo/plano, crec_ext_19_24 positivo):
--   Canarias: ext -0.6% → +16.3%. Estancado pre-COVID, despega después.
--     Gasto +32.1%. Nacional +4.6% (una de las pocas que crece en ambos mercados).
--   Cantabria: ext -12.8% → +16.4%. Perdía extranjeros, rebota.
--     Volumen bajo (318K). Ocio muy alto y subiendo (61→66%) → sol y playa.
--   CyL: ext -3.9% → +9.2%. Modesta recuperación. Nacional -15.3% (fuerte caída).
--     Gasto +44.2% pero desde base muy baja (477→688€, el menor de España).
--
-- EN RETROCESO (crec_ext negativo en el segundo tramo):
--   Murcia: ext +15.8% → -0.8%. Creció pre-COVID pero no recupera post.
--   Asturias: ext -19.7% → -9.4%. Declive continuo (203K→147K extranjeros).
--     Nacional también baja -8.7%. Ocio sube a 57.8% → pierde diversificación.
--   Aragón: ext -31.3% → -17.5%. Declive severo en ambos tramos y mercados.
--     Nacional: 8.0M → 6.7M. Ext: 497K → 282K. Ocio subió (43.5→54%).
--
-- DATOS POCO FIABLES (volúmenes demasiado bajos para conclusiones):
--   Navarra: ext 211K (2019) → 75K (2024) = -64.5%. Muy volátil por tamaño muestral.
--   CLM: ext 90K → 17K = -81.5%. Caída extrema, probablemente artefacto estadístico.
--   La Rioja: solo ext_2016=20K, sin datos 2019 ni 2024. Irrelevante.
--   Extremadura: sin datos de turistas extranjeros. Solo gasto (452→712€, +57.5%).
--
-- HALLAZGO - EL TURISMO NACIONAL NO SE HA RECUPERADO:
--   13 de 17 CC.AA. tienen crec_nac_19_24 negativo:
--     País Vasco -15.8%, CyL -15.3%, Navarra -14.7%, Aragón -9.4%, C. Valenciana -9.3%
--   Solo crecen en nacional: La Rioja +8.2%, Murcia +5.2%, Canarias +4.6%, Galicia +1.1%
--   Los españoles viajan MENOS que antes del COVID. El crecimiento turístico
--   post-pandemia se debe casi exclusivamente al turista extranjero.
--
-- GASTO MEDIO EXTRANJERO (sube en TODAS las CC.AA., 2016→2024):
--   Líder absoluto: Madrid 1825€ (+38.9%) → turista urbano de alto gasto.
--   Top: Canarias 1502€, Galicia 1455€, Murcia 1384€, Andalucía 1360€, CLM 1360€.
--   Mayor crecimiento: CLM +70.9%, Extremadura +57.5%, Galicia +48.2% (base baja).
--   Menor: País Vasco +7.0% (895→958€). Crece en volumen pero no en gasto.
--   NOTA: Estos crecimientos son en euros corrientes (nominales). La inflación acumulada
--   en España entre 2016 y 2024 (~20-25%) explica parte de la subida. Las CC.AA. con
--   crecimiento por debajo de ese rango (País Vasco +7%) probablemente experimentaron
--   una caída en gasto real. Deflactar requeriría IPC turístico regional y tipo de cambio,
--   lo cual queda fuera del alcance de este análisis.
--
-- CONCLUSIONES PARA EL PROYECTO:
--   1. País Vasco y Galicia confirman como emergentes estructurales (crecen en ambos
--      tramos con perfil diversificado). Son las mejores alternativas a masivos.
--   2. Madrid es un caso aparte: alternativo en perfil (ocio 35%) pero masivo en volumen.
--   3. C. Valenciana crece fuerte pero se concentra en ocio → riesgo de "balearización".
--   4. Aragón y Asturias pierden turistas en todos los frentes → necesitan reposicionarse.
--   5. El turismo nacional post-COVID no ha recuperado: la apuesta es por el extranjero.


-- ============================================================
-- QUERY 11: Oferta vs demanda de alojamiento por CC.AA.
-- Habilidades: CASE dentro de SUM/AVG, 4 CTEs con JOIN, ratios oferta/demanda
-- Objetivo: Cruzar plazas disponibles con viajeros reales por tipo de alojamiento
-- ============================================================
-- Usa dos tablas complementarias de las Encuestas de Ocupación del INE:
--   - oferta_alojamiento: plazas estimadas (capacidad)
--   - demanda_alojamiento: viajeros reales registrados en cada tipo de alojamiento
--
-- Antes estimábamos los turistas comerciales usando el % de alojamiento "de mercado"
-- de la ETR (turismo_residentes). Ahora tenemos datos REALES de viajeros registrados
-- en cada tipo de establecimiento, separados por residencia (Nacional/Extranjero).
--
-- Las plazas varían por mes (hoteles cierran en invierno), así que usamos
-- la media mensual de 2024 como indicador de capacidad típica.
-- Los viajeros son la SUMA anual de 2024 (todos los que se alojaron).
-- Presión = viajeros anuales / plazas medias → cuántos viajeros compiten
-- por cada plaza a lo largo del año.

WITH plazas AS (
    SELECT
        id_ccaa,
        destino,
        ROUND(AVG(CASE WHEN tipo_alojamiento = 'Hotelero' THEN plazas END)) AS plazas_hotel,
        ROUND(AVG(CASE WHEN tipo_alojamiento = 'Apartamento turístico' THEN plazas END)) AS plazas_apto,
        ROUND(AVG(CASE WHEN tipo_alojamiento = 'Camping' THEN plazas END)) AS plazas_camping,
        ROUND(AVG(CASE WHEN tipo_alojamiento = 'Turismo rural' THEN plazas END)) AS plazas_rural,
        ROUND(AVG(CASE WHEN tipo_alojamiento = 'Albergue' THEN plazas END)) AS plazas_albergue
    FROM oferta_alojamiento
    WHERE EXTRACT(YEAR FROM fecha) = 2024
    GROUP BY id_ccaa, destino
),
plazas_total AS (
    SELECT
        id_ccaa,
        plazas_hotel + COALESCE(plazas_apto, 0) + COALESCE(plazas_camping, 0)
            + COALESCE(plazas_rural, 0) + COALESCE(plazas_albergue, 0) AS plazas_total
    FROM plazas
),
viajeros AS (
    -- Viajeros reales registrados en alojamiento comercial (2024)
    -- Separados por residencia para ver la composición de la demanda
    -- NOTA: Se filtra residencia IS NOT NULL para excluir las filas "Total"
    -- del CSV (col5 vacío → residencia=NULL) que duplicarían el conteo.
    SELECT
        id_ccaa,
        SUM(CASE WHEN residencia = 'Nacional' THEN valor END) AS viajeros_nac,
        SUM(CASE WHEN residencia = 'Extranjero' THEN valor END) AS viajeros_ext,
        SUM(valor) AS viajeros_total
    FROM demanda_alojamiento
    WHERE metrica = 'Viajeros'
        AND EXTRACT(YEAR FROM fecha) = 2024
        AND residencia IS NOT NULL
    GROUP BY id_ccaa
),
pernoctaciones AS (
    -- Pernoctaciones totales (2024) para calcular estancia media
    SELECT
        id_ccaa,
        SUM(valor) AS pernoctaciones_total
    FROM demanda_alojamiento
    WHERE metrica = 'Pernoctaciones'
        AND EXTRACT(YEAR FROM fecha) = 2024
        AND residencia IS NOT NULL
    GROUP BY id_ccaa
)
SELECT
    p.destino,
    p.plazas_hotel,
    p.plazas_apto,
    p.plazas_camping,
    p.plazas_rural,
    p.plazas_albergue,
    pt.plazas_total,
    v.viajeros_nac,
    v.viajeros_ext,
    v.viajeros_total,
    -- Presión: viajeros totales / plazas totales
    ROUND(v.viajeros_total::NUMERIC / NULLIF(pt.plazas_total, 0), 1) AS presion_comercial,
    -- Estancia media: pernoctaciones / viajeros (días por viajero)
    ROUND(pe.pernoctaciones_total::NUMERIC / NULLIF(v.viajeros_total, 0), 2) AS estancia_media,
    -- % de viajeros extranjeros sobre el total
    ROUND(v.viajeros_ext::NUMERIC / NULLIF(v.viajeros_total, 0) * 100, 1) AS pct_extranjero
FROM plazas p
JOIN plazas_total pt ON p.id_ccaa = pt.id_ccaa
LEFT JOIN viajeros v ON p.id_ccaa = v.id_ccaa
LEFT JOIN pernoctaciones pe ON p.id_ccaa = pe.id_ccaa
ORDER BY pt.plazas_total DESC;

-- RESULTADO (2024, viajeros reales de Encuestas de Ocupación del INE):
-- presion_comercial = viajeros anuales / plazas medias mensuales.
-- Usa datos reales de check-ins en establecimientos (no estimaciones).
-- estancia_media = pernoctaciones / viajeros (noches por viajero).
-- pct_extranjero = viajeros extranjeros / viajeros totales en alojamiento registrado.
--
-- NOTA METODOLÓGICA:
--   Las Encuestas de Ocupación cuentan ENTRADAS en establecimientos, no personas únicas.
--   Un viajero que duerme en 3 hoteles = 3 viajeros. Esto es correcto para medir
--   presión sobre la infraestructura (cada check-in ocupa una plaza), pero difiere
--   de Frontur (personas únicas en frontera) y la ETR (viajes por hogar).
--   Las diferencias entre fuentes son metodológicas, no errores (verificado en Checks 1-5).
--
-- INFRAESTRUCTURA (plazas_total, media mensual 2024):
--   Top 5: Cataluña 511K, Andalucía 451K, Canarias 404K, C. Valenciana 351K, Baleares 265K
--   Medios: CyL 129K, Galicia 105K, Aragón 84K, CLM 67K, País Vasco 59K, Asturias 58K
--   Pequeños: Cantabria 49K, Murcia 46K, Extremadura 40K, Navarra 36K, La Rioja 18K
--
-- PRESIÓN COMERCIAL (presion_comercial = viajeros / plazas):
--   Muy alta (>80): Madrid 91.9, País Vasco 83.9, Ceuta 87.4
--     → Madrid: hub negocios + turismo urbano, capacidad limitada (166K plazas).
--     → País Vasco: destino "alternativo" ya consolidado. 46.5% extranjeros.
--   Alta (55-70): Galicia 67.7, Andalucía 57.0, Baleares 55.8, CyL 54.9, Navarra 54.4
--     → Galicia: efecto Camino de Santiago (albergues 11K plazas, estancia 1.87 noches).
--     → CyL: Camino + turismo rural. 32K plazas rurales (la mayor de España).
--     → Baleares: 85.8% extranjero (la mayor dependencia exterior de España).
--   Moderada (44-55): Cataluña 54.0, Extremadura 52.7, Asturias 48.5, Aragón 47.7,
--     La Rioja 46.5, CLM 45.6, Cantabria 44.3
--     → Cataluña: 511K plazas absorben 27.6M viajeros sin saturarse.
--     → Extremadura: sube de 26.5 (estimación) a 52.7 (real) → más uso comercial
--       del que la ETR sugería.
--   Baja (<45): Murcia 40.6, C. Valenciana 38.5, Canarias 36.4
--     → Canarias: baja presión pese a 14.7M viajeros gracias a 404K plazas.
--       Estancia media 6.76 noches (la mayor). Modelo resort: pocos check-ins, muchas noches.
--     → C. Valenciana: 38.5 pese a 13.5M viajeros. Mucho alojamiento no registrado
--       (apartamentos particulares, Airbnb) que no aparece en Encuestas de Ocupación.
--
-- ESTANCIA MEDIA (noches por viajero):
--   Larga (>4): Canarias 6.76, Apartamentos 5.09, Baleares 4.99 → sol y playa / vacacional
--   Media (3-4): C. Valenciana 3.97, Cataluña 3.21, Murcia 3.07, Andalucía 3.01
--   Corta (<3): Cantabria 2.82, Turismo rural 2.65, Asturias 2.37, Aragón 2.16,
--     Madrid 2.12, País Vasco 2.09, Navarra 2.08, La Rioja 1.96, CLM 1.95,
--     Extremadura 1.93, Albergues 1.89, Galicia 1.87, CyL 1.85
--   → Patrón claro: destinos de "ruta" (Camino, interior) = estancias cortas.
--     Destinos insulares/costeros = estancias largas.
--
-- DEPENDENCIA EXTERIOR (pct_extranjero en alojamiento registrado):
--   Muy alta (>60%): Baleares 85.8%, Canarias 79.1%
--     → Islas totalmente dependientes del turista extranjero.
--   Alta (40-60%): Cataluña 59.8%, Madrid 49.6%, Andalucía 47.5%,
--     País Vasco 46.5%, C. Valenciana 45.8%
--   Moderada (20-40%): Galicia 35.8%, Navarra 31.3%, Cantabria 25.3%,
--     La Rioja 25.0%, CyL 24.9%, Murcia 24.3%
--   Baja (<20%): Aragón 22.7%, Asturias 22.6%, Extremadura 17.5%, CLM 15.1%
--     → Interior peninsular: turismo casi 100% nacional.
--
-- CONCLUSIONES:
--   1. País Vasco (83.9) es el "alternativo" con mayor presión → necesita más capacidad.
--      Ya no es un destino emergente, es un destino consolidado con demanda real.
--   2. Galicia (67.7) sorprende con alta presión.
--      Su estancia corta (1.87) confirma el patrón de tránsito peregrino.
--   3. Canarias (36.4) tiene la menor presión entre los grandes pese a recibir
--      14.7M viajeros → su enorme oferta (404K plazas) absorbe la demanda.
--      El modelo resort (6.76 noches/viajero) es muy eficiente en uso de plazas.
--   4. C. Valenciana (38.5) y Murcia (40.6) muestran baja presión "oficial",
--      probablemente porque mucho turismo usa alojamiento no registrado.
--   5. Interior (CLM 45.6, Aragón 47.7, Asturias 48.5): presión moderada,
--      confirma que tienen capacidad de sobra para crecer.
