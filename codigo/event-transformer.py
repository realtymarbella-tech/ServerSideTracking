# event-transformer.py - Transformar eventos propios a formato Meta CAPI

import json
import hashlib
from datetime import datetime

class EventTransformer:
    def __init__(self, capi_mapping):
        self.mapping = capi_mapping
    
    def hash_pii(self, value):
        """Hash SHA-256 de PII para Meta"""
        if not value:
            return None
        return hashlib.sha256(value.lower().strip().encode()).hexdigest()
    
    def transform_to_meta(self, event):
        """Transforma evento propio a formato Meta CAPI"""
        event_name = event.get('eventName')
        
        if event_name not in self.mapping:
            raise ValueError(f"Unknown event: {event_name}")
        
        mapping = self.mapping[event_name]
        meta_event = mapping['parametros_meta']
        
        # Construir Meta event
        meta_payload = {
            'event_name': meta_event['event_name'],
            'event_id': self._generate_event_id(event, meta_event),
            'event_time': int(datetime.fromisoformat(event['timestamp']).timestamp()),
            'user_data': self._hash_user_data(event, meta_event),
            'custom_data': self._build_custom_data(event, meta_event)
        }
        
        return meta_payload
    
    def _generate_event_id(self, event, meta_event):
        """Generar ID único para evento"""
        # Implementar lógica según mapping
        return f"{event.get('eventName')}_{event.get('timestamp')}"
    
    def _hash_user_data(self, event, meta_event):
        """Hash de datos de usuario"""
        user_data = {}
        for meta_field, event_field in meta_event.get('user_data', {}).items():
            if event_field in event:
                user_data[meta_field] = self.hash_pii(str(event[event_field]))
        return user_data
    
    def _build_custom_data(self, event, meta_event):
        """Construir custom_data para Meta"""
        custom_data = {}
        for meta_field, event_field in meta_event.get('custom_data', {}).items():
            if isinstance(event_field, str) and event_field in event:
                custom_data[meta_field] = event[event_field]
            elif isinstance(event_field, str) and event_field.startswith('custom_'):
                # Handle custom properties
                custom_data[meta_field] = event.get(event_field.replace('custom_property_', ''))
        return custom_data

# Uso
if __name__ == '__main__':
    # Cargar mapping
    with open('meta/capi-mapping.json') as f:
        mapping = json.load(f)['mapping']
    
    transformer = EventTransformer(mapping)
    
    # Ejemplo
    event = {
        'eventName': 'FormSubmit',
        'email': 'test@example.com',
        'firstName': 'John',
        'lastName': 'Doe',
        'leadValue': 1500,
        'timestamp': '2024-08-27T10:36:00Z'
    }
    
    meta_event = transformer.transform_to_meta(event)
    print(json.dumps(meta_event, indent=2))
