from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from scoring_model import score_lead

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
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health():
    return {"ok": True}
