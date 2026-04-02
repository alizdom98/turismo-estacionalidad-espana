-- ============================================================
-- PROYECTO: Destinos Turísticos Alternativos en España
-- Archivo: 02_importar_datos.sql
-- Descripción: Importación de los CSV del INE a PostgreSQL
-- Autor: Andrés Liz Domínguez
-- Fecha: Febrero 2026
-- ============================================================

-- ============================================================
-- ORIGEN DE LOS DATOS
-- ============================================================
-- Los datos se descargaron del Instituto Nacional de Estadística (INE):
--   1. Encuesta de Turismo de Residentes (ETR/Familitur):
--      - datos_trimestrales_gasto_nacional.csv (viajes, pernoctaciones, gasto por CC.AA.)
--      - motivos_turistas_residentes.csv (viajes por motivo y CC.AA.)
--      - alojamiento_turistas_residentes.csv (viajes por tipo de alojamiento y CC.AA.)
--   2. Frontur (Movimientos Turísticos en Fronteras):
--      - motivos_turistas_extranjeros.csv (turistas extranjeros por motivo y CC.AA.)
--   3. Egatur (Encuesta de Gasto Turístico):
--      - gasto_turistas_extranjeros.csv (gasto y duración media por CC.AA.)
--   4. Encuestas de Ocupación en Alojamientos Turísticos:
--      (Agrupa 5 encuestas: Hotelera, Apartamentos, Campings, Turismo rural, Albergues)
--      - plazas_establecimientos.csv (plazas estimadas por tipo de alojamiento y CC.AA.)
--      - tipos_alojamiento_CC.AA.csv (viajeros y pernoctaciones por tipo, CC.AA. y residencia)
-- Formato: CSV separado por punto y coma (;), codificación LATIN1 ,
-- excepto los 2 CSV de Encuestas de Ocupación que tienen BOM UTF-8

-- ============================================================
-- MÉTODO DE IMPORTACIÓN (3 pasos)
-- ============================================================
-- Se usa un enfoque de "staging tables" porque los CSV del INE tienen:
--   - Números con formato español (puntos como separador de miles: "10.080.750")
--   - Valores decimales con coma ("6,22" y "3.576.058,81")
--   - Valores vacíos y "." / ".." para datos no disponibles
--   - Columnas constantes que no necesitamos (ej: "Tipo de dato" = siempre "Valor absoluto")
--
-- Por eso se importa primero todo como TEXT y después se transforma.

-- ============================================================
-- PASO 1: Crear tablas staging (todo como TEXT)
-- ============================================================

-- Staging para datos_trimestrales_gasto_nacional.csv (5 columnas)
CREATE TABLE staging_gasto_nacional (
    col1 TEXT,  -- Destino (CC.AA. con prefijo: "01 Andalucía")
    col2 TEXT,  -- Concepto turístico (métrica)
    col3 TEXT,  -- Tipo de dato (siempre "Valor absoluto", no la usamos)
    col4 TEXT,  -- Periodo ("2025T3")
    col5 TEXT   -- Total (valor numérico)
);

-- Staging para motivos_turistas_residentes.csv (11 columnas)
CREATE TABLE staging_motivos_residentes (
    col1 TEXT,   -- Destino principal (CC.AA. con prefijo)
    col2 TEXT,   -- Concepto turístico (siempre "Viajes", no la usamos)
    col3 TEXT,   -- Alojamiento principal: Nivel 1 (siempre "Total" en este archivo)
    col4 TEXT,   -- Alojamiento principal: Nivel 2 (siempre vacío en este archivo)
    col5 TEXT,   -- Motivo principal (21 categorías)
    col6 TEXT,   -- Transporte principal (siempre "Total", no la usamos)
    col7 TEXT,   -- Forma de organización del viaje (siempre "Total", no la usamos)
    col8 TEXT,   -- Duración del viaje (siempre "Total", no la usamos)
    col9 TEXT,   -- Comunidad autónoma de residencia (siempre "Total", no la usamos)
    col10 TEXT,  -- Periodo (año: "2024")
    col11 TEXT   -- Total (valor numérico: viajes)
);

-- Staging para alojamiento_turistas_residentes.csv (11 columnas, misma estructura)
CREATE TABLE staging_alojamiento_residentes (
    col1 TEXT,   -- Destino principal (CC.AA. con prefijo)
    col2 TEXT,   -- Concepto turístico (siempre "Viajes", no la usamos)
    col3 TEXT,   -- Alojamiento principal: Nivel 1 ("De mercado", "No de mercado", "Total")
    col4 TEXT,   -- Alojamiento principal: Nivel 2 ("Hotelero", "Camping", etc.)
    col5 TEXT,   -- Motivo principal (siempre "Total" en este archivo)
    col6 TEXT,   -- Transporte principal (siempre "Total", no la usamos)
    col7 TEXT,   -- Forma de organización del viaje (siempre "Total", no la usamos)
    col8 TEXT,   -- Duración del viaje (siempre "Total", no la usamos)
    col9 TEXT,   -- Comunidad autónoma de residencia (siempre "Total", no la usamos)
    col10 TEXT,  -- Periodo (año: "2024")
    col11 TEXT   -- Total (valor numérico: viajes)
);

-- Staging para motivos_turistas_extranjeros.csv (9 columnas)
CREATE TABLE staging_extranjeros_motivos (
    col1 TEXT,  -- Vía de acceso (siempre "Total de vías de acceso", no la usamos)
    col2 TEXT,  -- Comunidad autónoma de destino (CC.AA. con prefijo)
    col3 TEXT,  -- Motivo del viaje (3 categorías)
    col4 TEXT,  -- Tipo de alojamiento (siempre "Total de tipos de alojamiento", no la usamos)
    col5 TEXT,  -- Forma de organización del viaje (siempre "Total de formas...", no la usamos)
    col6 TEXT,  -- Duración del viaje (siempre "Total noches", no la usamos)
    col7 TEXT,  -- País de residencia (siempre "Total país de residencia", no la usamos)
    col8 TEXT,  -- Periodo ("2026M01")
    col9 TEXT   -- Total (valor numérico: turistas)
);

-- Staging para gasto_turistas_extranjeros.csv (5 columnas)
CREATE TABLE staging_gasto_extranjeros (
    col1 TEXT,  -- Comunidades autónomas (CC.AA. con prefijo)
    col2 TEXT,  -- Gastos y duración media de los viajes (métrica)
    col3 TEXT,  -- Tipo de dato (siempre "Dato base", no la usamos)
    col4 TEXT,  -- Periodo (año: "2025")
    col5 TEXT   -- Total (valor numérico)
);

-- Staging para plazas_establecimientos.csv (6 columnas)
CREATE TABLE staging_plazas_establecimientos (
    col1 TEXT,  -- Tipo de alojamiento (encuesta: "Encuesta de Ocupación Hotelera", etc.)
    col2 TEXT,  -- "Total Nacional" (siempre igual, no la usamos)
    col3 TEXT,  -- Comunidad autónoma (CC.AA. con prefijo, o vacío para total nacional)
    col4 TEXT,  -- Métrica (establecimientos, plazas, personal)
    col5 TEXT,  -- Periodo ("2026M01")
    col6 TEXT   -- Total (valor numérico)
);

-- Staging para tipos_alojamiento_CC.AA.csv (8 columnas)
CREATE TABLE staging_demanda_alojamiento (
    col1 TEXT,  -- Tipo de alojamiento (encuesta: "Encuesta de Ocupación Hotelera", etc.)
    col2 TEXT,  -- "Total Nacional" (siempre igual, no la usamos)
    col3 TEXT,  -- Comunidad autónoma (CC.AA. con prefijo, o vacío para total nacional)
    col4 TEXT,  -- Residencia Nivel 1 (siempre "Total", no la usamos)
    col5 TEXT,  -- Residencia Nivel 2 ("Residentes en España" / "Residentes en el Extranjero")
    col6 TEXT,  -- Viajeros y pernoctaciones ("Viajero" o "Pernoctaciones")
    col7 TEXT,  -- Periodo ("2026M01")
    col8 TEXT   -- Total (valor numérico)
);

-- ============================================================
-- PASO 2: Importar los CSV desde pgAdmin
-- ============================================================
-- Para cada tabla staging:
--   1. Clic derecho en la tabla → Import/Export Data...
--   2. Seleccionar "Import" y buscar el archivo CSV
--   3. Configurar: Format=csv, Header=Yes, Delimiter=;
--      Encoding: LATIN1 para los 5 primeros CSV, UTF8 para los 2 últimos
--   4. Clic en OK
--
-- NOTA ENCODING: Los CSV descargados del INE usan LATIN1.
-- Sin embargo, plazas_establecimientos.csv y tipos_alojamiento_CC.AA.csv tienen
-- BOM UTF-8 → importar como UTF8. Si se importan como LATIN1, los caracteres
-- acentuados se corrompen y las transformaciones fallan.
--
-- Importaciones:
--   staging_gasto_nacional         ← datos_trimestrales_gasto_nacional.csv  → 4.085 filas  (LATIN1)
--   staging_motivos_residentes     ← motivos_turistas_residentes.csv        → 3.990 filas  (LATIN1)
--   staging_alojamiento_residentes ← alojamiento_turistas_residentes.csv    → 2.090 filas  (LATIN1)
--   staging_extranjeros_motivos    ← motivos_turistas_extranjeros.csv       → 6.324 filas  (LATIN1)
--   staging_gasto_extranjeros      ← gasto_turistas_extranjeros.csv         → 760 filas    (LATIN1)
--   staging_plazas_establecimientos ← plazas_establecimientos.csv           → 90.300 filas (UTF8)
--   staging_demanda_alojamiento    ← tipos_alojamiento_CC.AA.csv           → 180.600 filas (UTF8)

-- ============================================================
-- PASO 3: Transformar y cargar en las tablas finales
-- ============================================================
-- (Ver archivo 03_transformar_datos.sql)
