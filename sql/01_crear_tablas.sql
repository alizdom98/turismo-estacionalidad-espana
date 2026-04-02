-- ============================================================
-- PROYECTO: Destinos Turísticos Alternativos en España
-- Archivo: 01_crear_tablas.sql
-- Descripción: Creación de la base de datos y las tablas
-- Autor: Andrés Liz Domínguez
-- Fecha: Febrero 2026
-- ============================================================

-- PASO 1: Crear la base de datos
-- (Desde pgAdmin: clic derecho en "Databases" → Create → Database)
-- Nombre: turismo_estacionalidad
-- Encoding: UTF8

-- ============================================================
-- TABLA 1: gasto_trimestral_nacional
-- ============================================================
-- Fuente: datos_trimestrales_gasto_nacional.csv (INE - Encuesta de Turismo de Residentes)
-- Contiene: viajes, pernoctaciones, duración media, gasto total y gasto medio
--           de los turistas residentes en España, por CC.AA. de destino
-- Periodo: 2015T1 - 2025T3 (trimestral)
-- Métricas: Viajes, Pernoctaciones, Duración media de los viajes,
--           Gasto total, Gasto medio por persona

CREATE TABLE gasto_trimestral_nacional (
    id SERIAL PRIMARY KEY,
    id_ccaa INTEGER,                -- Código INE de la CC.AA. (01-19)
    destino VARCHAR(60),            -- CC.AA. de destino 
    metrica VARCHAR(60),            -- Tipo de dato (5 métricas diferentes)
    anio INTEGER,                   -- Año extraído de '2025T3'
    trimestre INTEGER,              -- Trimestre (1-4)
    fecha DATE,                     -- Primer día del trimestre: 2025-07-01
    valor NUMERIC(14,2)             -- Valor numérico (enteros o decimales según métrica)
);

-- ============================================================
-- TABLA 2: turismo_residentes
-- ============================================================
-- Fuente: motivos_turistas_residentes.csv + alojamiento_turistas_residentes.csv
--         (INE - Encuesta de Turismo de Residentes)
-- Contiene: viajes de turistas residentes en España por motivo y tipo de alojamiento
-- Periodo: 2015 - 2024 (anual)
-- NOTA: Se fusionan 2 archivos. Cada fila tiene o bien un motivo específico
--       (con alojamiento='Total') o bien un alojamiento específico (con motivo='Total'),
--       porque los datos se descargaron por separado del INE.

CREATE TABLE turismo_residentes (
    id SERIAL PRIMARY KEY,
    id_ccaa INTEGER,                -- Código INE de la CC.AA. (01-19)
    destino VARCHAR(60),            -- CC.AA. de destino 
    motivo VARCHAR(80),             -- Motivo principal del viaje (o 'Total')
    alojamiento_nivel1 VARCHAR(30), -- 'Total', 'De mercado' o 'No de mercado'
    alojamiento_nivel2 VARCHAR(60), -- Tipo específico: 'Hotelero', 'Camping', etc. (NULL si subtotal)
    anio INTEGER,                   -- Año (2015-2024)
    viajes BIGINT                   -- Número de viajes
);

-- ============================================================
-- TABLA 3: turismo_extranjeros_motivos
-- ============================================================
-- Fuente: motivos_turistas_extranjeros.csv (INE - Frontur)
-- Contiene: turistas extranjeros que visitan España, por CC.AA. y motivo del viaje
-- Periodo: Octubre 2015 - Enero 2026 (mensual)
-- Motivos: Ocio, recreo y vacaciones / Negocios / Otros motivos

CREATE TABLE turismo_extranjeros_motivos (
    id SERIAL PRIMARY KEY,
    id_ccaa INTEGER,                -- Código INE de la CC.AA. (01-19)
    destino VARCHAR(60),            -- CC.AA. de destino 
    motivo VARCHAR(60),             -- Motivo del viaje (3 categorías)
    fecha DATE,                     -- Primer día del mes: 2026-01-01
    turistas BIGINT                 -- Número de turistas
);

-- ============================================================
-- TABLA 4: gasto_turistas_extranjeros
-- ============================================================
-- Fuente: gasto_turistas_extranjeros.csv (INE - Egatur)
-- Contiene: gasto y duración media de los turistas extranjeros por CC.AA.
-- Periodo: 2016 - 2025 (anual)
-- Métricas: Gasto total, Gasto medio por persona, Gasto medio diario, Duración media

CREATE TABLE gasto_turistas_extranjeros (
    id SERIAL PRIMARY KEY,
    id_ccaa INTEGER,                -- Código INE de la CC.AA. (01-19)
    destino VARCHAR(60),            -- CC.AA. de destino 
    metrica VARCHAR(60),            -- Tipo de dato (4 métricas)
    anio INTEGER,                   -- Año (2016-2025)
    valor NUMERIC(14,2)             -- Valor numérico (euros o noches según métrica)
);

-- ============================================================
-- TABLA 5: oferta_alojamiento
-- ============================================================
-- Fuente: plazas_establecimientos.csv (INE - Encuestas de Ocupación)
-- Contiene: plazas estimadas por tipo de alojamiento y CC.AA.
-- Periodo: Enero 2016 - Enero 2026 (mensual)
-- Tipos: Hotelero, Apartamento turístico, Camping, Turismo rural, Albergue
-- Solo se importa la métrica "Número de plazas estimadas" (no establecimientos ni personal)

CREATE TABLE oferta_alojamiento (
    id SERIAL PRIMARY KEY,
    id_ccaa INTEGER,                -- Código INE de la CC.AA. (01-19)
    destino VARCHAR(60),            -- CC.AA. de destino 
    tipo_alojamiento VARCHAR(60),   -- Tipo: Hotelero, Apartamento turístico, Camping, etc.
    fecha DATE,                     -- Primer día del mes: 2024-08-01
    plazas BIGINT                   -- Número de plazas estimadas
);

-- ============================================================
-- TABLA 6: demanda_alojamiento
-- ============================================================
-- Fuente: tipos_alojamiento_CC.AA.csv (INE - Encuestas de Ocupación)
-- Contiene: viajeros y pernoctaciones por tipo de alojamiento, CC.AA. y residencia
-- Periodo: Enero 2016 - Enero 2026 (mensual)
-- Tipos: Hotelero, Apartamento turístico, Camping, Turismo rural, Albergue
-- Residencia: Nacional (residentes en España) o Extranjero (residentes en el extranjero)
-- Complementa a oferta_alojamiento: oferta = plazas disponibles, demanda = viajeros reales

CREATE TABLE demanda_alojamiento (
    id SERIAL PRIMARY KEY,
    id_ccaa INTEGER,                -- Código INE de la CC.AA. (01-19)
    destino VARCHAR(60),            -- CC.AA. de destino 
    tipo_alojamiento VARCHAR(60),   -- Tipo: Hotelero, Apartamento turístico, Camping, etc.
    residencia VARCHAR(20),         -- 'Nacional' o 'Extranjero'
    metrica VARCHAR(20),            -- 'Viajeros' o 'Pernoctaciones'
    fecha DATE,                     -- Primer día del mes: 2024-08-01
    valor BIGINT                    -- Número de viajeros o pernoctaciones
);

-- NOTAS:
-- - id_ccaa es el código numérico del INE ("01 Andalucía" → id_ccaa=1, destino="Andalucía")
--   Permite JOINs fiables entre tablas aunque los nombres varíen entre encuestas
-- - gasto_trimestral_nacional usa NUMERIC(14,2) porque mezcla enteros (viajes) con decimales (gasto)
-- - turismo_residentes usa BIGINT porque solo contiene conteos de viajes (siempre enteros)
-- - Los periodos originales del INE ('2025T3', '2024', '2026M01') se convierten a tipos
--   DATE o INTEGER en el script de transformación
