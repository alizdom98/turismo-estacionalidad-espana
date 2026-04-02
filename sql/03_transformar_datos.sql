-- ============================================================
-- PROYECTO: Destinos Turísticos Alternativos en España
-- Archivo: 03_transformar_datos.sql
-- Descripción: Transformación de datos staging → tablas finales
-- Autor: Andrés Liz Domínguez
-- Fecha: Febrero 2026
-- ============================================================

-- ============================================================
-- ¿QUÉ HACE ESTE SCRIPT?
-- ============================================================
-- Coge los datos "crudos" de las 7 tablas staging (todo TEXT) y los mueve
-- a las 6 tablas finales con los tipos de datos correctos.
--
-- Transformaciones aplicadas:
--   1. TRIM()                         → Quita espacios en blanco
--   2. LEFT(col, 2)::INTEGER           → Extrae código INE de CC.AA. ("01 Andalucía" → 1)
--   3. SUBSTRING(col FROM POS+1)      → Quita prefijo numérico de CC.AA. ("01 Andalucía" → "Andalucía")
--   4. REPLACE('.','')                → Quita puntos de miles ("10.080.750" → "10080750")
--   5. REPLACE(',','.')               → Cambia coma decimal a punto ("6,22" → "6.22")
--   6. ::BIGINT / ::NUMERIC / ::INTEGER → Convierte texto a número
--   7. IN ('','.','..') → NULL        → El INE usa "." y ".." para datos no disponibles
--   8. NULLIF(x,'')                   → Convierte strings vacíos en NULL
--   9. MAKE_DATE() / TO_DATE()        → Convierte periodos a DATE
--  10. Descarte de columnas constantes (Tipo de dato, Transporte, Organización, etc.)

-- ============================================================
-- TRANSFORMACIÓN 1: gasto_trimestral_nacional
-- ============================================================
-- Fuente: staging_gasto_nacional (5 columnas TEXT)
-- Destino: gasto_trimestral_nacional (6 columnas tipadas + id)
-- Columnas descartadas: col3 ("Tipo de dato" = siempre "Valor absoluto")
--
-- Parseo del periodo '2025T3':
--   - anio = LEFT(col4, 4) → 2025
--   - trimestre = RIGHT(col4, 1) → 3
--   - fecha = MAKE_DATE(2025, (3-1)*3+1, 1) → 2025-07-01 (primer día del trimestre)
--
-- Formato de números:
--   - Viajes: "10.080.750" → quitar puntos → 10080750
--   - Gasto total: "3.576.058,81" → quitar puntos → "3576058,81" → coma a punto → 3576058.81
--   - Duración media: "6,22" → coma a punto → 6.22
--   Todo se resuelve con REPLACE('.','') + REPLACE(',','.')

INSERT INTO gasto_trimestral_nacional (id_ccaa, destino, metrica, anio, trimestre, fecha, valor)
SELECT
    LEFT(TRIM(col1), 2)::INTEGER,
    TRIM(SUBSTRING(TRIM(col1) FROM POSITION(' ' IN TRIM(col1)) + 1)),
    TRIM(col2),
    LEFT(TRIM(col4), 4)::INTEGER,
    RIGHT(TRIM(col4), 1)::INTEGER,
    MAKE_DATE(
        LEFT(TRIM(col4), 4)::INTEGER,
        (RIGHT(TRIM(col4), 1)::INTEGER - 1) * 3 + 1,
        1
    ),
    CASE
        WHEN TRIM(col5) IN ('', '.', '..') OR col5 IS NULL THEN NULL
        ELSE REPLACE(REPLACE(TRIM(col5), '.', ''), ',', '.')::NUMERIC(14,2)
    END
FROM staging_gasto_nacional;

-- ============================================================
-- TRANSFORMACIÓN 2: turismo_residentes (desde motivos)
-- ============================================================
-- Fuente: staging_motivos_residentes (11 columnas TEXT)
-- Destino: turismo_residentes (6 columnas tipadas + id)
-- Columnas descartadas: col2 (siempre "Viajes"), col6 (Transporte = "Total"),
--   col7 (Organización = "Total"), col8 (Duración = "Total"), col9 (Residencia = "Total")
--
-- Este archivo tiene el desglose por MOTIVO del viaje.
-- Alojamiento está siempre en "Total" (col3='Total', col4 vacío).

INSERT INTO turismo_residentes (id_ccaa, destino, motivo, alojamiento_nivel1, alojamiento_nivel2, anio, viajes)
SELECT
    LEFT(TRIM(col1), 2)::INTEGER,
    TRIM(SUBSTRING(TRIM(col1) FROM POSITION(' ' IN TRIM(col1)) + 1)),
    TRIM(col5),                     -- Motivo principal (21 categorías incluyendo 'Total')
    NULLIF(TRIM(col3), ''),         -- Alojamiento Nivel 1 (siempre 'Total' en este archivo)
    NULLIF(TRIM(col4), ''),         -- Alojamiento Nivel 2 (siempre NULL en este archivo)
    TRIM(col10)::INTEGER,           -- Año
    CASE
        WHEN TRIM(col11) IN ('', '.', '..') OR col11 IS NULL THEN NULL
        ELSE REPLACE(TRIM(col11), '.', '')::BIGINT
    END
FROM staging_motivos_residentes;

-- ============================================================
-- TRANSFORMACIÓN 3: turismo_residentes (desde alojamiento)
-- ============================================================
-- Fuente: staging_alojamiento_residentes (11 columnas TEXT)
-- Destino: turismo_residentes (misma tabla, se añaden filas)
-- Columnas descartadas: las mismas que arriba
--
-- Este archivo tiene el desglose por TIPO DE ALOJAMIENTO.
-- Motivo está siempre en "Total" (col5='Total').
--
-- IMPORTANTE: Se excluyen las filas donde col3='Total' (Nivel 1 = Total)
-- porque esas son las mismas filas que ya tenemos del archivo de motivos
-- con motivo='Total' y alojamiento='Total' (el gran total por CC.AA. y año).

INSERT INTO turismo_residentes (id_ccaa, destino, motivo, alojamiento_nivel1, alojamiento_nivel2, anio, viajes)
SELECT
    LEFT(TRIM(col1), 2)::INTEGER,
    TRIM(SUBSTRING(TRIM(col1) FROM POSITION(' ' IN TRIM(col1)) + 1)),
    TRIM(col5),                     -- Motivo (siempre 'Total' en este archivo)
    NULLIF(TRIM(col3), ''),         -- Alojamiento Nivel 1 ('De mercado' o 'No de mercado')
    NULLIF(TRIM(col4), ''),         -- Alojamiento Nivel 2 (tipo específico o NULL si subtotal)
    TRIM(col10)::INTEGER,           -- Año
    CASE
        WHEN TRIM(col11) IN ('', '.', '..') OR col11 IS NULL THEN NULL
        ELSE REPLACE(TRIM(col11), '.', '')::BIGINT
    END
FROM staging_alojamiento_residentes
WHERE TRIM(col3) != 'Total';       -- Excluir totales que ya existen desde el archivo de motivos

-- Resultado esperado: INSERT 0 1900

-- ============================================================
-- TRANSFORMACIÓN 4: turismo_extranjeros_motivos
-- ============================================================
-- Fuente: staging_extranjeros_motivos (9 columnas TEXT)
-- Destino: turismo_extranjeros_motivos (4 columnas tipadas + id)
-- Columnas descartadas: col1 (Vía = "Total de vías de acceso"),
--   col4 (Alojamiento = "Total de tipos de alojamiento"),
--   col5 (Organización = "Total de formas de organización del viaje"),
--   col6 (Duración = "Total noches"), col7 (País = "Total país de residencia")
--
-- Parseo del periodo '2026M01':
--   - TO_DATE('2026' || '-' || '01' || '-01', 'YYYY-MM-DD') → 2026-01-01
--
-- NOTA: Los valores usan puntos como separador de miles (ej: "41.286" = 41286).
--       El INE usa "." solo como marcador de dato no disponible.
--       Para diferenciarlos: "." exacto → NULL, "41.286" con números → quitar punto.

INSERT INTO turismo_extranjeros_motivos (id_ccaa, destino, motivo, fecha, turistas)
SELECT
    LEFT(TRIM(col2), 2)::INTEGER,
    TRIM(SUBSTRING(TRIM(col2) FROM POSITION(' ' IN TRIM(col2)) + 1)),
    TRIM(col3),
    TO_DATE(
        LEFT(TRIM(col8), 4) || '-' || RIGHT(TRIM(col8), 2) || '-01',
        'YYYY-MM-DD'
    ),
    CASE
        WHEN TRIM(col9) IN ('', '.', '..') OR col9 IS NULL THEN NULL
        ELSE REPLACE(TRIM(col9), '.', '')::BIGINT
    END
FROM staging_extranjeros_motivos;

-- Resultado esperado: INSERT 0 ~6324

-- ============================================================
-- TRANSFORMACIÓN 5: gasto_turistas_extranjeros
-- ============================================================
-- Fuente: staging_gasto_extranjeros (5 columnas TEXT)
-- Destino: gasto_turistas_extranjeros (4 columnas tipadas + id)
-- Columnas descartadas: col3 ("Tipo de dato" = siempre "Dato base")
--
-- Formato de números:
--   - Gasto total: "20.032,82" → "20032,82" → "20032.82" → 20032.82
--   - Gasto medio por persona: "1.388" → "1388" → 1388.00
--   - Gasto medio diario: "178" → 178.00
--   - Duración media: "7,82" → "7.82" → 7.82

INSERT INTO gasto_turistas_extranjeros (id_ccaa, destino, metrica, anio, valor)
SELECT
    LEFT(TRIM(col1), 2)::INTEGER,
    TRIM(SUBSTRING(TRIM(col1) FROM POSITION(' ' IN TRIM(col1)) + 1)),
    TRIM(col2),
    TRIM(col4)::INTEGER,
    CASE
        WHEN TRIM(col5) IN ('', '.', '..') OR col5 IS NULL THEN NULL
        ELSE REPLACE(REPLACE(TRIM(col5), '.', ''), ',', '.')::NUMERIC(14,2)
    END
FROM staging_gasto_extranjeros;

-- Resultado esperado: INSERT 0 760

-- ============================================================
-- TRANSFORMACIÓN 6: oferta_alojamiento
-- ============================================================
-- Fuente: staging_plazas_establecimientos (6 columnas TEXT)
-- Destino: oferta_alojamiento (4 columnas tipadas + id)
-- Columnas descartadas: col2 ("Total Nacional", siempre igual)
--
-- Filtros aplicados:
--   - Solo métrica "Número de plazas estimadas" (no establecimientos ni personal)
--   - Solo filas con CC.AA. (excluir totales nacionales donde col3 está vacío)
--   - Solo desde 2016 en adelante
--
-- Mapeo del nombre de la encuesta a tipo de alojamiento simplificado:
--   "Encuesta de Ocupación Hotelera"                         → "Hotelero"
--   "Encuesta de Ocupación en Apartamentos Turísticos"       → "Apartamento turístico"
--   "Encuesta de Ocupación en Campings"                      → "Camping"
--   "Encuesta de Ocupación en Alojamientos de Turismo Rural" → "Turismo rural"
--   "Encuesta de Ocupación en Albergues"                     → "Albergue"
--
-- Parseo del periodo '2026M01': igual que turismo_extranjeros_motivos.
-- Formato de números: "11.839" → quitar punto → 11839 (solo miles, no decimales).

INSERT INTO oferta_alojamiento (id_ccaa, destino, tipo_alojamiento, fecha, plazas)
SELECT
    LEFT(TRIM(col3), 2)::INTEGER,
    TRIM(SUBSTRING(TRIM(col3) FROM POSITION(' ' IN TRIM(col3)) + 1)),
    CASE
        WHEN col1 LIKE '%Hotelera' THEN 'Hotelero'
        WHEN col1 LIKE '%Apartamentos%' THEN 'Apartamento turístico'
        WHEN col1 LIKE '%Campings' THEN 'Camping'
        WHEN col1 LIKE '%Rural' THEN 'Turismo rural'
        WHEN col1 LIKE '%Albergues' THEN 'Albergue'
    END,
    TO_DATE(
        LEFT(TRIM(col5), 4) || '-' || RIGHT(TRIM(col5), 2) || '-01',
        'YYYY-MM-DD'
    ),
    CASE
        WHEN TRIM(col6) IN ('', '.', '..') OR col6 IS NULL THEN NULL
        ELSE REPLACE(TRIM(col6), '.', '')::BIGINT
    END
FROM staging_plazas_establecimientos
WHERE TRIM(col4) = 'Número de plazas estimadas'
    AND TRIM(col3) != ''
    AND col3 IS NOT NULL
    AND LEFT(TRIM(col5), 4)::INTEGER >= 2016;

-- Resultado esperado: INSERT 0 ~11.400

-- ============================================================
-- TRANSFORMACIÓN 7: demanda_alojamiento
-- ============================================================
-- Fuente: staging_demanda_alojamiento (8 columnas TEXT)
-- Destino: demanda_alojamiento (6 columnas tipadas + id)
-- Columnas descartadas: col2 ("Total Nacional", siempre igual),
--   col4 (Residencia Nivel 1 = siempre "Total")
--
-- Filtros aplicados:
--   - Solo filas con CC.AA. (excluir totales nacionales donde col3 está vacío)
--   - Solo desde 2016 en adelante (coherente con oferta_alojamiento)
--
-- Mapeo del nombre de la encuesta a tipo de alojamiento:
--   Igual que en transformación 6 (oferta_alojamiento)
--
-- Mapeo de residencia:
--   "Residentes en España"         → "Nacional"
--   "Residentes en el Extranjero"  → "Extranjero"
--
-- Mapeo de métrica:
--   "Viajero"         → "Viajeros"         (se pluraliza para coherencia)
--   "Pernoctaciones"  → "Pernoctaciones"   (se mantiene igual)
--
-- Parseo del periodo '2026M01': igual que transformaciones 4 y 6.
-- Formato de números: "11.839" → quitar punto → 11839 (solo miles, no decimales).

INSERT INTO demanda_alojamiento (id_ccaa, destino, tipo_alojamiento, residencia, metrica, fecha, valor)
SELECT
    LEFT(TRIM(col3), 2)::INTEGER,
    TRIM(SUBSTRING(TRIM(col3) FROM POSITION(' ' IN TRIM(col3)) + 1)),
    CASE
        WHEN col1 LIKE '%Hotelera' THEN 'Hotelero'
        WHEN col1 LIKE '%Apartamentos%' THEN 'Apartamento turístico'
        WHEN col1 LIKE '%Campings' THEN 'Camping'
        WHEN col1 LIKE '%Rural' THEN 'Turismo rural'
        WHEN col1 LIKE '%Albergues' THEN 'Albergue'
    END,
    CASE
        WHEN TRIM(col5) LIKE 'Residentes en Espa%' THEN 'Nacional'
        WHEN TRIM(col5) LIKE 'Residentes en el Extranjero' THEN 'Extranjero'
    END,
    CASE
        WHEN TRIM(col6) = 'Viajero' THEN 'Viajeros'
        ELSE TRIM(col6)
    END,
    TO_DATE(
        LEFT(TRIM(col7), 4) || '-' || RIGHT(TRIM(col7), 2) || '-01',
        'YYYY-MM-DD'
    ),
    CASE
        WHEN TRIM(col8) IN ('', '.', '..') OR col8 IS NULL THEN NULL
        ELSE REPLACE(TRIM(col8), '.', '')::BIGINT
    END
FROM staging_demanda_alojamiento
WHERE TRIM(col3) != ''
    AND col3 IS NOT NULL
    AND LEFT(TRIM(col7), 4)::INTEGER >= 2016;

-- Resultado esperado: INSERT 0 ~38.000

-- ============================================================
-- VERIFICACIÓN
-- ============================================================

SELECT 'gasto_trimestral_nacional' AS tabla, COUNT(*) AS filas FROM gasto_trimestral_nacional
UNION ALL
SELECT 'turismo_residentes', COUNT(*) FROM turismo_residentes
UNION ALL
SELECT 'turismo_extranjeros_motivos', COUNT(*) FROM turismo_extranjeros_motivos
UNION ALL
SELECT 'gasto_turistas_extranjeros', COUNT(*) FROM gasto_turistas_extranjeros
UNION ALL
SELECT 'oferta_alojamiento', COUNT(*) FROM oferta_alojamiento
UNION ALL
SELECT 'demanda_alojamiento', COUNT(*) FROM demanda_alojamiento;

SELECT * FROM gasto_trimestral_nacional LIMIT 5;
SELECT * FROM turismo_residentes LIMIT 5;
SELECT * FROM turismo_extranjeros_motivos LIMIT 5;
SELECT * FROM gasto_turistas_extranjeros LIMIT 5;
SELECT * FROM oferta_alojamiento LIMIT 5;
SELECT * FROM demanda_alojamiento LIMIT 5;

-- ============================================================
-- LIMPIEZA: Eliminar filas con valor NULL
-- ============================================================
-- El INE usa "." y ".." para datos no disponibles, que ya convertimos a NULL.
-- Estas filas sin valor distorsionan cálculos, así que las eliminamos.

DELETE FROM gasto_trimestral_nacional WHERE valor IS NULL;
DELETE FROM turismo_residentes WHERE viajes IS NULL;
DELETE FROM turismo_extranjeros_motivos WHERE turistas IS NULL;
DELETE FROM gasto_turistas_extranjeros WHERE valor IS NULL;
DELETE FROM oferta_alojamiento WHERE plazas IS NULL;
DELETE FROM demanda_alojamiento WHERE valor IS NULL;

-- ============================================================
-- VERIFICACIÓN FINAL
-- ============================================================

SELECT 'gasto_trimestral_nacional' AS tabla, COUNT(*) AS filas FROM gasto_trimestral_nacional
UNION ALL
SELECT 'turismo_residentes', COUNT(*) FROM turismo_residentes
UNION ALL
SELECT 'turismo_extranjeros_motivos', COUNT(*) FROM turismo_extranjeros_motivos
UNION ALL
SELECT 'gasto_turistas_extranjeros', COUNT(*) FROM gasto_turistas_extranjeros
UNION ALL
SELECT 'oferta_alojamiento', COUNT(*) FROM oferta_alojamiento
UNION ALL
SELECT 'demanda_alojamiento', COUNT(*) FROM demanda_alojamiento;

-- ============================================================
-- LIMPIEZA: Eliminar las tablas staging
-- ============================================================
DROP TABLE IF EXISTS staging_gasto_nacional;
DROP TABLE IF EXISTS staging_motivos_residentes;
DROP TABLE IF EXISTS staging_alojamiento_residentes;
DROP TABLE IF EXISTS staging_extranjeros_motivos;
DROP TABLE IF EXISTS staging_gasto_extranjeros;
DROP TABLE IF EXISTS staging_plazas_establecimientos;
DROP TABLE IF EXISTS staging_demanda_alojamiento;
