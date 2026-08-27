"""
scoring-api.py
Santamaría Collection — SST Pro

Microservicio FastAPI que expone scoring-model.py como endpoint HTTP.
El collector Node.js llama a este servicio para puntuar leads en tiempo real.

Arranque:
  pip install fastapi uvicorn
  uvicorn scoring-api:app --host 0.0.0.0 --port 8001 --workers 2
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import logging

from scoring_model import score_lead

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("scorer")

app = FastAPI(title="SMC Lead Scorer", version="1.0.0")


class LeadPayload(BaseModel):
    lead_id:              Optional[str]   = None
    source:               Optional[str]   = "unknown"
    property_id:          Optional[str]   = None
    email:                Optional[bool]  = False
    phone:                Optional[bool]  = False
    first_name:           Optional[bool]  = False
    fbp:                  Optional[bool]  = False
    property_views:       Optional[int]   = 0
    time_on_site_seconds: Optional[int]   = 0
    pages_visited:        Optional[int]   = 0
    cta_clicks:           Optional[int]   = 0
    scroll_depth_pct:     Optional[float] = 0.0
    repeat_visit:         Optional[bool]  = False


@app.post("/score")
def score_endpoint(payload: LeadPayload):
    try:
        result = score_lead(payload.dict())
        logger.info(
            f"[Scorer] lead_id={result['lead_id']} "
            f"score={result['lead_score']} "
            f"status={result['lead_status']}"
        )
        return result
    except Exception as e:
        logger.error(f"[Scorer] Error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
def health():
    return {"ok": True}
