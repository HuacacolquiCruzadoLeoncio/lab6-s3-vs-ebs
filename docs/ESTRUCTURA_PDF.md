# Estructura sugerida del PDF (un solo archivo)

**Portada:** universidad, curso, "Laboratorio 6: Amazon S3 vs Amazon EBS", docente, **todos los integrantes del Grupo 6**, fecha.
**Enlace al repositorio** (el docente lo revisará).

## 1. Contexto y escenario (1 página)
- Proyecto: Sistema de Reclamos por Mensajería (serverless, sa-east-1). En el proyecto S3 solo aloja el frontend y no se usa EBS.
- Escenario de la comparación: **adjuntos de reclamos** (fotos/PDF). Supuestos con cifras (decláralos): p. ej. 50 000 reclamos/mes,
  2 adjuntos de ~2 MB, ≈ 200 GB nuevos por mes, pico de 6 000 usuarios concurrentes (RNF-09).
- Atributos y RNF que se comparan: rendimiento, escalabilidad, disponibilidad, recuperabilidad (RTO 1 h / RPO), costos.

## 2. Parte teórica (respuestas con tus palabras y con cifras)
1. **¿Qué problema resuelve cada servicio?** (objetos vs bloques; relación con los adjuntos).
2. **Tres beneficios principales de cada uno**, usando: administración / costos / vendor lock-in / curva de aprendizaje.
3. **Diferencias en escalabilidad y disponibilidad** (regional vs zonal, límites de IOPS/throughput, durabilidad, SLA). Cita la documentación de AWS.
4. **Escenarios de recomendación**
   - Cuándo S3 (con números) y cuándo EBS (con números).
   - Para el servicio que NO encaja: **qué tendría que cambiar el escenario o cómo adaptarlo para que funcione**
     (p. ej. EBS con varias EC2 + replicación entre AZ + snapshots programados; S3 como respaldo/archivo de una base alojada en EBS).
5. **Consecuencias técnicas y económicas de elegir mal** a 6 meses, 1 año y 3 años: costo (provisionado vs usado), operación (parches, capacidad),
   riesgo (una sola AZ), rediseño necesario. Apóyate en la salida de `06_cost_estimate.py`.

## 3. Parte práctica
3.1 Diseño del experimento: **diagrama comparativo único** (`docs/diagrama.mmd`), hipótesis, datos, métricas y requisitos
    (EC2 como complemento de EBS, IAM, endpoint, snapshot) y por qué cada uno es necesario.
3.2 Despliegue con Terraform (capturas 1-7).
3.3 Ejecución y evidencias de uso (capturas 8-18).
3.4 Resultados: tabla de `results/summary.md`, tiempos de T4 y T5, y costos (T7).

## 4. Análisis y conclusión
- Qué servicio conviene al proyecto para los adjuntos y por qué (con los números medidos).
- Qué sorprendió o no coincidió con la teoría (si EBS fue más rápido en latencia, dilo).
- Limitaciones de la prueba (ver README).

## 5. Referencias
Documentación de AWS (S3, EBS, SLA, precios) con fecha de consulta.

---
Recuerda: el docente detecta textos copiados de IA; redacta con tus palabras y explica tus propias mediciones.
