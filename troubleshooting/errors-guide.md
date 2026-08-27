# Guía de Errores

## Meta Rechaza Eventos

### Error: "Invalid user_data"
- **Causa:** Email no está hashed correctamente
- **Solución:** Usar SHA-256 lowercase + stripped
- **Verificar:** `echo -n "test@example.com" | sha256sum`

### Error: "Invalid event_id"
- **Causa:** event_id duplicado o formato incorrecto
- **Solución:** Usar UUID v4 o timestamp + random
- **Prevenir:** Deduplicación en base de datos

### Error: "Custom data validation failed"
- **Causa:** Campo personalizado no reconocido
- **Solución:** Revisar naming convention (snake_case vs camelCase)

## Baja Entrega de Leads

1. Verificar eventos llegan a queue
2. Verificar transformer no tiene errores
3. Verificar deduplicación no está eliminando eventos válidos
4. Revisar Meta error logs
5. Comprobar presupuesto disponible en campaña

## CPL Disparado

1. Revisar lead quality score
2. Verificar scoring model está calibrado
3. Comprobar segmentación de audiencia en Meta
4. Revisar creativas de anuncios
5. Analizar cambios en campaña o targeting
