# Claude Server-Side Tracking Pro

Sistema expert de server-side tracking para maximizar generación y calidad de leads en Meta (Facebook, Instagram).

## 📋 Estructura del Proyecto

```
├── eventos/           # Taxonomía y schema de eventos
├── meta/              # Integración Meta Conversions API
├── codigo/            # Implementaciones clave (Node.js, Python)
├── sql/               # Queries para análisis y validación
├── scoring/           # Modelo ML de scoring de leads
├── testing/           # QA checklist y test datasets
├── configuracion/     # .env, docker-compose, estructura
├── troubleshooting/   # Guías de debugging y errores
├── learnings/         # Casos de estudio y optimizaciones
└── docs/              # Documentación adicional
```

## 🚀 Quick Start

1. Clonar repo
2. Copiar `.env.example` a `.env`
3. Configurar credenciales Meta
4. `docker-compose up`
5. Ver `/eventos/event-taxonomy.json` para entender eventos

## 📊 Roadmap (Fases)

1. **Infraestructura** (2 sem) - Setup de tracking server
2. **Instrumentación** (3 sem) - Capturar eventos en cliente
3. **Meta CAPI** (1 sem) - Integración con Meta
4. **Scoring** (2 sem) - Modelo de calificación de leads
5. **Campañas** (1 sem) - Setup en Ads Manager
6. **Lanzamiento** (2 sem) - Launch y primeros datos
7. **Optimización** (Continuo) - Mejora iterativa

## 🎯 Objetivos

- **CPL:** Reducir 40-50% vs baseline
- **CPQL:** Reducir 50-60% vs baseline
- **Lead Quality:** Aumentar 25%+ SQL rate
- **Escalabilidad:** 10K+ eventos/segundo

## 📚 Documentación Clave

- [Event Taxonomy](eventos/event-taxonomy.json)
- [Meta CAPI Mapping](meta/capi-mapping.json)
- [QA Checklist](testing/qa-checklist.md)
- [Troubleshooting](troubleshooting/errors-guide.md)

## 👨‍💻 Tech Stack

- **Backend:** Node.js, Python
- **Cloud:** AWS (Lambda, SQS, S3)
- **Database:** PostgreSQL, Redis
- **Analytics:** BigQuery, Looker
- **Integration:** Meta Conversions API

## 📞 Contacto

Para preguntas sobre el sistema, contactar a:
- Tech Lead: [tu email]
- Performance Marketing: [tu email]

---

**Status:** In Development  
**Última actualización:** 2024-08-27  
**Versión:** 0.1.0
